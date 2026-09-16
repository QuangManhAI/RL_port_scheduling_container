class_name DropoffEnv
extends TrainingEnvBase

## Stage S4: Drop-Off Training Environment
## Agent learns fine-approach, drop-zone alignment, and trigger timing to unload box.

@export var arena_half_extent: float = 2.5
@export var placement_tolerance: float = 0.85

@onready var drop_zone_marker: Node3D = $DropZoneMarker
@onready var carried_box: ToteBox = $CarriedBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var is_placed: bool = false
var failed_attempt: bool = false

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	is_placed = false
	failed_attempt = false

	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true

	# 1. Spawn seeded from S3 terminal distribution: robot ~1.0m from zone
	var offset_x = rng.randf_range(-0.35, 0.35)
	var offset_z = rng.randf_range(0.95, 1.25)
	var yaw_noise = rng.randf_range(-deg_to_rad(25.0), deg_to_rad(25.0))

	if amr:
		amr.global_position = Vector3(offset_x, 0.0, offset_z)
		amr.rotation = Vector3(0.0, yaw_noise, 0.0)
		amr.velocity = Vector3.ZERO
		amr.set_rl_control(0.0, 0.0)

	# 2. Stow box in tray
	if carried_box and amr and amr.slot_1_marker:
		carried_box.freeze = true
		if carried_box.get_parent() != amr.cargo_tray:
			carried_box.get_parent().remove_child(carried_box)
			amr.cargo_tray.add_child(carried_box)
		carried_box.transform = amr.slot_1_marker.transform
		carried_box.visible = true

	if drop_zone_marker:
		drop_zone_marker.global_position = Vector3(0.0, 0.02, 0.0)

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr or not drop_zone_marker:
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

	# 6..8: Relative vector to drop zone
	var local_rel = amr.global_transform.basis.inverse() * (drop_zone_marker.global_position - amr.global_position)
	var dist = amr.global_position.distance_to(drop_zone_marker.global_position)
	obs.append(clampf(local_rel.x / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(-local_rel.z / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(dist / (arena_half_extent * 2.0), 0.0, 1.0))

	# 9: Carrying flag
	var carrying = 1.0 if (amr.get_stowed_box_count() > 0 or amr.held_box != null) else 0.0
	obs.append(carrying)

	# 10: Lift/tray status
	obs.append(carrying)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / arena_half_extent, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var reward: float = 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0
	var dist = amr.global_position.distance_to(drop_zone_marker.global_position)

	# 1. Alignment shaping toward drop zone
	var forward = -amr.global_transform.basis.z
	var to_zone = (drop_zone_marker.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_zone)
	reward += maxf(0.0, alignment) * 0.08
	reward -= 0.01

	# 2. Trigger drop action
	if trigger > 0.5:
		if dist <= placement_tolerance and alignment >= 0.6:
			# Successful placement within drop zone!
			is_placed = true
			reward += 2.5
			if carried_box and carried_box.get_parent() == amr.cargo_tray:
				# Place box down into drop zone
				amr.cargo_tray.remove_child(carried_box)
				get_parent().add_child(carried_box)
				carried_box.global_position = drop_zone_marker.global_position + Vector3(0.0, 0.16, 0.0)
				carried_box.freeze = false
		else:
			# Premature or misaligned drop
			failed_attempt = true
			reward -= 0.5

	return reward

func _is_terminated() -> bool:
	return is_placed or failed_attempt

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"is_placed": is_placed,
		"failed_attempt": failed_attempt,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if is_placed else []
	}
