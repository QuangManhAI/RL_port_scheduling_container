class_name NavigateCarryingEnv
extends TrainingEnvBase

## Stage S3: Navigate-while-Carrying Training Environment
## Agent learns smooth transit while carrying physical payload in cargo tray.

@export var arena_half_extent: float = 6.0
@export var arrival_threshold: float = 1.20
@export var stop_speed_threshold: float = 0.30

@onready var drop_zone_marker: Node3D = $DropZoneMarker
@onready var carried_box: ToteBox = $CarriedBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prev_distance_to_zone: float = 0.0
var goal_reached: bool = false
var wall_collided: bool = false

func _ready() -> void:
	super._ready()
	_stow_box_in_slot1()

func _stow_box_in_slot1() -> void:
	if carried_box and amr and amr.slot_1_marker and amr.cargo_tray:
		carried_box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		carried_box.freeze = true
		if carried_box.get_parent() != amr.cargo_tray:
			if carried_box.get_parent():
				carried_box.get_parent().remove_child(carried_box)
			amr.cargo_tray.add_child(carried_box)
		carried_box.position = amr.slot_1_marker.position
		carried_box.rotation = Vector3.ZERO
		carried_box.visible = true

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
	_stow_box_in_slot1()

	# 3. Spawn drop zone marker >= 3.0m away
	SpawnRandomizer.spawn_drop_zone(drop_zone_marker, amr, arena_half_extent, 3.0, rng)
	prev_distance_to_zone = _get_current_distance_to_zone()

func _get_current_distance_to_zone() -> float:
	if not amr or not drop_zone_marker:
		return 999.0
	return amr.global_position.distance_to(drop_zone_marker.global_position)

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr or not drop_zone_marker:
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

	# 6..8: Relative vector to drop zone normalized to universal 16m metric span
	var local_rel = amr.global_transform.basis.inverse() * (drop_zone_marker.global_position - amr.global_position)
	var dist = _get_current_distance_to_zone()
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying flag = 1.0
	obs.append(1.0)

	# 10: Lift/tray status = 1.0 (stowed in tray)
	obs.append(1.0)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var cur_dist = _get_current_distance_to_zone()
	var delta_dist = prev_distance_to_zone - cur_dist
	prev_distance_to_zone = cur_dist

	var reward: float = 0.0

	# 1. Progress shaping toward drop zone
	reward += delta_dist * 3.0
	reward -= 0.01 # Time penalty

	# 2. Strict anti-spinning penalty
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	reward -= 0.04 * abs(v_ang)
	if abs(v_ang) > 0.4 and amr._manual_linear_vel < 0.3:
		reward -= 0.08 * (abs(v_ang) - 0.4)

	# 3. Orientation alignment shaping (facing drop zone)
	var forward = -amr.global_transform.basis.z
	var to_zone = (drop_zone_marker.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_zone)
	if alignment >= 0.0:
		reward += alignment * 0.08
	else:
		reward -= 0.08 * abs(alignment)

	# 4. Advance approach deceleration profile within 2.2m (prevents overshooting and orbiting)
	if cur_dist <= 2.2 and amr.current_speed > 0.8:
		reward -= 0.08 * (amr.current_speed - 0.8)

	# 5. Arrival and controlled stopping bonus: requires facing drop zone and coming to stop <= 0.30 m/s
	if cur_dist <= arrival_threshold:
		if alignment >= 0.35:
			if amr.current_speed <= stop_speed_threshold:
				goal_reached = true
				reward += 5.0 + alignment * 1.0
			else:
				# Near drop zone but still cruising: encourage linear braking
				reward += 0.08 - (amr.current_speed / 2.8) * 0.15
		else:
			reward -= 0.10

	# 6. Wall collision penalty
	var wall_limit = arena_half_extent - 0.35
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return goal_reached or wall_collided

func _get_info() -> Dictionary:
	var forward: Vector3 = -amr.global_transform.basis.z if amr else Vector3.FORWARD
	var to_zone: Vector3 = (drop_zone_marker.global_position - amr.global_position).normalized() if (amr and drop_zone_marker) else Vector3.FORWARD
	return {
		"step": step_count,
		"amr_pos": [amr.global_position.x, amr.global_position.y, amr.global_position.z] if amr else [],
		"target_pos": [drop_zone_marker.global_position.x, drop_zone_marker.global_position.y, drop_zone_marker.global_position.z] if drop_zone_marker else [],
		"amr_yaw": amr.rotation.y if amr else 0.0,
		"speed": amr.current_speed if amr else 0.0,
		"linear_vel": amr._manual_linear_vel if amr else 0.0,
		"angular_vel": amr._rl_target_v_ang if amr else 0.0,
		"alignment": forward.dot(to_zone),
		"distance_to_box": _get_current_distance_to_zone(),
		"distance_to_zone": _get_current_distance_to_zone(),
		"goal_reached": goal_reached,
		"wall_collided": wall_collided,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if (goal_reached or wall_collided) else []
	}
