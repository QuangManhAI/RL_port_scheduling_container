class_name NavigateCarryingEnv
extends TrainingEnvBase

## Stage S3: Navigate-while-Carrying Training Environment
## Agent learns smooth transit while carrying physical payload in cargo tray.

@export var arena_half_extent: float = 6.0
@export var arrival_threshold: float = 1.20

@onready var drop_zone_marker: Node3D = $DropZoneMarker
@onready var carried_box: ToteBox = $CarriedBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prev_distance_to_zone: float = 0.0
var goal_reached: bool = false
var wall_collided: bool = false

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	goal_reached = false
	wall_collided = false

	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true

	# 1. Spawn agent
	SpawnRandomizer.spawn_agent(amr, arena_half_extent, rng)

	# 2. Stow box directly in AMR tray slot 1
	if carried_box and amr and amr.slot_1_marker:
		carried_box.freeze = true
		if carried_box.get_parent() != amr.cargo_tray:
			carried_box.get_parent().remove_child(carried_box)
			amr.cargo_tray.add_child(carried_box)
		carried_box.transform = amr.slot_1_marker.transform
		carried_box.visible = true

	# 3. Spawn drop zone marker >= 3.0m away
	SpawnRandomizer.spawn_drop_zone(drop_zone_marker, amr, arena_half_extent, 3.0, rng)
	prev_distance_to_zone = _get_current_distance_to_zone()

func _get_current_distance_to_zone() -> float:
	if not amr or not drop_zone_marker:
		return 999.0
	return amr.global_position.distance_to(drop_zone_marker.global_position)

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
	var dist = _get_current_distance_to_zone()
	obs.append(clampf(local_rel.x / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(-local_rel.z / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(dist / (arena_half_extent * 2.0), 0.0, 1.0))

	# 9: Carrying flag = 1.0
	obs.append(1.0)

	# 10: Lift/tray status = 1.0 (stowed in tray)
	obs.append(1.0)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / arena_half_extent, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(_action: Array) -> float:
	var cur_dist = _get_current_distance_to_zone()
	var delta_dist = prev_distance_to_zone - cur_dist
	prev_distance_to_zone = cur_dist

	var reward: float = 0.0

	# 1. Progress shaping toward drop zone
	reward += delta_dist * 3.5

	# 2. Time penalty
	reward -= 0.01

	# 3. Orientation alignment shaping (facing drop zone)
	var forward = -amr.global_transform.basis.z
	var to_zone = (drop_zone_marker.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_zone)
	reward += alignment * 0.03

	# Soft penalty for driving backwards
	if amr._manual_linear_vel < -0.1:
		reward -= 0.05

	# 4. Soft stability penalty: discourage erratic turning while carrying cargo
	reward -= 0.005 * abs(amr._rl_target_v_ang)

	# 5. Arrival bonus
	if cur_dist <= arrival_threshold:
		if alignment >= 0.35:
			goal_reached = true
			reward += 2.0 + alignment * 1.0
		else:
			reward -= 0.1

	# 6. Wall collision penalty
	var wall_limit = arena_half_extent - 0.35
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return goal_reached or wall_collided

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"distance_to_box": _get_current_distance_to_zone(),
		"distance_to_zone": _get_current_distance_to_zone(),
		"goal_reached": goal_reached,
		"wall_collided": wall_collided,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if (goal_reached or wall_collided) else []
	}
