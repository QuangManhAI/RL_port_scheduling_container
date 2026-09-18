class_name RackDockingEnv
extends TrainingEnvBase

## Stage R1: Gentle Rack Navigation & Docking Environment.
## Teaches the AMR to navigate from across the arena to dock square and stable
## in front of an assigned tier/slot on a physical 4-tier storage rack (ShelfPod).
## Implements a 2-stage physics curriculum (frozen until diff >= 0.70, then dynamic).

@export var arena_half_extent: float = 7.0

@onready var rack: ShelfPod = $ShelfPod
@onready var boxes_root: Node3D = $RackBoxes

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

const NeuralPolicyScript = preload("res://scripts/ai/neural_policy.gd")
@export var native_ai_mode: bool = false
@export var policy_json_path: String = "res://models/ppo_r1_policy.json"

var boxes: Array[ToteBox] = []
var target_box_idx: int = 0
var target_tier: int = 1
var target_side_val: float = -1.0
var prev_sub_goal_dist: float = 0.0

var docking_success: bool = false
var rack_toppled: bool = false
var wall_collided: bool = false

var native_policy: RefCounted = null
var _native_reset_timer: float = 0.0
var _native_action_accum: float = 0.0
var _current_native_act: Array = [0.0, 0.0, 0.0]

var _mat_normal: StandardMaterial3D
var _mat_highlight: StandardMaterial3D

func _ready() -> void:
	max_episode_steps = 300
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
		print("[RackDockingEnv] Zero-Latency Native Dual-Clock In-Engine AI ACTIVATED!")
		Engine.physics_ticks_per_second = physics_hz
		print("  - Simulation Clock (Physics): %d Hz (Continuous high precision)" % physics_hz)
		print("  - Action Decision Clock:      %d Hz (True step pacing)" % action_hz)
		get_tree().paused = false
		_on_arena_reset(0, 0.0)

func _physics_process(delta: float) -> void:
	if not native_ai_mode or not native_policy:
		return

	if docking_success or rack_toppled or wall_collided or step_count >= max_episode_steps:
		_native_reset_timer += delta
		if _native_reset_timer > 1.2:
			_native_reset_timer = 0.0
			_on_arena_reset(0, 0.0)
		return

	# Dual-clock accumulator: query neural policy at action_hz (60 Hz)
	_native_action_accum += delta
	var action_dt = 1.0 / float(max(1, action_hz))
	if _native_action_accum >= action_dt:
		_native_action_accum -= action_dt
		step_count += 1
		var obs = _compute_observation()
		_current_native_act = native_policy.predict(obs)

	# Apply action at 200 Hz simulation physics
	_apply_action(_current_native_act)
	_compute_reward(_current_native_act)

func _setup_materials() -> void:
	_mat_normal = StandardMaterial3D.new()
	_mat_normal.albedo_color = Color(0.2, 0.65, 0.95, 1.0)
	_mat_normal.roughness = 0.4

	_mat_highlight = StandardMaterial3D.new()
	_mat_highlight.albedo_color = Color(1.0, 0.85, 0.1, 1.0)
	_mat_highlight.emission_enabled = true
	_mat_highlight.emission = Color(1.0, 0.75, 0.05, 1.0)
	_mat_highlight.emission_energy_multiplier = 2.0

func _init_boxes() -> void:
	if not boxes_root:
		return
	for child in boxes_root.get_children():
		if child is ToteBox:
			boxes.append(child)

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()

	docking_success = false
	rack_toppled = false
	wall_collided = false

	# 1. Reset Rack position and physics state
	if rack:
		rack.global_position = Vector3(0.0, 0.02, 0.0)
		rack.rotation = Vector3.ZERO
		rack.reset_rack()
		# Progressive Physics Curriculum:
		# Frozen until difficulty >= 0.70 to learn spatial approach first,
		# then full unconstrained RigidBody3D dynamics where impacts cause toppling.
		if difficulty < 0.70:
			rack.freeze = true
		else:
			rack.freeze = false

	# 2. Reset and dock all 8 boxes on rack
	for i in range(min(boxes.size(), TOTE_SLOT_DEFS.size())):
		var b = boxes[i]
		var s_def = TOTE_SLOT_DEFS[i]
		var world_box_pos = rack.global_position + s_def["offset"]
		b.visible = true
		if difficulty < 0.70:
			b.freeze = true
		else:
			b.freeze = false
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.global_position = world_box_pos
		b.rotation = Vector3.ZERO
		if b.mesh_inst:
			b.mesh_inst.material_override = _mat_normal

	# 3. Uniformly select random target box (Tier 1-4, L/R)
	target_box_idx = rng.randi_range(0, min(boxes.size(), TOTE_SLOT_DEFS.size()) - 1)
	var active_slot = TOTE_SLOT_DEFS[target_box_idx]
	target_tier = active_slot["tier"]
	target_side_val = active_slot["side_val"]

	# Highlight active target box
	if target_box_idx < boxes.size():
		var target_box = boxes[target_box_idx]
		if target_box.mesh_inst:
			target_box.mesh_inst.material_override = _mat_highlight

	# 4. Spawn AMR at randomized approach sector (distance 2.8m to 4.8m in front of rack bay)
	if amr:
		var spawn_angle = rng.randf_range(-PI * 0.88, -PI * 0.12)
		var spawn_dist = rng.randf_range(2.8, 4.8)
		var spawn_x = clampf(cos(spawn_angle) * spawn_dist, -(arena_half_extent - 1.2), arena_half_extent - 1.2)
		var spawn_z = -absf(sin(spawn_angle) * spawn_dist) # In front of rack bay
		var spawn_yaw = rng.randf_range(-PI, PI) # Full 360-degree arbitrary initial heading

		amr.reset_robot(Vector3(spawn_x, 0.0, spawn_z), spawn_yaw)
		amr.is_manual_control = false
		amr.is_rl_control = true

	prev_sub_goal_dist = _get_dist_to_target_box()

func _get_target_box_pos() -> Vector3:
	if target_box_idx < boxes.size() and boxes[target_box_idx]:
		return boxes[target_box_idx].global_position
	# Fallback to slot definition
	var s_def = TOTE_SLOT_DEFS[target_box_idx]
	return rack.global_position + s_def["offset"]

func _get_dist_to_target_box() -> float:
	if not amr:
		return 10.0
	var pos = _get_target_box_pos()
	var diff = amr.global_position - pos
	diff.y = 0.0 # Ground plane horizontal distance for chassis driving
	return diff.length()

func _get_rack_face_normal() -> Vector3:
	# Bay face points towards -Z in local rack coordinates
	if not rack:
		return Vector3.FORWARD
	return -rack.global_transform.basis.z

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

	# 6..8: Relative 3D vector to target box in robot local frame
	var box_pos = _get_target_box_pos()
	var local_rel = amr.global_transform.basis.inverse() * (box_pos - amr.global_position)
	var dist = _get_dist_to_target_box()
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9..10: Carrying status (0.0 for docking) & Tray status (0.0)
	obs.append(0.0)
	obs.append(0.0)

	# 11..12: Nearest arena wall distance
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	# 13: Target Tier (normalized: 0.25, 0.50, 0.75, 1.0)
	obs.append(float(target_tier) / 4.0)

	# 14: Target Slot Side (-1.0 for Left, +1.0 for Right)
	obs.append(target_side_val)

	# 15: Rack Face Alignment: dot product between robot forward and rack outward face normal
	# Robot forward is -basis.z. When robot is directly facing the rack bay opening, alignment is ~1.0
	var fwd = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	# Robot approaching from front of rack faces opposite the rack face normal
	var face_align = clampf(fwd.dot(-rack_face_norm), -1.0, 1.0)
	obs.append(face_align)

	return obs

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var to_box = (_get_target_box_pos() - amr.global_position).normalized()
	var align_to_box = forward.dot(to_box)

	# 180-degree symmetry breaker
	if align_to_box < -0.85 and cur_dist > 1.5 and abs(v_ang) < 0.15:
		v_ang = 0.8

	# Disallow reverse when approaching from distance to prevent hovering/retreating
	if cur_dist > 1.50:
		v_lin = clampf(v_lin, 0.0, 1.0)
	else:
		v_lin = clampf(v_lin, -0.15, 1.0)

	# Dynamic safety corridor speed governance near rack
	var max_lin_speed: float = 2.8
	if cur_dist <= 2.35:
		# Inside docking zone, govern speed to gentle docking crawl
		max_lin_speed = 0.40
	elif cur_dist <= 3.2:
		# Smooth deceleration into docking zone
		max_lin_speed = clampf(0.40 + (cur_dist - 2.35) * 2.5, 0.40, 2.8)

	var lin_vel = clampf(v_lin * 2.8, -0.4, max_lin_speed)
	var ang_vel = v_ang * 2.2
	amr.set_rl_control(lin_vel, ang_vel)

func _compute_reward(_action: Array) -> float:
	var reward: float = 0.0
	if not amr or not rack:
		return reward

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	var face_align = forward.dot(-rack_face_norm)

	# 1. Distance shaping reward (pulls robot directly to rack mouth)
	var progress = prev_sub_goal_dist - cur_dist
	reward += progress * 4.0
	prev_sub_goal_dist = cur_dist

	# 2. Alignment bonus when approaching
	if cur_dist <= 3.5:
		reward += maxf(0.0, face_align) * 0.25

	# 3. Controlled speed near rack (< 1.6m): penalize high-speed ramming only
	if cur_dist <= 1.6 and amr.current_speed > 0.45:
		reward -= 0.15 * (amr.current_speed - 0.45)

	# 4. Rack tilt & topple detection
	var up_alignment = rack.global_transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.94: # Tilt > ~20 degrees
		rack_toppled = true
		reward -= 10.0

	# 5. Step penalty (drives urgency to dock)
	reward -= 0.02

	# 6. Kinematic Docking Completion Gate:
	# Arm shoulder is 0.30m ahead of AMR center, with MAX_REACH = 2.15m.
	# Effective horizontal reach from AMR center to tote box is up to 2.35m.
	# - Standard Dock: cur_dist <= 2.35m, face_align >= 0.60 (~53 deg), speed <= 0.45 m/s
	# - Close Dock: cur_dist <= 1.60m, face_align >= 0.40 (~66 deg), speed <= 0.45 m/s
	var is_stable = up_alignment >= 0.985 # Rack tilt < 10 deg
	var is_standard_dock = (cur_dist <= 2.35 and face_align >= 0.60 and amr.current_speed <= 0.45 and is_stable)
	var is_close_dock = (cur_dist <= 1.60 and face_align >= 0.40 and amr.current_speed <= 0.45 and is_stable)

	if is_standard_dock or is_close_dock:
		docking_success = true
		reward += 10.0 + face_align * 3.0

	# 7. Wall collision penalty
	var wall_limit = arena_half_extent - 0.40
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return docking_success or rack_toppled or wall_collided

func _is_truncated() -> bool:
	return step_count >= max_episode_steps

func _get_info() -> Dictionary:
	var forward = -amr.global_transform.basis.z if amr else Vector3.FORWARD
	var rack_norm = _get_rack_face_normal()
	var fa = forward.dot(-rack_norm) if amr else 0.0
	var col_name: String = ""
	if amr and amr.get_slide_collision_count() > 0:
		var c = amr.get_slide_collision(0).get_collider()
		if c:
			col_name = c.name
			if c.get_parent(): col_name = c.get_parent().name + "/" + col_name
	return {
		"docking_success": docking_success,
		"rack_toppled": rack_toppled,
		"wall_collided": wall_collided,
		"target_tier": target_tier,
		"target_side": target_side_val,
		"dist_to_target": prev_sub_goal_dist,
		"dist_to_subgoal": prev_sub_goal_dist,
		"face_align": fa,
		"current_speed": amr.current_speed if amr else 0.0,
		"step_count": step_count,
		"arm_hit": amr.last_arm_hit if amr else "",
		"col_count": amr.get_slide_collision_count() if amr else 0,
		"col_name": col_name,
	}
