class_name PickupEnv
extends TrainingEnvBase

## Stage S2: Pick-Up Training Environment
## Agent learns fine-alignment, approach angle, and trigger timing to grasp the box.

@export var arena_half_extent: float = 2.5
@onready var target_box: ToteBox = $TargetBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var is_picked: bool = false
var failed_attempt: bool = false
var pick_hold_timer: float = 0.0

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	is_picked = false
	failed_attempt = false
	pick_hold_timer = 0.0

	# 1. Reset AMR
	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# 2. Spawn seeded from S1 terminal distribution: robot ~1.0m from box
	var offset_x = rng.randf_range(-0.35, 0.35)
	var offset_z = rng.randf_range(-1.2, -0.85)
	var yaw_noise = rng.randf_range(-deg_to_rad(25.0), deg_to_rad(25.0))

	if amr:
		amr.global_position = Vector3(offset_x, 0.0, offset_z)
		amr.rotation = Vector3(0.0, yaw_noise, 0.0)
		amr.velocity = Vector3.ZERO
		amr.set_rl_control(0.0, 0.0)

	if target_box:
		target_box.freeze = true
		target_box.global_position = Vector3(0.0, 0.16, 0.0)
		target_box.rotation = Vector3.ZERO
		target_box.linear_velocity = Vector3.ZERO
		target_box.angular_velocity = Vector3.ZERO
		target_box.visible = true

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr or not target_box:
		for i in range(13): obs.append(0.0)
		return obs

	# 0..3: Local pose
	var norm_x = clampf(amr.global_position.x / arena_half_extent, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / arena_half_extent, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Velocities [v_lin/max_speed, v_ang/turn_speed]
	var norm_v = clampf(amr._manual_linear_vel / maxf(amr.max_speed, 1.0), -1.0, 1.0)
	var norm_w = clampf(amr._rl_target_v_ang / maxf(amr.turn_speed, 1.0), -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative vector to box (in robot local frame)
	var local_rel = amr.global_transform.basis.inverse() * (target_box.global_position - amr.global_position)
	var dist = amr.global_position.distance_to(target_box.global_position)
	obs.append(clampf(local_rel.x / arena_half_extent, -1.0, 1.0))
	obs.append(clampf(local_rel.z / arena_half_extent, -1.0, 1.0))
	obs.append(clampf(dist / arena_half_extent, 0.0, 1.0))

	# 9: Carrying status (1.0 if held, else 0.0)
	obs.append(1.0 if amr.held_box != null else 0.0)

	# 10: Lift/tray status (1.0 if in tray, 0.5 if held ready, 0.0 if empty)
	var tray_status = 1.0 if amr.get_stowed_box_count() > 0 else (0.5 if amr.held_box != null else 0.0)
	obs.append(tray_status)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / arena_half_extent, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var reward: float = 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0
	var dist = amr.global_position.distance_to(target_box.global_position)

	# 1. Approach alignment shaping
	var forward = -amr.global_transform.basis.z
	var to_box = (target_box.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_box)
	reward += maxf(0.0, alignment) * 0.08

	# Distance progress
	reward += (1.5 - minf(dist, 1.5)) * 0.05
	reward -= 0.01 # Time penalty

	# 2. Trigger evaluation
	if trigger > 0.5:
		if amr.held_box != null or amr.get_stowed_box_count() > 0:
			# Successful pick!
			is_picked = true
			reward += 2.5
		elif dist > 1.8 or alignment < 0.6:
			# Premature or misaligned trigger attempt
			failed_attempt = true
			reward -= 0.5

	# Check if box is successfully held
	if amr.held_box != null or amr.get_stowed_box_count() > 0:
		is_picked = true
		reward += 0.1

	return reward

func _is_terminated() -> bool:
	return is_picked or failed_attempt

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"is_picked": is_picked,
		"failed_attempt": failed_attempt,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if is_picked else []
	}
