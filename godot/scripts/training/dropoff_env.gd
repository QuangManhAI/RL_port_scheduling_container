class_name DropoffEnv
extends TrainingEnvBase

## Stage S4: Drop-Off Training Environment
## Agent learns fine-approach, drop-zone alignment, and trigger timing to unload box.

@export var arena_half_extent: float = 2.5
@export var placement_tolerance: float = 1.10

@onready var drop_zone_marker: Node3D = $DropZoneMarker
@onready var carried_box: ToteBox = $CarriedBox

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var is_placed: bool = false
var failed_attempt: bool = false
var wall_collided: bool = false

func _ready() -> void:
	max_episode_steps = 300
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
		carried_box.linear_velocity = Vector3.ZERO
		carried_box.angular_velocity = Vector3.ZERO
		carried_box.visible = true

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	is_placed = false
	failed_attempt = false
	wall_collided = false

	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true

	# 1. Spawn seeded from S3 terminal distribution: robot ~0.80 - 1.20m from zone
	var offset_x = rng.randf_range(-0.30, 0.30)
	var offset_z = rng.randf_range(0.80, 1.20)
	var yaw_noise = rng.randf_range(-deg_to_rad(25.0), deg_to_rad(25.0))

	if amr:
		amr.global_position = Vector3(offset_x, 0.0, offset_z)
		amr.rotation = Vector3(0.0, yaw_noise, 0.0)
		amr.velocity = Vector3.ZERO
		amr.set_rl_control(0.0, 0.0)

	# 2. Stow box in tray
	_stow_box_in_slot1()

	if drop_zone_marker:
		drop_zone_marker.global_position = Vector3(0.0, 0.02, 0.0)

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0

	var lin_vel = v_lin * amr.max_speed
	var ang_vel = v_ang * amr.turn_speed
	amr.set_rl_control(lin_vel, ang_vel)

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
	var dist = amr.global_position.distance_to(drop_zone_marker.global_position)
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying flag
	var carrying = 1.0 if (amr.get_stowed_box_count() > 0 or amr.held_box != null) else 0.0
	obs.append(carrying)

	# 10: Lift/tray status
	obs.append(carrying)

	# 11..12: Wall distances
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var reward: float = 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0
	var dist = amr.global_position.distance_to(drop_zone_marker.global_position)

	# 1. Approach alignment shaping toward drop zone
	var forward = -amr.global_transform.basis.z
	var to_zone = (drop_zone_marker.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_zone)
	if alignment >= 0.0:
		reward += alignment * 0.10
	else:
		reward -= 0.10 * abs(alignment)

	# 2. Strict anti-spinning penalty
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	reward -= 0.04 * abs(v_ang)
	if abs(v_ang) > 0.4 and amr._manual_linear_vel < 0.3:
		reward -= 0.08 * (abs(v_ang) - 0.4)

	# Distance progress shaping toward drop zone
	reward += (1.5 - minf(dist, 1.5)) * 0.08
	reward -= 0.01 # Time penalty

	# Deceleration shaping near drop point (prevents ramming/overshooting)
	if dist <= 1.5 and amr.current_speed > 0.6:
		reward -= 0.06 * (amr.current_speed - 0.6)

	# 3. Trigger drop action
	var in_drop_zone = (dist <= 1.50) and (alignment >= 0.30)
	if in_drop_zone:
		reward += maxf(0.0, trigger) * 0.20

		if (trigger > 0.30 or dist <= 0.80) and not is_placed:
			is_placed = true
			reward += 8.0 + maxf(0.0, trigger) * 1.5
			if carried_box and carried_box.get_parent() == amr.cargo_tray:
				amr.cargo_tray.remove_child(carried_box)
				add_child(carried_box)
				carried_box.global_position = drop_zone_marker.global_position + Vector3(0.0, 0.16, 0.0)
				carried_box.rotation = Vector3.ZERO
				carried_box.linear_velocity = Vector3.ZERO
				carried_box.angular_velocity = Vector3.ZERO
				carried_box.freeze = false
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
	return is_placed or wall_collided

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"distance_to_zone": amr.global_position.distance_to(drop_zone_marker.global_position) if (amr and drop_zone_marker) else 0.0,
		"is_placed": is_placed,
		"failed_attempt": failed_attempt,
		"wall_collided": wall_collided,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if is_placed else []
	}
