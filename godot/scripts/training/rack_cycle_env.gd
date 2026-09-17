class_name RackCycleEnv
extends TrainingEnvBase

## Stage R4: Full Rack Cycle Environment (Pick from Rack -> Stow -> Transit -> Conveyor Dropoff).
## Unifies multi-tier rack extraction, dynamic tray stowing, carrying transit across the bay,
## and elevated conveyor placement into a complete autonomous loop.

@export var arena_half_extent: float = 8.0

@onready var rack: ShelfPod = $ShelfPod
@onready var boxes_root: Node3D = $RackBoxes
@onready var conveyor: StaticBody3D = $ConveyorTable
@onready var drop_target_marker: Marker3D = $ConveyorTable/DropTargetMarker

const TOTE_SLOT_DEFS: Array[Dictionary] = [
	{"tier": 1, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 0.56, -0.60)},
	{"tier": 1, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 0.56, -0.60)},
	{"tier": 2, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 1.11, -0.60)},
	{"tier": 2, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 1.11, -0.60)},
	{"tier": 3, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 1.67, -0.60)},
	{"tier": 3, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 1.67, -0.60)},
	{"tier": 4, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 2.23, -0.60)},
	{"tier": 4, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 2.23, -0.60)},
]

const CONVEYOR_SLOTS: Array[Vector3] = [
	Vector3(-0.45, 0.77, -0.05),
	Vector3(-0.15, 0.77, -0.05),
	Vector3(0.15, 0.77, -0.05),
	Vector3(0.45, 0.77, -0.05),
]

enum CycleSubStage {
	NAVIGATE_TO_RACK = 1,
	DOCK_AND_PICK = 2,
	TRAY_STOW = 3,
	NAVIGATE_CARRYING = 4,
	CONVEYOR_DOCK = 5,
	UNSTOW_AND_PLACE = 6,
	CYCLE_COMPLETE = 7
}

const NeuralPolicyScript = preload("res://scripts/ai/neural_policy.gd")
@export var native_ai_mode: bool = false
@export var policy_json_path: String = "res://models/ppo_r4_policy.json"

var boxes: Array[ToteBox] = []
var delivery_manifest: Array[int] = []
var target_box_idx: int = 0
var target_tier: int = 1
var target_side_val: float = -1.0

var current_sub_stage: CycleSubStage = CycleSubStage.NAVIGATE_TO_RACK
var prev_sub_goal_dist: float = 0.0
var _sub_stage_steps: int = 0
var _stow_reset_timer: float = 0.0

var is_picked: bool = false
var is_stowed: bool = false
var is_placed: bool = false
var cycle_success: bool = false
var rack_toppled: bool = false
var wall_collided: bool = false
var box_dropped: bool = false
var total_placed_boxes: int = 0
var initial_stowed_count: int = 0
var is_full_tray_mode: bool = false
var dispatch_strategy: String = "auto"

var last_ik_dist: float = 0.0
var last_ik_err: String = ""
var trigger_attempted: bool = false
var failed_attempt: bool = false
var _pick_reward_given: int = 0
var _stow_reward_given: int = 0
var _place_reward_given: int = 0
var _completion_reward_given: bool = false

var native_policy: RefCounted = null
var _native_reset_timer: float = 0.0
var _native_action_accum: float = 0.0
var _current_native_act: Array = [0.0, 0.0, 0.0]

var _mat_normal: StandardMaterial3D
var _mat_highlight: StandardMaterial3D

func _ready() -> void:
	max_episode_steps = 650
	_setup_materials()
	_init_boxes()
	super._ready()

	# Check for command line flags for native execution
	var args = OS.get_cmdline_user_args()
	if args.is_empty(): args = OS.get_cmdline_args()
	for a in args:
		if a == "--native-ai" or a == "--native":
			native_ai_mode = true

	if native_ai_mode:
		_init_native_ai()

func _init_native_ai() -> void:
	native_policy = NeuralPolicyScript.new()
	if native_policy.load_from_json(policy_json_path):
		print("[RackCycleEnv] Zero-Latency Native In-Engine AI ACTIVATED!")
		Engine.physics_ticks_per_second = physics_hz
		get_tree().paused = false
		_on_arena_reset(0, 0.0)

func _setup_materials() -> void:
	_mat_normal = StandardMaterial3D.new()
	_mat_normal.albedo_color = Color(0.2, 0.65, 0.95, 1.0)
	_mat_normal.roughness = 0.4

	_mat_highlight = StandardMaterial3D.new()
	_mat_highlight.albedo_color = Color(1.0, 0.85, 0.1, 1.0)
	_mat_highlight.emission_enabled = true
	_mat_highlight.emission = Color(1.0, 0.85, 0.1, 1.0)
	_mat_highlight.emission_energy_multiplier = 0.6

func _init_boxes() -> void:
	boxes.clear()
	if not boxes_root:
		return
	for child in boxes_root.get_children():
		if child is ToteBox:
			boxes.append(child)

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()

	is_picked = false
	is_stowed = false
	is_placed = false
	cycle_success = false
	rack_toppled = false
	wall_collided = false
	box_dropped = false
	trigger_attempted = false
	failed_attempt = false
	_pick_reward_given = 0
	_stow_reward_given = 0
	_place_reward_given = 0
	_completion_reward_given = false
	_sub_stage_steps = 0
	_stow_reset_timer = 0.0
	current_sub_stage = CycleSubStage.NAVIGATE_TO_RACK
	total_placed_boxes = 0
	initial_stowed_count = 0
	is_full_tray_mode = false
	dispatch_strategy = str(last_reset_msg.get("dispatch_strategy", "auto"))

	if last_reset_msg.get("full_tray", false) or difficulty >= 2.0:
		is_full_tray_mode = true

	# 1. Reset Rack position and physics state at z = -4.0m, facing aisle (rotation.y = PI)
	if rack:
		rack.global_position = Vector3(0.0, 0.02, -4.0)
		rack.rotation = Vector3(0.0, PI, 0.0)
		rack.reset_rack()
		if difficulty < 0.70:
			rack.freeze = true
		else:
			rack.freeze = false

	# 2. Reset Conveyor Table at z = +4.0m
	if conveyor:
		conveyor.global_position = Vector3(0.0, 0.0, 4.0)
		conveyor.rotation = Vector3.ZERO
		if conveyor.has_method("reset_conveyor"):
			conveyor.reset_conveyor()

	# 3. Spawn AMR in mid-bay corridor (between rack and conveyor)
	if amr:
		amr.arm_tween_speed_scale = 3.5
		var spawn_x = rng.randf_range(-2.0, 2.0)
		var spawn_z = rng.randf_range(-1.2, 1.2)
		var spawn_yaw = rng.randf_range(-PI, PI)

		if is_full_tray_mode:
			spawn_x = rng.randf_range(-1.5, 1.5)
			spawn_z = rng.randf_range(-1.2, 0.5)
			spawn_yaw = rng.randf_range(-0.35, 0.35)

		amr.reset_robot(Vector3(spawn_x, 0.0, spawn_z), spawn_yaw)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# 4. Reset all 8 boxes onto rack
	for i in range(min(boxes.size(), TOTE_SLOT_DEFS.size())):
		var b = boxes[i]
		var s_def = TOTE_SLOT_DEFS[i]
		var world_box_pos = rack.to_global(s_def["offset"]) if rack else (Vector3(0.0, 0.0, -4.0) + s_def["offset"])
		b.visible = true
		if difficulty < 0.70:
			b.freeze = true
		else:
			b.freeze = false
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		if b.get_parent() != boxes_root:
			b.get_parent().remove_child(b)
			boxes_root.add_child(b)
		b.global_position = world_box_pos
		b.global_rotation = rack.global_rotation if rack else Vector3.ZERO
		if b.mesh_inst:
			b.mesh_inst.material_override = _mat_normal

	# 5. Uniformly select target SKU box (Tier 1-4, L/R)
	target_box_idx = rng.randi_range(0, min(boxes.size(), TOTE_SLOT_DEFS.size()) - 1)
	delivery_manifest.clear()

	if last_reset_msg.has("manifest") and last_reset_msg["manifest"] is Array:
		for val in last_reset_msg["manifest"]:
			delivery_manifest.append(int(val))
	elif last_reset_msg.has("delivery_count"):
		var req_count: int = int(last_reset_msg["delivery_count"])
		var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
		order.shuffle()
		for i in range(min(req_count, order.size())):
			delivery_manifest.append(order[i])
	elif last_reset_msg.get("multi_box", false) and not is_full_tray_mode:
		var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
		order.shuffle()
		delivery_manifest = [order[0], order[1]]
	elif is_full_tray_mode:
		delivery_manifest = []
	else:
		# Single box delivery default
		delivery_manifest = [target_box_idx]

	if not delivery_manifest.is_empty():
		target_box_idx = delivery_manifest[0]

	_update_active_target_box()

	if is_full_tray_mode and amr and amr.cargo_tray and boxes.size() >= 2:
		var b0 = boxes[0]
		var b1 = boxes[1]

		if b0.get_parent(): b0.get_parent().remove_child(b0)
		amr.cargo_tray.add_child(b0)
		b0.position = amr.slot_1_marker.position if amr.slot_1_marker else Vector3(0.0, 0.17, -0.22)
		b0.rotation = Vector3.ZERO
		b0.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b0.freeze = true
		b0.sleeping = false
		amr.add_collision_exception_with(b0)
		b0.add_collision_exception_with(amr)

		if b1.get_parent(): b1.get_parent().remove_child(b1)
		amr.cargo_tray.add_child(b1)
		b1.position = amr.slot_2_marker.position if amr.slot_2_marker else Vector3(0.0, 0.17, 0.22)
		b1.rotation = Vector3.ZERO
		b1.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b1.freeze = true
		b1.sleeping = false
		amr.add_collision_exception_with(b1)
		b1.add_collision_exception_with(amr)

		initial_stowed_count = 2
		is_picked = true
		is_stowed = true
		current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
	else:
		initial_stowed_count = 1

	max_episode_steps = max(750, delivery_manifest.size() * 1000)
	prev_sub_goal_dist = _get_dist_to_active_subgoal()

func _update_active_target_box() -> void:
	if target_box_idx >= 0 and target_box_idx < min(boxes.size(), TOTE_SLOT_DEFS.size()):
		var active_slot = TOTE_SLOT_DEFS[target_box_idx]
		target_tier = active_slot["tier"]
		target_side_val = active_slot["side_val"]
		for i in range(boxes.size()):
			if boxes[i] and is_instance_valid(boxes[i]) and boxes[i].mesh_inst:
				if i == target_box_idx:
					boxes[i].mesh_inst.material_override = _mat_highlight
				else:
					boxes[i].mesh_inst.material_override = _mat_normal

func _get_target_box_pos() -> Vector3:
	if target_box_idx < boxes.size() and boxes[target_box_idx]:
		return boxes[target_box_idx].global_position
	var s_def = TOTE_SLOT_DEFS[target_box_idx]
	return rack.to_global(s_def["offset"]) if rack else (Vector3(0.0, 0.0, -4.0) + s_def["offset"])

func _get_conveyor_drop_pos() -> Vector3:
	if drop_target_marker:
		return drop_target_marker.global_position
	elif conveyor:
		return conveyor.to_global(Vector3(0.0, 0.77, -0.05))
	return Vector3(0.0, 0.77, 3.95)

func _get_dist_to_conveyor() -> float:
	if not amr:
		return 8.0
	var c_pos = drop_target_marker.global_position if drop_target_marker else Vector3(0.0, 0.77, 3.95)
	var diff = amr.global_position - c_pos
	diff.y = 0.0
	return diff.length()

func _get_box_pos_by_idx(idx: int) -> Vector3:
	if idx >= 0 and idx < boxes.size() and boxes[idx] and is_instance_valid(boxes[idx]):
		return boxes[idx].global_position
	if idx >= 0 and idx < TOTE_SLOT_DEFS.size():
		var s_def = TOTE_SLOT_DEFS[idx]
		return rack.to_global(s_def["offset"]) if rack else (Vector3(0.0, 0.0, -4.0) + s_def["offset"])
	return Vector3.ZERO

func _get_active_subgoal_pos() -> Vector3:
	if current_sub_stage in [CycleSubStage.NAVIGATE_TO_RACK, CycleSubStage.DOCK_AND_PICK, CycleSubStage.TRAY_STOW]:
		return _get_target_box_pos()
	else:
		return drop_target_marker.global_position if drop_target_marker else Vector3(0.0, 0.77, 3.95)

func _get_dist_to_active_subgoal() -> float:
	if not amr:
		return 10.0
	var pos = _get_active_subgoal_pos()
	var diff = amr.global_position - pos
	diff.y = 0.0
	return diff.length()

func _get_subgoal_normal() -> Vector3:
	if current_sub_stage in [CycleSubStage.NAVIGATE_TO_RACK, CycleSubStage.DOCK_AND_PICK, CycleSubStage.TRAY_STOW]:
		# Bay faces towards -Z in local rack coords (global -Z from rack center)
		return -rack.global_transform.basis.z if rack else Vector3.FORWARD
	else:
		# Conveyor table faces toward aisle (-Z in global space)
		return Vector3(0.0, 0.0, -1.0)

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr:
		for i in range(16): obs.append(0.0)
		return obs

	# 0..3: Global arena pose normalized to 8m half-extent
	var norm_x = clampf(amr.global_position.x / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Normalized linear & angular velocity
	var norm_v = clampf(amr._manual_linear_vel / 2.8, -1.0, 1.0)
	var norm_w = clampf(amr._rl_target_v_ang / 2.2, -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative 3D vector to active sub-goal in robot local frame
	var sub_pos = _get_active_subgoal_pos()
	var local_rel = amr.global_transform.basis.inverse() * (sub_pos - amr.global_position)
	var dist = _get_dist_to_active_subgoal()
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying status (0.0 before stow, 1.0 during carrying/dropoff)
	var is_carrying = 1.0 if (current_sub_stage >= CycleSubStage.NAVIGATE_CARRYING and not is_placed) else 0.0
	obs.append(is_carrying)

	# 10: Tray status (0.5 for 1/2 boxes stowed)
	var tray_status = 0.5 if (is_stowed and not is_placed) else 0.0
	obs.append(tray_status)

	# 11..12: Nearest arena wall distance
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	# 13: Target Tier (normalized: 0.25..1.0 for rack; 0.0 for conveyor)
	var tier_val = (float(target_tier) / 4.0) if (current_sub_stage < CycleSubStage.NAVIGATE_CARRYING) else 0.0
	obs.append(tier_val)

	# 14: Target Slot Side (-1.0 Left, +1.0 Right for rack; 0.0 for conveyor)
	var side_val = target_side_val if (current_sub_stage < CycleSubStage.NAVIGATE_CARRYING) else 0.0
	obs.append(side_val)

	# 15: Face Alignment with active sub-goal
	var fwd = -amr.global_transform.basis.z
	var sub_norm = _get_subgoal_normal()
	var face_align = clampf(fwd.dot(-sub_norm), -1.0, 1.0)
	obs.append(face_align)

	return obs

func _apply_action(action: Array) -> void:
	if not amr:
		return

	# If arm is actively tweening / manipulating, brake chassis to halt
	if amr._is_arm_tweening:
		amr.set_rl_control(0.0, 0.0)
		return

	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0

	var cur_dist = _get_dist_to_active_subgoal()
	var forward = -amr.global_transform.basis.z
	var sub_norm = _get_subgoal_normal()
	var face_align = forward.dot(-sub_norm)

	# Speed governance near obstacles
	var max_lin_speed: float = 2.8
	if cur_dist <= 2.2:
		max_lin_speed = 0.45
	elif cur_dist <= 3.2:
		max_lin_speed = clampf(0.45 + (cur_dist - 2.2) * 2.3, 0.45, 2.8)

	if cur_dist > 1.50:
		v_lin = clampf(v_lin, 0.0, 1.0)
	else:
		v_lin = clampf(v_lin, -0.20, 1.0)

	var lin_vel = clampf(v_lin * 2.8, -0.4, max_lin_speed)
	var ang_vel = v_ang * 2.2
	amr.set_rl_control(lin_vel, ang_vel)

	# Trigger logic based on mission phase
	if current_sub_stage in [CycleSubStage.NAVIGATE_TO_RACK, CycleSubStage.DOCK_AND_PICK] and not is_picked:
		var target_box: ToteBox = boxes[target_box_idx] if target_box_idx < boxes.size() else null
		if target_box and is_instance_valid(target_box):
			var local_target = amr.arm.to_local(target_box.global_position)
			var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)
			var in_reach = ik.success and face_align >= 0.35 and not rack_toppled

			if in_reach and trigger > 0.0:
				trigger_attempted = true
				current_sub_stage = CycleSubStage.DOCK_AND_PICK
				amr.set_rl_control(0.0, 0.0) # Halt chassis immediately on pick trigger
				amr.trigger_rl_action(target_box)
			elif trigger > 0.35 and not in_reach and cur_dist > 2.2:
				failed_attempt = true

	elif current_sub_stage in [CycleSubStage.NAVIGATE_CARRYING, CycleSubStage.CONVEYOR_DOCK] and is_stowed and not is_placed:
		# Conveyor table dropoff trigger (slot-aware for multi-box)
		var drop_pos = _get_conveyor_drop_pos()
		var ik_deck = ArmIKSolver.solve_local(amr.arm.to_local(drop_pos))
		last_ik_dist = ik_deck.target_distance
		last_ik_err = ik_deck.error_message
		var at_conveyor = (cur_dist <= 1.85 and face_align >= 0.40 and amr.current_speed <= 0.60 and ik_deck.success)

		if trigger > 0.0:
			trigger_attempted = true
			if at_conveyor:
				var started: bool = amr.execute_dynamic_unstow_and_place(drop_pos)
				if started:
					current_sub_stage = CycleSubStage.UNSTOW_AND_PLACE
			else:
				print("[ConveyorTrigger Failed] dist=%.2f fa=%.2f spd=%.2f ik=%s err=%s" % [cur_dist, face_align, amr.current_speed, str(ik_deck.success), ik_deck.error_message])

func _physics_process(delta: float) -> void:
	if amr:
		# Auto-chain: Held in aisle -> Dynamic Stow
		if current_sub_stage == CycleSubStage.DOCK_AND_PICK:
			if amr.held_box != null:
				is_picked = true
			if amr.arm_motion_state == amr.ArmMotionState.HELD_READY:
				current_sub_stage = CycleSubStage.TRAY_STOW
				amr.execute_dynamic_stow()

		# Auto-chain: Stowed in tray -> Autonomous Decision: Batch (Fill Tray) vs Immediate (Move Out)
		if current_sub_stage == CycleSubStage.TRAY_STOW:
			if amr.get_stowed_box_count() > 0 and not amr._is_arm_tweening:
				# Pop the box that was just stowed from the manifest
				if not delivery_manifest.is_empty():
					delivery_manifest.pop_front()

				var can_batch: bool = (amr.get_stowed_box_count() < 2 and not delivery_manifest.is_empty())
				var choose_batch: bool = false

				if can_batch:
					if dispatch_strategy == "batch":
						choose_batch = true
					elif dispatch_strategy == "immediate":
						choose_batch = false
					else:
						# "auto" Cost-Effectiveness Evaluation:
						# Evaluate transit cost delta:
						# Cost of batching (drive to next rack box + drive to conveyor)
						# vs Cost of immediate delivery (drive to conveyor + round-trip back to next rack + drive to conveyor)
						var next_target = delivery_manifest[0]
						var next_box_pos = _get_box_pos_by_idx(next_target)
						var dist_to_next_rack = amr.global_position.distance_to(next_box_pos)
						var dist_to_conveyor = _get_dist_to_conveyor()

						var cost_batch = dist_to_next_rack + dist_to_conveyor
						var cost_immediate = (2.0 * dist_to_conveyor) + dist_to_next_rack
						choose_batch = (cost_batch < cost_immediate)

				if choose_batch:
					target_box_idx = delivery_manifest[0]
					_update_active_target_box()
					is_picked = false
					is_stowed = false
					current_sub_stage = CycleSubStage.NAVIGATE_TO_RACK
					prev_sub_goal_dist = _get_dist_to_active_subgoal()
				else:
					is_stowed = true
					current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
					prev_sub_goal_dist = _get_dist_to_active_subgoal()

		# Auto-chain: Unstow & placed on conveyor -> Unstow next box or Return to Rack or Cycle Complete
		if current_sub_stage == CycleSubStage.UNSTOW_AND_PLACE:
			if not amr._is_arm_tweening and amr.held_box == null:
				total_placed_boxes += 1

				if amr.get_stowed_box_count() > 0:
					# Unstow the second box from the tray onto the conveyor!
					var next_pos = _get_conveyor_drop_pos()
					var started: bool = amr.execute_dynamic_unstow_and_place(next_pos)
					if not started:
						print("[UNSTOW RECOVERY] Could not unstow remaining box, transitioning out")
						if is_full_tray_mode or delivery_manifest.is_empty():
							is_placed = true
							cycle_success = true
							current_sub_stage = CycleSubStage.CYCLE_COMPLETE
						else:
							current_sub_stage = CycleSubStage.NAVIGATE_TO_RACK
				elif is_full_tray_mode or delivery_manifest.is_empty():
					# All boxes delivered!
					is_placed = true
					cycle_success = true
					current_sub_stage = CycleSubStage.CYCLE_COMPLETE
				else:
					# Tray is empty, but manifest still has more boxes! Return to rack!
					target_box_idx = delivery_manifest[0]
					_update_active_target_box()
					is_picked = false
					is_stowed = false
					is_placed = false
					current_sub_stage = CycleSubStage.NAVIGATE_TO_RACK
					prev_sub_goal_dist = _get_dist_to_active_subgoal()

	# Auto-cycle to next target after completing cycle (for interactive viewing)
	if cycle_success:
		_stow_reset_timer += delta
		if _stow_reset_timer >= 2.0:
			_stow_reset_timer = 0.0
			_on_arena_reset(0, 0.0)

	# Native AI step process
	if native_ai_mode and native_policy:
		if cycle_success or rack_toppled or wall_collided or step_count >= max_episode_steps:
			_native_reset_timer += delta
			if _native_reset_timer > 1.5:
				_native_reset_timer = 0.0
				_on_arena_reset(0, 0.0)
			return

		_native_action_accum += delta
		var action_dt = 1.0 / float(max(1, action_hz))
		if _native_action_accum >= action_dt:
			_native_action_accum -= action_dt
			step_count += 1
			var obs = _compute_observation()
			_current_native_act = native_policy.predict(obs)

		_apply_action(_current_native_act)
		_compute_reward(_current_native_act)

func _compute_reward(action: Array) -> float:
	var reward: float = 0.0
	if not amr or not rack:
		return reward

	var cur_dist = _get_dist_to_active_subgoal()
	var forward = -amr.global_transform.basis.z
	var sub_norm = _get_subgoal_normal()
	var face_align = forward.dot(-sub_norm)

	# 1. Distance shaping progress towards active sub-goal
	if not amr._is_arm_tweening and not cycle_success:
		var progress = prev_sub_goal_dist - cur_dist
		reward += progress * 3.5
		prev_sub_goal_dist = cur_dist

		# Alignment bonus when approaching
		if cur_dist <= 3.5:
			reward += maxf(0.0, face_align) * 0.20

	# 2. Rack tilt & topple penalty
	var up_alignment = rack.global_transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.94:
		rack_toppled = true
		reward -= 10.0

	# 3. Wall collision penalty
	var wall_limit = arena_half_extent - 0.40
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	# 4. Phase-Specific Shaping
	var trigger = float(action[2]) if action.size() > 2 else 0.0

	match current_sub_stage:
		CycleSubStage.NAVIGATE_TO_RACK:
			var target_box: ToteBox = boxes[target_box_idx] if target_box_idx < boxes.size() else null
			if target_box and is_instance_valid(target_box) and not is_stowed:
				var local_target = amr.arm.to_local(target_box.global_position)
				var ik_res: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)
				last_ik_dist = ik_res.target_distance
				last_ik_err = ik_res.error_message

				if cur_dist <= 2.6:
					if ik_res.target_distance > ArmIKSolver.MAX_REACH:
						reward -= 0.50 * (ik_res.target_distance - ArmIKSolver.MAX_REACH)
					elif ik_res.success and face_align >= 0.35:
						reward += 0.05

		CycleSubStage.DOCK_AND_PICK:
			var current_stowed = (amr.get_stowed_box_count() if amr else 0) + total_placed_boxes
			if is_picked and _pick_reward_given <= current_stowed:
				reward += 10.0
				_pick_reward_given = current_stowed + 1

		CycleSubStage.TRAY_STOW:
			var total_stowed_now = (amr.get_stowed_box_count() if amr else 0) + total_placed_boxes
			if total_stowed_now > _stow_reward_given:
				reward += 5.0
				_stow_reward_given = total_stowed_now

		CycleSubStage.NAVIGATE_CARRYING, CycleSubStage.CONVEYOR_DOCK:
			# Guidance to conveyor table
			if cur_dist <= 2.2 and face_align >= 0.40:
				reward += 0.15
				if trigger > 0.0 and amr.current_speed <= 0.45:
					reward += 0.50

		CycleSubStage.UNSTOW_AND_PLACE, CycleSubStage.CYCLE_COMPLETE:
			if total_placed_boxes > _place_reward_given:
				reward += 15.0
				_place_reward_given = total_placed_boxes
			if cycle_success and not _completion_reward_given:
				reward += 30.0 + maxf(0.0, face_align) * 5.0
				_completion_reward_given = true

	# 5. Check for dropped / fallen boxes
	for b in boxes:
		if b and is_instance_valid(b) and b.global_position.y < -0.20:
			box_dropped = true
			reward -= 15.0
			break

	# 6. Failed premature trigger penalty
	if failed_attempt:
		reward -= 0.05
		failed_attempt = false

	# 7. Step penalty
	reward -= 0.02
	return reward

func _is_terminated() -> bool:
	return cycle_success or rack_toppled or wall_collided or box_dropped

func _get_info() -> Dictionary:
	var forward = -amr.global_transform.basis.z if amr else Vector3.FORWARD
	var sub_norm = _get_subgoal_normal()
	var fa = forward.dot(-sub_norm) if amr else 0.0
	var col_name: String = ""
	if amr and amr.get_slide_collision_count() > 0:
		var c = amr.get_slide_collision(0).get_collider()
		if c:
			col_name = c.name
			if c.get_parent(): col_name = c.get_parent().name + "/" + col_name

	var fwd_vec = -amr.global_transform.basis.z if amr else Vector3.FORWARD
	return {
		"amr_pos": [amr.global_position.x, amr.global_position.z] if amr else [0.0, 0.0],
		"amr_yaw": amr.rotation.y if amr else 0.0,
		"amr_fwd": [fwd_vec.x, fwd_vec.z],
		"current_sub_stage": int(current_sub_stage),
		"is_picked": is_picked,
		"is_stowed": is_stowed,
		"is_placed": is_placed,
		"cycle_success": cycle_success,
		"rack_toppled": rack_toppled,
		"wall_collided": wall_collided,
		"target_tier": target_tier,
		"target_side": target_side_val,
		"dist_to_subgoal": prev_sub_goal_dist,
		"face_align": fa,
		"current_speed": amr.current_speed if amr else 0.0,
		"manual_lin_vel": amr._manual_linear_vel if amr else 0.0,
		"target_v_lin": amr._rl_target_v_lin if amr else 0.0,
		"amr_vel": [amr.velocity.x, amr.velocity.z] if amr else [0.0, 0.0],
		"step_count": step_count,
		"ik_dist": last_ik_dist,
		"ik_err": last_ik_err,
		"last_arm_hit": amr.last_arm_hit if amr else "",
		"trigger_attempted": trigger_attempted,
		"failed_attempt": failed_attempt,
		"col_name": col_name,
		"stowed_box_count": amr.get_stowed_box_count() if amr else 0,
		"total_placed_boxes": total_placed_boxes,
		"initial_stowed_count": initial_stowed_count,
		"is_full_tray_mode": is_full_tray_mode,
		"delivery_manifest_remaining": delivery_manifest.size(),
		"delivery_manifest": delivery_manifest.duplicate(),
		"is_manifest_empty": delivery_manifest.is_empty(),
		"cargo_tray_attached": (amr.cargo_tray != null and amr.cargo_tray.get_parent() != null and amr.cargo_tray.get_parent().name == "Chassis"),
		"all_boxes_transported": (is_placed and (amr.get_stowed_box_count() if amr else 0) == 0 and delivery_manifest.is_empty()),
		"box_dropped": box_dropped,
		"dispatch_strategy": dispatch_strategy,
	}
