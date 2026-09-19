class_name MultiAgentEnv
extends TrainingEnvBase

## Multi-Agent Environment: 2 AMRs picking and delivering 8 ToteBoxes to a Drop Zone.
## Supports dual S5-policy inference with dynamic task allocation and mutual yielding.

@export var arena_half_extent: float = 10.0

@onready var amr_1: AmrRobot = $AMR_1
@onready var amr_2: AmrRobot = $AMR_2

@onready var box_1: ToteBox = $Box_1
@onready var box_2: ToteBox = $Box_2
@onready var box_3: ToteBox = $Box_3
@onready var box_4: ToteBox = $Box_4
@onready var box_5: ToteBox = $Box_5
@onready var box_6: ToteBox = $Box_6
@onready var box_7: ToteBox = $Box_7
@onready var box_8: ToteBox = $Box_8

@onready var drop_zone: Node3D = $DropZoneMarker

enum BoxStatus {
	ON_FLOOR = 0,
	CARRIED_BY_AMR_1 = 1,
	CARRIED_BY_AMR_2 = 2,
	DELIVERED = 3
}

var boxes: Array[ToteBox] = []
var box_states: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var delivered_count: int = 0
var robot_collisions: int = 0
var wall_collisions: int = 0
var all_delivered: bool = false
var prev_total_dist: float = 0.0

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

@export var native_ai_mode: bool = false
@export var use_s6_obs: bool = false
@export var policy_json_path: String = "res://models/ppo_s6_policy.json"
@export var physics_hz: int = 150  ## High-frequency continuous physics clock (150 Ticks/s)
@export var action_hz: int = 60    ## Neural network decision frequency (60 Hz)
@export var speed_scale: float = 1.5 ## 1.5x Faster Motion multiplier

var native_policy: NeuralPolicy = null
var _native_reset_timer: float = 0.0
var _action_tick_accumulator: float = 0.0
var _current_joint_act: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var prev_delivered_count: int = 0
var dropzone_reserver: int = 0  ## 0 = free, 1 = AMR 1 reserved, 2 = AMR 2 reserved
var _dropzone_reserve_start_time: float = 0.0
var _is_undocking_1: bool = false
var _undock_start_1: float = 0.0
var _is_undocking_2: bool = false
var _undock_start_2: float = 0.0
var _deadlock_duration: float = 0.0
var _deadlock_escape_timer: float = 0.0
var _deadlock_escape_robot: int = 0

func _ready() -> void:
	max_episode_steps = 3600
	amr = $AMR_1 # Keep base class reference happy
	boxes = [box_1, box_2, box_3, box_4, box_5, box_6, box_7, box_8]
	super._ready()

	# Check for command line flags
	var args = OS.get_cmdline_user_args()
	if args.is_empty(): args = OS.get_cmdline_args()
	for arg in args:
		if arg == "--native":
			native_ai_mode = true
		elif arg == "--s6":
			use_s6_obs = true
		elif arg.begins_with("--policy="):
			policy_json_path = arg.replace("--policy=", "")
		elif arg.begins_with("--physics-hz="):
			physics_hz = int(arg.replace("--physics-hz=", ""))
		elif arg.begins_with("--action-hz="):
			action_hz = int(arg.replace("--action-hz=", ""))
		elif arg.begins_with("--speed="):
			speed_scale = float(arg.replace("--speed=", ""))

	if native_ai_mode:
		_init_native_ai()

func _unhandled_input(event: InputEvent) -> void:
	if not native_ai_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			speed_scale = 1.5
			print("[Control] Mode 1: 1.5x Speed (Fast & Snappy)")
		elif event.keycode == KEY_2:
			speed_scale = 1.0
			print("[Control] Mode 2: 1.0x Speed (Standard)")
		elif event.keycode == KEY_3:
			speed_scale = 2.0
			print("[Control] Mode 3: 2.0x Turbo Speed")
		elif event.keycode == KEY_EQUAL: # '+' key
			speed_scale += 0.25
			print("[Control] Speed increased to: %.2fx" % speed_scale)
		elif event.keycode == KEY_MINUS: # '-' key
			speed_scale = maxf(0.25, speed_scale - 0.25)
			print("[Control] Speed decreased to: %.2fx" % speed_scale)
		elif event.keycode == KEY_R:
			_on_arena_reset(0, 0.0)
			print("[Control] Arena Reset!")
		elif event.keycode == KEY_SPACE:
			get_tree().paused = not get_tree().paused
			print("[Control] Paused: ", get_tree().paused)

func _init_native_ai() -> void:
	native_policy = NeuralPolicy.new()
	if native_policy.load_from_json(policy_json_path):
		if native_policy.w0.size() > 0 and (native_policy.w0[0] as Array).size() >= 17:
			use_s6_obs = true
			print("[MultiAgentEnv] Zero-Latency Native Dual-Clock In-Engine AI ACTIVATED! (PPO S6 Multi-Agent Awareness)")
		else:
			use_s6_obs = false
			print("[MultiAgentEnv] Zero-Latency Native Dual-Clock In-Engine AI ACTIVATED! (PPO S5 Single-Agent Baseline)")
		Engine.physics_ticks_per_second = physics_hz
		print("  - Simulation Clock (Physics): %d Hz (Continuous high precision)" % physics_hz)
		print("  - Action Decision Clock:      %d Hz (True step pacing)" % action_hz)
		print("  - Speed Scale:                %.2fx" % speed_scale)
		get_tree().paused = false
		_on_arena_reset(0, 0.0)

func _physics_process(delta: float) -> void:
	if not native_ai_mode or not native_policy:
		return

	if all_delivered:
		_native_reset_timer += delta
		if _native_reset_timer > 1.5:
			_native_reset_timer = 0.0
			_on_arena_reset(0, 0.0)
		return

	# Dual-clock accumulator: only update neural network decision at action_hz (e.g. 60 Hz)
	_action_tick_accumulator += delta
	var action_dt = 1.0 / float(max(1, action_hz))

	if _action_tick_accumulator >= action_dt:
		_action_tick_accumulator -= action_dt
		step_count += 1

		# Neural network evaluates decision at clean action_hz pace
		var is_s6 = native_policy.w0.size() > 0 and (native_policy.w0[0] as Array).size() >= 17
		var obs1 = _compute_s6_obs(amr_1, 1) if is_s6 else _compute_s5_obs(amr_1, 1)
		var obs2 = _compute_s6_obs(amr_2, 2) if is_s6 else _compute_s5_obs(amr_2, 2)

		var act1 = native_policy.predict(obs1)
		var act2 = native_policy.predict(obs2)

		_current_joint_act = [act1[0], act1[1], act1[2], act2[0], act2[1], act2[2]]

	# Apply continuous physics motion at every single high-rate tick (150 Hz)
	_apply_action_scaled(_current_joint_act, speed_scale, delta)

	if step_count >= max_episode_steps:
		_on_arena_reset(0, 0.0)

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	step_count = 0
	delivered_count = 0
	prev_delivered_count = 0
	robot_collisions = 0
	wall_collisions = 0
	all_delivered = false
	dropzone_reserver = 0
	_dropzone_reserve_start_time = 0.0
	_is_undocking_1 = false
	_undock_start_1 = 0.0
	_is_undocking_2 = false
	_undock_start_2 = 0.0
	_deadlock_duration = 0.0
	_deadlock_escape_timer = 0.0
	_deadlock_escape_robot = 0
	box_states = [0, 0, 0, 0, 0, 0, 0, 0]

	# Reset AMR 1 (spawns on West with slight angle/pos randomization)
	if amr_1:
		var yaw1 = rng.randf_range(-0.35, 0.35)
		var spawn1 = Vector3(-5.0 + rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.8, 0.8))
		amr_1.reset_robot(spawn1, yaw1)
		amr_1.is_manual_control = false
		amr_1.is_rl_control = true
		amr_1.held_box = null
		_clear_cargo_tray(amr_1)

	# Reset AMR 2 (spawns on East with slight angle/pos randomization)
	if amr_2:
		var yaw2 = PI + rng.randf_range(-0.35, 0.35)
		var spawn2 = Vector3(5.0 + rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.8, 0.8))
		amr_2.reset_robot(spawn2, yaw2)
		amr_2.is_manual_control = false
		amr_2.is_rl_control = true
		amr_2.held_box = null
		_clear_cargo_tray(amr_2)

	# Reset Drop Zone to center
	if drop_zone:
		drop_zone.global_position = Vector3(0.0, 0.02, 0.0)

	# Scatter 8 boxes randomly
	var occupied_positions: Array[Vector3] = [amr_1.global_position, amr_2.global_position, drop_zone.global_position]
	for i in range(boxes.size()):
		var b = boxes[i]
		if not b:
			continue
		if b.get_parent() != self:
			if b.get_parent():
				b.get_parent().remove_child(b)
			add_child(b)

		b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.visible = true

		var pos = _generate_scatter_position(occupied_positions, 2.5)
		occupied_positions.append(pos)
		b.global_position = pos
		b.rotation = Vector3(0.0, rng.randf_range(-PI, PI), 0.0)

	prev_total_dist = _calculate_system_potential()

func _clear_cargo_tray(robot: AmrRobot) -> void:
	if robot and robot.cargo_tray:
		for child in robot.cargo_tray.get_children():
			if child is ToteBox:
				robot.cargo_tray.remove_child(child)
				if child.get_parent() != self:
					add_child(child)

func _generate_scatter_position(occupied: Array[Vector3], min_sep: float) -> Vector3:
	var margin: float = 2.0
	var max_r = arena_half_extent - margin
	for attempt in range(60):
		var x = rng.randf_range(-max_r, max_r)
		var z = rng.randf_range(-max_r, max_r)
		var candidate = Vector3(x, 0.16, z)
		var ok = true
		if drop_zone and candidate.distance_to(drop_zone.global_position) < 3.2:
			ok = false
		if ok:
			for p in occupied:
				if candidate.distance_to(p) < min_sep:
					ok = false
					break
		if ok:
			return candidate
	return Vector3(rng.randf_range(-max_r, max_r), 0.16, rng.randf_range(-max_r, max_r))

func _is_carrying(robot_id: int) -> bool:
	var target_state = BoxStatus.CARRIED_BY_AMR_1 if robot_id == 1 else BoxStatus.CARRIED_BY_AMR_2
	for st in box_states:
		if st == target_state:
			return true
	return false

func _get_target_box_index(robot_id: int) -> int:
	var floor_boxes: Array[int] = []
	for i in range(boxes.size()):
		if box_states[i] == BoxStatus.ON_FLOOR and boxes[i]:
			floor_boxes.append(i)

	if floor_boxes.is_empty():
		return -1

	var c1 = _is_carrying(1)
	var c2 = _is_carrying(2)

	# If this robot is already carrying, it seeks DropZone, not a box
	if (robot_id == 1 and c1) or (robot_id == 2 and c2):
		return -1

	# If teammate is carrying, this robot gets its closest available floor box
	var other_carrying = c2 if robot_id == 1 else c1
	if other_carrying:
		var my_robot = amr_1 if robot_id == 1 else amr_2
		var best_idx = -1
		var best_dist = 999.0
		for i in floor_boxes:
			var d = my_robot.global_position.distance_to(boxes[i].global_position)
			if d < best_dist:
				best_dist = d
				best_idx = i
		return best_idx

	# If neither is carrying:
	# Case 1: Exactly 1 box left on floor -> assign ONLY to the closer robot! The farther robot gets -1
	if floor_boxes.size() == 1:
		var single_idx = floor_boxes[0]
		var d1 = amr_1.global_position.distance_to(boxes[single_idx].global_position) if amr_1 else 999.0
		var d2 = amr_2.global_position.distance_to(boxes[single_idx].global_position) if amr_2 else 999.0
		if robot_id == 1:
			return single_idx if d1 <= d2 else -1
		else:
			return single_idx if d2 < d1 else -1

	# Case 2: >= 2 boxes on floor -> globally optimal bipartite matching
	# Determines pair (box_for_1, box_for_2) with distinct indices that minimizes total travel distance
	var best_total_cost = 99999.0
	var best_box_1 = -1
	var best_box_2 = -1

	for i in floor_boxes:
		var pos_i = boxes[i].global_position
		var d1 = amr_1.global_position.distance_to(pos_i) if amr_1 else 0.0
		for j in floor_boxes:
			if i == j:
				continue
			var pos_j = boxes[j].global_position
			var d2 = amr_2.global_position.distance_to(pos_j) if amr_2 else 0.0
			var cost = d1 + d2
			if cost < best_total_cost:
				best_total_cost = cost
				best_box_1 = i
				best_box_2 = j

	return best_box_1 if robot_id == 1 else best_box_2

func _does_path_intersect_dropzone(from_pos: Vector3, to_pos: Vector3, safe_radius: float = 2.2) -> bool:
	var dz = drop_zone.global_position if drop_zone else Vector3.ZERO
	var p1 = Vector2(from_pos.x, from_pos.z)
	var p2 = Vector2(to_pos.x, to_pos.z)
	var c = Vector2(dz.x, dz.z)

	var seg = p2 - p1
	var l2 = seg.length_squared()
	if l2 < 0.01:
		return p1.distance_to(c) < safe_radius

	var t = clampf((c - p1).dot(seg) / l2, 0.0, 1.0)
	var projection = p1 + t * seg
	return projection.distance_to(c) < safe_radius

func _get_active_subgoal_pos(robot_id: int) -> Vector3:
	var my_robot = amr_1 if robot_id == 1 else amr_2
	if not my_robot:
		return Vector3.ZERO

	if _is_carrying(robot_id):
		# Target DropZone directly for robust PPO policy navigation
		return drop_zone.global_position if drop_zone else Vector3.ZERO
	else:
		var target_idx = _get_target_box_index(robot_id)
		var base_target = Vector3.ZERO
		if target_idx != -1 and boxes[target_idx]:
			base_target = boxes[target_idx].global_position
		else:
			# Stand by at lateral parking bay FAR from DropZone (0,0)
			base_target = Vector3(-6.5, 0.0, 0.0) if robot_id == 1 else Vector3(6.5, 0.0, 0.0)

		# Circumnavigate around the green DropZone if path intersects it
		if _does_path_intersect_dropzone(my_robot.global_position, base_target, 2.25):
			# Pick bypass side matching robot's current side (never cross DropZone to get to bypass!)
			var bypass_z = -3.2
			if my_robot.global_position.z > 0.3:
				bypass_z = 3.2
			elif my_robot.global_position.z < -0.3:
				bypass_z = -3.2
			else:
				# Near centerline: choose side closer to base_target or robot_id tie-breaker
				if abs(base_target.z) > 0.5:
					bypass_z = 3.2 if base_target.z > 0.0 else -3.2
				else:
					bypass_z = -3.2 if robot_id == 1 else 3.2

			var bypass_pos = Vector3(0.0, 0.0, bypass_z)
			var dist_to_bypass = my_robot.global_position.distance_to(bypass_pos)

			if dist_to_bypass > 1.0:
				return bypass_pos

		return base_target

func _calculate_system_potential() -> float:
	var sum_dist: float = 0.0
	for i in range(boxes.size()):
		var state = box_states[i]
		var b = boxes[i]
		if not b or state == BoxStatus.DELIVERED:
			continue
		if state == BoxStatus.ON_FLOOR:
			var d1 = amr_1.global_position.distance_to(b.global_position) if amr_1 else 10.0
			var d2 = amr_2.global_position.distance_to(b.global_position) if amr_2 else 10.0
			sum_dist += minf(d1, d2)
		elif state == BoxStatus.CARRIED_BY_AMR_1:
			sum_dist += amr_1.global_position.distance_to(drop_zone.global_position) if amr_1 else 10.0
		elif state == BoxStatus.CARRIED_BY_AMR_2:
			sum_dist += amr_2.global_position.distance_to(drop_zone.global_position) if amr_2 else 10.0
	return sum_dist

func _resolve_symmetry(robot: AmrRobot, robot_id: int, v_ang: float) -> float:
	if not robot:
		return v_ang
	var sub_pos = _get_active_subgoal_pos(robot_id)
	var forward = -robot.global_transform.basis.z
	var to_sub = (sub_pos - robot.global_position).normalized()
	var alignment = forward.dot(to_sub)
	var cur_dist = robot.global_position.distance_to(sub_pos)
	if alignment < -0.80 and cur_dist > 1.5 and abs(v_ang) < 0.15:
		return 0.8
	return v_ang

func _smooth_approach(robot: AmrRobot, robot_id: int, v_lin: float, v_ang: float) -> Dictionary:
	if not robot:
		return {"v_lin": v_lin, "v_ang": v_ang}

	# Protect reverse undocking maneuver from forward override
	if (robot_id == 1 and _is_undocking_1) or (robot_id == 2 and _is_undocking_2):
		return {"v_lin": v_lin, "v_ang": v_ang}

	var is_c = _is_carrying(robot_id)
	var target_idx = _get_target_box_index(robot_id)

	# Idle parking behavior (e.g. 2nd robot waiting while 1st robot picks/delivers last box)
	if not is_c and target_idx == -1:
		var park_pos = Vector3(-6.5, 0.0, 0.0) if robot_id == 1 else Vector3(6.5, 0.0, 0.0)
		var d_park = robot.global_position.distance_to(park_pos)
		if d_park < 1.0:
			robot.set_amr_state(AmrRobot.AmrState.IDLE)
			return {"v_lin": 0.0, "v_ang": 0.0}

	# Near target box: damp high-frequency steering oscillation and ensure forward commitment
	if not is_c and target_idx != -1 and boxes[target_idx]:
		var b = boxes[target_idx]
		var d = robot.global_position.distance_to(b.global_position)
		if d < 2.5:
			var to_box = (b.global_position - robot.global_position).normalized()
			var fwd = -robot.global_transform.basis.z
			var right = robot.global_transform.basis.x
			var alignment = fwd.dot(to_box)
			var steer_to_box = -right.dot(to_box)
			if alignment > 0.20:
				v_ang = clampf(v_ang * 0.5 + steer_to_box * 0.8, -0.5, 0.5)
				v_lin = maxf(v_lin, 0.65)
			else:
				v_ang = clampf(steer_to_box * 1.5, -1.0, 1.0)
				v_lin = maxf(v_lin, 0.35) # Curve into box rather than spinning on spot

	# DropZone Docking & Strict Exclusion Zone Guardrail:
	# AMR MUST NEVER drive through or step onto the green drop zone!
	if drop_zone:
		var d_dz = robot.global_position.distance_to(drop_zone.global_position)
		var to_dz = (drop_zone.global_position - robot.global_position)
		to_dz.y = 0.0
		var dir_to_dz = to_dz.normalized() if to_dz.length_squared() > 0.01 else Vector3(0, 0, -1)
		var fwd = -robot.global_transform.basis.z

		# Absolute boundary guardrail: Green platform radius = 1.45m.
		# If any robot is inside 1.70m, immediately reverse back to perimeter!
		if d_dz < 1.70:
			return {"v_lin": -0.85, "v_ang": 0.0}

		if is_c:
			# Docking approach: actively guide heading straight to DropZone perimeter
			var right = robot.global_transform.basis.x
			var steer_to_dz = -right.dot(dir_to_dz)
			if d_dz < 3.2:
				v_ang = clampf(v_ang * 0.5 + steer_to_dz * 0.8, -0.6, 0.6)
			if dropzone_reserver == robot_id:
				if d_dz > 2.45 and fwd.dot(dir_to_dz) > 0.15:
					v_lin = maxf(v_lin, 0.65)
				elif d_dz <= 2.45:
					# Stop advancing forward while in docking perimeter
					v_lin = 0.0
		else:
			# Not carrying: High-Agility Streamline Tangent Navigation around DropZone
			if d_dz < 2.85:
				var r_out = -dir_to_dz # Unit vector pointing OUTWARD from DropZone
				var right = robot.global_transform.basis.x

				# Emergency buffer: if inside 1.90m and facing inward, reverse swiftly
				if d_dz < 1.90 and fwd.dot(dir_to_dz) > 0.0:
					v_lin = -0.80
					v_ang = 0.0
				else:
					# Streamline Tangent: find which circle tangent leads towards active goal
					var goal_pos = _get_active_subgoal_pos(robot_id)
					var to_goal = (goal_pos - robot.global_position)
					to_goal.y = 0.0
					var dir_goal = to_goal.normalized() if to_goal.length_squared() > 0.01 else fwd

					# Circle tangent unit vectors
					var t_ccw = Vector3(-r_out.z, 0.0, r_out.x)
					var t_cw = Vector3(r_out.z, 0.0, -r_out.x)
					var t_best = t_ccw if t_ccw.dot(dir_goal) >= t_cw.dot(dir_goal) else t_cw

					# Outward safety push if within 2.30m
					var outward_bias = clampf((2.30 - d_dz) / 0.5, 0.0, 1.2)
					var v_stream = (t_best + r_out * outward_bias).normalized()

					# Proportional steering to align forward vector with streamline
					var steer_stream = -right.dot(v_stream)
					v_ang = clampf(v_ang * 0.35 + steer_stream * 1.5, -1.0, 1.0)

					# Maintain swift, agile cruising speed around the rim! (No sluggish braking)
					var alignment = fwd.dot(v_stream)
					if alignment > 0.15:
						v_lin = maxf(v_lin, 0.85)
					else:
						v_lin = maxf(v_lin, 0.50)

	return {"v_lin": v_lin, "v_ang": v_ang}

func _apply_action(action: Array) -> void:
	_apply_action_scaled(action, speed_scale, 1.0 / float(max(1, action_hz)))

func _apply_action_scaled(action: Array, scale_factor: float = 1.0, dt: float = 0.01) -> void:
	if action.size() < 6:
		return

	# Action 0..2: AMR 1
	var v_lin1 = clampf(float(action[0]), -0.15, 1.0)
	var v_ang1 = clampf(float(action[1]), -1.0, 1.0)
	var trig1 = float(action[2])

	# Action 3..5: AMR 2
	var v_lin2 = clampf(float(action[3]), -0.15, 1.0)
	var v_ang2 = clampf(float(action[4]), -1.0, 1.0)
	var trig2 = float(action[5])

	v_ang1 = _resolve_symmetry(amr_1, 1, v_ang1)
	v_ang2 = _resolve_symmetry(amr_2, 2, v_ang2)

	var now_sec = Time.get_ticks_msec() / 1000.0

	# Reverse undocking sequence after drop: AMR reverses straight back to clear DropZone curb swiftly
	if _is_undocking_1 and amr_1:
		var d1_dz = amr_1.global_position.distance_to(drop_zone.global_position) if drop_zone else 999.0
		if d1_dz >= 2.80 or (now_sec - _undock_start_1) > 1.1:
			_is_undocking_1 = false
		else:
			v_lin1 = -0.75
			v_ang1 = 0.0
			amr_1.set_amr_state(AmrRobot.AmrState.MOVING)

	if _is_undocking_2 and amr_2:
		var d2_dz = amr_2.global_position.distance_to(drop_zone.global_position) if drop_zone else 999.0
		if d2_dz >= 2.80 or (now_sec - _undock_start_2) > 1.1:
			_is_undocking_2 = false
		else:
			v_lin2 = -0.75
			v_ang2 = 0.0
			amr_2.set_amr_state(AmrRobot.AmrState.MOVING)

	# Apply smoothing against jitter, spin-in-place, and DropZone streamline navigation
	var sm1 = _smooth_approach(amr_1, 1, v_lin1, v_ang1)
	v_lin1 = sm1["v_lin"]
	v_ang1 = sm1["v_ang"]

	var sm2 = _smooth_approach(amr_2, 2, v_lin2, v_ang2)
	v_lin2 = sm2["v_lin"]
	v_ang2 = sm2["v_ang"]

	# Unified Mutual Traffic & Yielding Manager (Zero conflicts, zero deadlocks)
	var traffic = _resolve_mutual_traffic(v_lin1, v_ang1, v_lin2, v_ang2, dt)
	v_lin1 = traffic["v_lin1"]
	v_ang1 = traffic["v_ang1"]
	v_lin2 = traffic["v_lin2"]
	v_ang2 = traffic["v_ang2"]

	# Apply speed scaled forward and angular speeds
	if amr_1:
		amr_1.set_rl_control(v_lin1 * 3.4 * scale_factor, v_ang1 * 2.6 * scale_factor)
	if amr_2:
		amr_2.set_rl_control(v_lin2 * 3.4 * scale_factor, v_ang2 * 2.6 * scale_factor)

	_handle_robot_interaction(amr_1, 1, trig1)
	_handle_robot_interaction(amr_2, 2, trig2)

func _resolve_mutual_traffic(v_lin1: float, v_ang1: float, v_lin2: float, v_ang2: float, dt: float = 0.01) -> Dictionary:
	if not amr_1 or not amr_2:
		return {"v_lin1": v_lin1, "v_ang1": v_ang1, "v_lin2": v_lin2, "v_ang2": v_ang2}

	var d_between = amr_1.global_position.distance_to(amr_2.global_position)
	var c1 = _is_carrying(1)
	var c2 = _is_carrying(2)

	# 1. DropZone Runway Reservation:
	# Ensure robots don't crowd the DropZone dock simultaneously
	if drop_zone:
		var d1_dz = amr_1.global_position.distance_to(drop_zone.global_position)
		var d2_dz = amr_2.global_position.distance_to(drop_zone.global_position)

		# Release reservation immediately once the robot is no longer carrying cargo
		if dropzone_reserver == 1 and not c1:
			dropzone_reserver = 0
		elif dropzone_reserver == 2 and not c2:
			dropzone_reserver = 0

		# Allocate reservation if currently free
		if dropzone_reserver == 0:
			if c1 and c2:
				dropzone_reserver = 1 if d1_dz <= d2_dz else 2
			elif c1:
				dropzone_reserver = 1
			elif c2:
				dropzone_reserver = 2

		# If DropZone is reserved: non-reserver holds outside at perimeter (d >= 3.0m), never freezes
		if dropzone_reserver == 1:
			if c2 and d2_dz < 3.2:
				v_lin2 = 0.25 # Holding glide outside perimeter
				amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
		elif dropzone_reserver == 2:
			if c1 and d1_dz < 3.2:
				v_lin1 = 0.25
				amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)

	# 2. Determine clear Right of Way:
	# - Undocking robot has absolute priority
	# - Carrying robot has priority over empty robot
	# - Default to AMR 1
	var p1_has_prio = true
	if _is_undocking_2:
		p1_has_prio = false
	elif _is_undocking_1:
		p1_has_prio = true
	elif c2 and not c1:
		p1_has_prio = false
	elif c1 and not c2:
		p1_has_prio = true
	else:
		p1_has_prio = true

	# 3. Active Anti-Deadlock Escape Monitor:
	# Detect if both robots are pinned/wedged against each other
	var spd1 = amr_1.current_speed
	var spd2 = amr_2.current_speed
	if d_between < 2.2 and spd1 < 0.20 and spd2 < 0.20 and not _is_undocking_1 and not _is_undocking_2:
		_deadlock_duration += dt
		if _deadlock_duration > 0.25: # 250ms of wedged stall
			_deadlock_escape_timer = 0.65
			_deadlock_escape_robot = 2 if p1_has_prio else 1
			_deadlock_duration = 0.0
	else:
		_deadlock_duration = maxf(0.0, _deadlock_duration - dt * 2.0)

	# Execute deadlock escape override if active
	if _deadlock_escape_timer > 0.0:
		_deadlock_escape_timer -= dt
		if _deadlock_escape_robot == 2:
			v_lin2 = -0.85
			v_ang2 = 1.0
			v_lin1 = 0.15 # Prio holds to let yielding robot slip free
			amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
		else:
			v_lin1 = -0.85
			v_ang1 = 1.0
			v_lin2 = 0.15
			amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)
		return {"v_lin1": v_lin1, "v_ang1": v_ang1, "v_lin2": v_lin2, "v_ang2": v_ang2}

	# 4. Proximity Traffic & Sidestep Evasion:
	if d_between < 2.8:
		var prio_robot = amr_1 if p1_has_prio else amr_2
		var yield_robot = amr_2 if p1_has_prio else amr_1

		var to_prio = (prio_robot.global_position - yield_robot.global_position).normalized()
		var fwd_yield = -yield_robot.global_transform.basis.z
		var right_yield = yield_robot.global_transform.basis.x
		var fwd_prio = -prio_robot.global_transform.basis.z

		# Geometry relative to yielding robot
		var facing_prio = fwd_yield.dot(to_prio)
		var prio_on_right = right_yield.dot(to_prio)

		# Steer AWAY from priority robot:
		# In Godot 3D: +Y rotation turns LEFT (+1.0), -Y rotation turns RIGHT (-1.0).
		# If prio is to the right (> 0.05), steer LEFT (+1.0).
		# If prio is to the left (< -0.05), steer RIGHT (-1.0).
		# If dead center (|dot| <= 0.05), steer RIGHT (-1.0) standard rule.
		var steer_away = 1.0 if prio_on_right > 0.05 else -1.0

		# Check if yielding robot is directly blocking prio robot's forward path
		var prio_to_yield = -to_prio
		var prio_blocked = fwd_prio.dot(prio_to_yield) > 0.25

		if d_between < 1.70:
			# CRITICAL BUMPER ZONE (chassis length 1.45m, diagonal 1.73m)
			# Yielding robot backs away forcefully and angles away to break contact
			if facing_prio > -0.2:
				if p1_has_prio:
					v_lin2 = -0.75
					v_ang2 = steer_away * 0.9
					amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
					# If prio is blocked face-to-face, slow down prio so it doesn't ram yield
					v_lin1 = 0.20 if prio_blocked else maxf(v_lin1, 0.70)
				else:
					v_lin1 = -0.75
					v_ang1 = steer_away * 0.9
					amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)
					v_lin2 = 0.20 if prio_blocked else maxf(v_lin2, 0.70)
			else:
				# Prio is behind yielding robot; yielding robot accelerates forward to open distance
				if p1_has_prio:
					v_lin2 = 0.85
					v_ang2 = steer_away * 0.7
					amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
					v_lin1 = maxf(v_lin1, 0.65)
				else:
					v_lin1 = 0.85
					v_ang1 = steer_away * 0.7
					amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)
					v_lin2 = maxf(v_lin2, 0.65)
		else:
			# PASSING ZONE (1.70m <= d < 2.80m)
			# Non-blocking sidestep: glide aside at 0.60 m/s without stopping
			if facing_prio > 0.0:
				if p1_has_prio:
					v_ang2 = clampf(v_ang2 * 0.25 + steer_away * 1.1, -1.0, 1.0)
					v_lin2 = 0.60
					v_lin1 = maxf(v_lin1, 0.80)
					amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
				else:
					v_ang1 = clampf(v_ang1 * 0.25 + steer_away * 1.1, -1.0, 1.0)
					v_lin1 = 0.60
					v_lin2 = maxf(v_lin2, 0.80)
					amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)

	return {"v_lin1": v_lin1, "v_ang1": v_ang1, "v_lin2": v_lin2, "v_ang2": v_ang2}

func _handle_robot_interaction(robot: AmrRobot, robot_id: int, trigger: float) -> void:
	if not robot:
		return

	var current_carried_idx: int = -1
	for i in range(boxes.size()):
		if (robot_id == 1 and box_states[i] == BoxStatus.CARRIED_BY_AMR_1) or (robot_id == 2 and box_states[i] == BoxStatus.CARRIED_BY_AMR_2):
			current_carried_idx = i
			break

	if current_carried_idx == -1:
		# Seeking box
		var target_idx = _get_target_box_index(robot_id)
		if target_idx != -1 and boxes[target_idx]:
			var b = boxes[target_idx]
			var d = robot.global_position.distance_to(b.global_position)
			# Pick if within reach:
			# Physical bumper contact occurs at ~0.95m. Arm reaches 2.15m.
			if d <= 1.45 or (d <= 1.85 and trigger > 0.0):
				if b.get_parent():
					b.get_parent().remove_child(b)
				robot.cargo_tray.add_child(b)
				b.position = robot.slot_1_marker.position if robot.slot_1_marker else Vector3(0.0, 0.16, 0.22)
				b.rotation = Vector3.ZERO
				b.freeze = true
				box_states[target_idx] = BoxStatus.CARRIED_BY_AMR_1 if robot_id == 1 else BoxStatus.CARRIED_BY_AMR_2
				robot.set_amr_state(AmrRobot.AmrState.LIFTING)
				print("[AMR %d] Picked box #%d (distance: %.2fm)" % [robot_id, target_idx, d])
	else:
		# Carrying box to drop zone
		var drop_dist = robot.global_position.distance_to(drop_zone.global_position)
		# Perimeter docking drop threshold: AMR stops outside green circle, arm places box on dock
		if drop_dist <= 2.70 or (drop_dist <= 3.00 and trigger > 0.0):
			var b = boxes[current_carried_idx]
			robot.cargo_tray.remove_child(b)
			add_child(b)
			# Neatly place 8 boxes in a 4x2 grid on the drop zone platform (height y = 0.22)
			var offset_x = (delivered_count % 4 - 1.5) * 0.55
			var offset_z = (delivered_count / 4 - 0.5) * 0.60
			b.global_position = drop_zone.global_position + Vector3(offset_x, 0.22, offset_z)
			b.rotation = Vector3.ZERO
			b.freeze = true
			box_states[current_carried_idx] = BoxStatus.DELIVERED
			delivered_count += 1
			robot.set_amr_state(AmrRobot.AmrState.IDLE)
			print("[AMR %d] Docked at perimeter (d=%.2fm) -> Delivered box #%d! [%d/8]" % [robot_id, drop_dist, current_carried_idx, delivered_count])

			# Trigger immediate reverse undocking out of the DropZone
			var now_s = Time.get_ticks_msec() / 1000.0
			if robot_id == 1:
				_is_undocking_1 = true
				_undock_start_1 = now_s
			else:
				_is_undocking_2 = true
				_undock_start_2 = now_s

			# Free up DropZone reservation immediately so other robot can dock
			dropzone_reserver = 0

			if delivered_count >= boxes.size():
				all_delivered = true
				print("✔ [Mission Complete] ALL 8 BOXES DELIVERED IN %d STEPS!" % step_count)

func _compute_observation() -> Array:
	var obs: Array = []
	if use_s6_obs:
		# 34 dimensions: 17 per robot with teammate mutual awareness
		obs.append_array(_compute_s6_obs(amr_1, 1))
		obs.append_array(_compute_s6_obs(amr_2, 2))
	else:
		# 26 dimensions: 13 per robot matching Stage 5 format
		obs.append_array(_compute_s5_obs(amr_1, 1))
		obs.append_array(_compute_s5_obs(amr_2, 2))
	return obs

func _compute_s6_obs(robot: AmrRobot, robot_id: int) -> Array:
	var o: Array = _compute_s5_obs(robot, robot_id)
	var other_robot: AmrRobot = amr_2 if robot_id == 1 else amr_1
	if robot and other_robot:
		var rel_teammate = robot.global_transform.basis.inverse() * (other_robot.global_position - robot.global_position)
		var teammate_dist = robot.global_position.distance_to(other_robot.global_position)
		# 13: Local relative X to teammate (lateral offset: negative = left, positive = right)
		o.append(clampf(rel_teammate.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
		# 14: Local relative Z to teammate (longitudinal: positive = in front, negative = behind)
		o.append(clampf(-rel_teammate.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
		# 15: Teammate Euclidean distance
		o.append(clampf(teammate_dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))
		# 16: Closing rate / approach velocity (dot product of relative position and relative velocity)
		var to_other = (other_robot.global_position - robot.global_position).normalized()
		var rel_vel = other_robot.velocity - robot.velocity
		var closing_rate = to_other.dot(rel_vel)
		o.append(clampf(closing_rate / 4.0, -1.0, 1.0))
	else:
		o.append(0.0)
		o.append(0.0)
		o.append(1.0)
		o.append(0.0)
	return o

func _compute_s5_obs(robot: AmrRobot, robot_id: int) -> Array:
	var o: Array = []
	if not robot:
		for i in range(13): o.append(0.0)
		return o

	# 0..3: Global arena pose normalized to 8m half-extent
	var norm_x = clampf(robot.global_position.x / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var norm_z = clampf(robot.global_position.z / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var yaw = robot.rotation.y
	o.append(norm_x)
	o.append(norm_z)
	o.append(sin(yaw))
	o.append(cos(yaw))

	# 4..5: Normalized linear & angular velocity
	var norm_v = clampf(robot._manual_linear_vel / 2.8, -1.0, 1.0)
	var norm_w = clampf(robot._rl_target_v_ang / 2.2, -1.0, 1.0)
	o.append(norm_v)
	o.append(norm_w)

	# 6..8: Relative vector to active sub-goal in robot local frame
	var sub_pos = _get_active_subgoal_pos(robot_id)
	var local_rel = robot.global_transform.basis.inverse() * (sub_pos - robot.global_position)
	var dist = robot.global_position.distance_to(sub_pos)
	o.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	o.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	o.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying status (0.0 if seeking box, 1.0 if seeking drop zone)
	var is_c = 1.0 if _is_carrying(robot_id) else 0.0
	o.append(is_c)

	# 10: Tray status
	o.append(is_c)

	# 11..12: Nearest wall distance
	var dist_x = arena_half_extent - abs(robot.global_position.x)
	var dist_z = arena_half_extent - abs(robot.global_position.z)
	o.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	o.append(0.0)

	return o

func _compute_reward(_action: Array = []) -> float:
	var rew: float = 0.0

	# 1. Potential field progress reward (progress toward items and drop zone)
	var cur_total_dist = _calculate_system_potential()
	var dist_delta = prev_total_dist - cur_total_dist
	rew += clampf(dist_delta * 1.5, -2.0, 2.0)
	prev_total_dist = cur_total_dist

	# 2. Box delivered reward
	if delivered_count > prev_delivered_count:
		var new_delivered = delivered_count - prev_delivered_count
		rew += 25.0 * new_delivered
		prev_delivered_count = delivered_count

	# 3. All boxes delivered completion bonus
	if all_delivered:
		rew += 50.0

	# 4. Teammate collision & proximity penalty
	if amr_1 and amr_2:
		var d_between = amr_1.global_position.distance_to(amr_2.global_position)
		if d_between < 1.0: # Direct collision
			rew -= 5.0
			robot_collisions += 1
		elif d_between < 2.0: # Proximity warning zone
			rew -= 0.6 * (2.0 - d_between)

	# 5. Wall proximity penalty
	if amr_1:
		var w1 = minf(arena_half_extent - abs(amr_1.global_position.x), arena_half_extent - abs(amr_1.global_position.z))
		if w1 < 0.6:
			rew -= 1.5
	if amr_2:
		var w2 = minf(arena_half_extent - abs(amr_2.global_position.x), arena_half_extent - abs(amr_2.global_position.z))
		if w2 < 0.6:
			rew -= 1.5

	# 6. Step penalty to encourage fast completion
	rew -= 0.02

	# 7. Speed and agility encouragement (encourage swift cruising, penalize idling)
	if amr_1:
		rew += 0.02 * clampf(amr_1.current_speed / 2.0, 0.0, 1.0)
	if amr_2:
		rew += 0.02 * clampf(amr_2.current_speed / 2.0, 0.0, 1.0)

	# 8. Strict DropZone disc penetration penalty (R = 1.45m)
	if drop_zone:
		var d1_dz = amr_1.global_position.distance_to(drop_zone.global_position) if amr_1 else 10.0
		var d2_dz = amr_2.global_position.distance_to(drop_zone.global_position) if amr_2 else 10.0
		if d1_dz < 1.45: rew -= 4.0
		if d2_dz < 1.45: rew -= 4.0

	return rew

func _is_terminated() -> bool:
	return all_delivered

func _is_truncated() -> bool:
	return step_count >= max_episode_steps

func _get_info() -> Dictionary:
	return {
		"delivered_count": delivered_count,
		"all_delivered": all_delivered,
		"robot_collisions": robot_collisions,
		"wall_collisions": wall_collisions,
		"step_count": step_count,
		"r1_pos": [snappedf(amr_1.global_position.x, 0.01), snappedf(amr_1.global_position.z, 0.01)] if amr_1 else [],
		"r2_pos": [snappedf(amr_2.global_position.x, 0.01), snappedf(amr_2.global_position.z, 0.01)] if amr_2 else [],
		"reserver": dropzone_reserver,
		"target_1": _get_target_box_index(1),
		"target_2": _get_target_box_index(2),
		"c1": _is_carrying(1),
		"c2": _is_carrying(2),
		"d1_dz": snappedf(amr_1.global_position.distance_to(drop_zone.global_position), 0.01) if amr_1 and drop_zone else 0.0,
		"d2_dz": snappedf(amr_2.global_position.distance_to(drop_zone.global_position), 0.01) if amr_2 and drop_zone else 0.0,
	}
