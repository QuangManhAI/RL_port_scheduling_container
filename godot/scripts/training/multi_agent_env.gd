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
@export var policy_json_path: String = "res://models/ppo_s5_policy.json"
@export var physics_hz: int = 150  ## High-frequency continuous physics clock (150 Ticks/s)
@export var action_hz: int = 60    ## Neural network decision frequency (60 Hz)
@export var speed_scale: float = 1.5 ## 1.5x Faster Motion multiplier

var native_policy: NeuralPolicy = null
var _native_reset_timer: float = 0.0
var _action_tick_accumulator: float = 0.0
var _current_joint_act: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

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
		print("[MultiAgentEnv] Zero-Latency Native Dual-Clock In-Engine AI ACTIVATED!")
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
		var obs1 = _compute_s5_obs(amr_1, 1)
		var obs2 = _compute_s5_obs(amr_2, 2)

		var act1 = native_policy.predict(obs1)
		var act2 = native_policy.predict(obs2)

		_current_joint_act = [act1[0], act1[1], act1[2], act2[0], act2[1], act2[2]]

	# Apply continuous physics motion at every single high-rate tick (150 Hz)
	_apply_action_scaled(_current_joint_act, speed_scale)

	if step_count >= max_episode_steps:
		_on_arena_reset(0, 0.0)

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	step_count = 0
	delivered_count = 0
	robot_collisions = 0
	wall_collisions = 0
	all_delivered = false
	box_states = [0, 0, 0, 0, 0, 0, 0, 0]

	# Reset AMR 1 (spawns on West)
	if amr_1:
		amr_1.reset_robot(Vector3(-5.0, 0.0, 0.0), 0.0)
		amr_1.is_manual_control = false
		amr_1.is_rl_control = true
		amr_1.held_box = null
		_clear_cargo_tray(amr_1)

	# Reset AMR 2 (spawns on East)
	if amr_2:
		amr_2.reset_robot(Vector3(5.0, 0.0, 0.0), PI)
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
	for attempt in range(50):
		var x = rng.randf_range(-max_r, max_r)
		var z = rng.randf_range(-max_r, max_r)
		var candidate = Vector3(x, 0.16, z)
		var ok = true
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
	var other_id = 2 if robot_id == 1 else 1
	var other_target = -1

	# If the other robot is not carrying, find which box it's heading towards
	if not _is_carrying(other_id):
		var other_robot = amr_2 if robot_id == 1 else amr_1
		var min_d = 999.0
		for i in range(boxes.size()):
			if box_states[i] == BoxStatus.ON_FLOOR and boxes[i]:
				var d = other_robot.global_position.distance_to(boxes[i].global_position)
				if d < min_d:
					min_d = d
					other_target = i

	# Now find the best box for this robot (prefer boxes not targeted by teammate)
	var my_robot = amr_1 if robot_id == 1 else amr_2
	var best_idx = -1
	var best_dist = 999.0

	for i in range(boxes.size()):
		if box_states[i] == BoxStatus.ON_FLOOR and boxes[i]:
			if i != other_target:
				var d = my_robot.global_position.distance_to(boxes[i].global_position)
				if d < best_dist:
					best_dist = d
					best_idx = i

	# If all other boxes are taken, fall back to whatever is left
	if best_idx == -1:
		for i in range(boxes.size()):
			if box_states[i] == BoxStatus.ON_FLOOR and boxes[i]:
				var d = my_robot.global_position.distance_to(boxes[i].global_position)
				if d < best_dist:
					best_dist = d
					best_idx = i

	return best_idx

func _get_active_subgoal_pos(robot_id: int) -> Vector3:
	if _is_carrying(robot_id):
		return drop_zone.global_position if drop_zone else Vector3.ZERO
	else:
		var target_idx = _get_target_box_index(robot_id)
		if target_idx != -1 and boxes[target_idx]:
			return boxes[target_idx].global_position
		return drop_zone.global_position if drop_zone else Vector3.ZERO

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

func _apply_action(action: Array) -> void:
	_apply_action_scaled(action, speed_scale)

func _apply_action_scaled(action: Array, scale_factor: float = 1.0) -> void:
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

	# Mutual Collision Avoidance & Yielding Negotiation:
	if amr_1 and amr_2:
		var d_between = amr_1.global_position.distance_to(amr_2.global_position)
		if d_between < 2.0:
			var dir_2to1 = (amr_1.global_position - amr_2.global_position).normalized()
			var fwd_2 = -amr_2.global_transform.basis.z
			# If AMR 2 is facing AMR 1, AMR 2 yields priority to AMR 1
			if fwd_2.dot(dir_2to1) > 0.35:
				v_lin2 *= 0.15 # Slow down / yield
				amr_2.set_amr_state(AmrRobot.AmrState.YIELDING)
			else:
				var dir_1to2 = (amr_2.global_position - amr_1.global_position).normalized()
				var fwd_1 = -amr_1.global_transform.basis.z
				if fwd_1.dot(dir_1to2) > 0.35:
					v_lin1 *= 0.15
					amr_1.set_amr_state(AmrRobot.AmrState.YIELDING)

	# Apply speed scaled forward and angular speeds
	if amr_1:
		amr_1.set_rl_control(v_lin1 * 3.4 * scale_factor, v_ang1 * 2.6 * scale_factor)
	if amr_2:
		amr_2.set_rl_control(v_lin2 * 3.4 * scale_factor, v_ang2 * 2.6 * scale_factor)

	_handle_robot_interaction(amr_1, 1, trig1)
	_handle_robot_interaction(amr_2, 2, trig2)

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
			# Pick if within reach
			if d <= 0.85 or (d <= 1.35 and trigger > 0.15):
				if b.get_parent():
					b.get_parent().remove_child(b)
				robot.cargo_tray.add_child(b)
				b.position = robot.slot_1_marker.position if robot.slot_1_marker else Vector3(0.0, 0.16, 0.22)
				b.rotation = Vector3.ZERO
				b.freeze = true
				box_states[target_idx] = BoxStatus.CARRIED_BY_AMR_1 if robot_id == 1 else BoxStatus.CARRIED_BY_AMR_2
				robot.set_amr_state(AmrRobot.AmrState.LIFTING)
	else:
		# Carrying box to drop zone
		var drop_dist = robot.global_position.distance_to(drop_zone.global_position)
		if drop_dist <= 1.5 or (drop_dist <= 1.8 and trigger > 0.15):
			var b = boxes[current_carried_idx]
			robot.cargo_tray.remove_child(b)
			add_child(b)
			# Neatly place 8 boxes in a 4x2 grid in the drop zone
			var offset_x = (delivered_count % 4 - 1.5) * 0.55
			var offset_z = (delivered_count / 4 - 0.5) * 0.60
			b.global_position = drop_zone.global_position + Vector3(offset_x, 0.16, offset_z)
			b.rotation = Vector3.ZERO
			b.freeze = true
			box_states[current_carried_idx] = BoxStatus.DELIVERED
			delivered_count += 1
			robot.set_amr_state(AmrRobot.AmrState.IDLE)
			if delivered_count >= boxes.size():
				all_delivered = true

func _compute_observation() -> Array:
	# 26 dimensions: 13 per robot matching exactly the Stage 5 (S5) input format!
	var obs: Array = []
	obs.append_array(_compute_s5_obs(amr_1, 1))
	obs.append_array(_compute_s5_obs(amr_2, 2))
	return obs

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
	return 0.0

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
	}
