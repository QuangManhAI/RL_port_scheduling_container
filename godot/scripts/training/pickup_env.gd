class_name PickupEnv
extends TrainingEnvBase

## Stage S2: Pick-Up Training Environment
## Agent learns fine-alignment, approach angle, and trigger timing to grasp the box.

@export var arena_half_extent: float = 2.5
@onready var target_box: ToteBox = $TargetBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var is_picked: bool = false
var failed_attempt: bool = false
var wall_collided: bool = false
var trigger_attempted: bool = false

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	is_picked = false
	failed_attempt = false
	wall_collided = false
	trigger_attempted = false

	# 1. Reset AMR
	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# 2. Reset Box at origin
	if target_box:
		target_box.freeze = true
		target_box.global_position = Vector3(0.0, 0.16, 0.0)
		target_box.rotation = Vector3.ZERO
		target_box.linear_velocity = Vector3.ZERO
		target_box.angular_velocity = Vector3.ZERO
		target_box.visible = true

	# 3. Spawn seeded from S1 terminal distribution: robot in front of box ~0.95 - 1.25m away
	# Box is at (0, 0.16, 0). Robot facing -Z towards box is placed at +Z.
	var offset_x = rng.randf_range(-0.30, 0.30)
	var offset_z = rng.randf_range(0.95, 1.25)
	var yaw_noise = rng.randf_range(-deg_to_rad(25.0), deg_to_rad(25.0))

	if amr:
		amr.global_position = Vector3(offset_x, 0.0, offset_z)
		amr.rotation = Vector3(0.0, yaw_noise, 0.0)
		amr.velocity = Vector3.ZERO
		amr.set_rl_control(0.0, 0.0)

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0

	var lin_vel = v_lin * amr.max_speed
	var ang_vel = v_ang * amr.turn_speed
	amr.set_rl_control(lin_vel, ang_vel)

	if trigger > 0.5 and not trigger_attempted:
		trigger_attempted = true
		amr.trigger_rl_action(target_box)

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr or not target_box:
		for i in range(13): obs.append(0.0)
		return obs

	# 0..3: Local pose normalized to universal 8m half-extent
	var norm_x = clampf(amr.global_position.x / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Velocities normalized to physical limits [2.8 m/s, 2.2 rad/s]
	var norm_v = clampf(amr._manual_linear_vel / 2.8, -1.0, 1.0)
	var norm_w = clampf(amr._manual_angular_vel / 2.2, -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative vector to box normalized to universal 16m metric span
	var local_rel = amr.global_transform.basis.inverse() * (target_box.global_position - amr.global_position)
	var dist = amr.global_position.distance_to(target_box.global_position)
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying status (1.0 if held, else 0.0)
	obs.append(1.0 if amr.held_box != null else 0.0)

	# 10: Lift/tray status (1.0 if in tray, 0.5 if held ready, 0.0 if empty)
	var tray_status = 1.0 if amr.get_stowed_box_count() > 0 else (0.5 if amr.held_box != null else 0.0)
	obs.append(tray_status)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
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
	if alignment >= 0.0:
		reward += alignment * 0.10
	else:
		reward -= 0.10 * abs(alignment)

	# 2. Strict anti-spinning penalty
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	reward -= 0.04 * abs(v_ang)
	if abs(v_ang) > 0.4 and amr._manual_linear_vel < 0.3:
		reward -= 0.08 * (abs(v_ang) - 0.4)

	# Distance progress toward grasp window
	reward += (1.5 - minf(dist, 1.5)) * 0.08
	reward -= 0.01 # Time penalty

	# Deceleration shaping near grasp point (prevents ramming)
	if dist <= 1.5 and amr.current_speed > 0.6:
		reward -= 0.06 * (amr.current_speed - 0.6)

	# 3. Trigger guidance & grasp execution
	var in_grasp_range = (dist <= 1.50) and (alignment >= 0.30)
	if in_grasp_range:
		reward += maxf(0.0, trigger) * 0.20

		if (trigger > 0.30 or dist <= 0.80) and not is_picked:
			if target_box and amr and amr.cargo_tray:
				target_box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				target_box.freeze = true
				if target_box.get_parent():
					target_box.get_parent().remove_child(target_box)
				amr.cargo_tray.add_child(target_box)
				target_box.position = amr.slot_1_marker.position if amr.slot_1_marker else Vector3(0.0, 0.16, 0.22)
				target_box.rotation = Vector3.ZERO
			is_picked = true
			reward += 6.0 + maxf(0.0, trigger) * 1.0
	else:
		if trigger > 0.40 and dist > 1.8:
			reward -= 0.05

	# 4. Wall collision penalty
	var wall_limit = arena_half_extent - 0.35
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return is_picked or failed_attempt or wall_collided

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"distance_to_box": amr.global_position.distance_to(target_box.global_position) if (amr and target_box) else 0.0,
		"is_picked": is_picked,
		"failed_attempt": failed_attempt,
		"wall_collided": wall_collided,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if is_picked else []
	}
