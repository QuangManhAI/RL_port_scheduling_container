class_name NavigateToItemEnv
extends TrainingEnvBase

## Stage S1: Navigate-to-Item Training Environment
## Agent learns spatial approach, orientation alignment, and goal distance keeping.

@export var arena_half_extent: float = 6.0
@export var grasp_reach_threshold: float = 1.05
@export var stop_speed_threshold: float = 0.30

@onready var target_box: ToteBox = $TargetBox
@onready var walls_node: Node3D = $ArenaWalls

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prev_distance_to_box: float = 0.0
var goal_reached: bool = false
var wall_collided: bool = false

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	goal_reached = false
	wall_collided = false

	# 1. Reset AMR state
	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# 2. Randomize spawn
	SpawnRandomizer.spawn_agent(amr, arena_half_extent, rng)
	var min_dist = DifficultyRamp.get_min_box_distance(difficulty, 2.0, 5.5)
	SpawnRandomizer.spawn_target_box(target_box, amr, arena_half_extent, min_dist, rng)

	prev_distance_to_box = _get_current_distance_to_box()

func _get_current_distance_to_box() -> float:
	if not amr or not target_box:
		return 999.0
	var amr_arm_pos = amr.shoulder.global_position if amr.shoulder else amr.global_position
	return amr_arm_pos.distance_to(target_box.global_position)

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr or not target_box:
		for i in range(13): obs.append(0.0)
		return obs

	# 0..3: Local pose [x/half_extent, z/half_extent, sin(yaw), cos(yaw)]
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

	# 6..8: Relative vector to box (in robot local frame) [dx, dz, distance]
	var local_rel = amr.global_transform.basis.inverse() * (target_box.global_position - amr.global_position)
	var dist = _get_current_distance_to_box()
	obs.append(clampf(local_rel.x / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(-local_rel.z / (arena_half_extent * 2.0), -1.0, 1.0)) # Forward offset in body frame
	obs.append(clampf(dist / (arena_half_extent * 2.0), 0.0, 1.0))

	# 9: Carrying flag (0.0)
	obs.append(0.0)

	# 10: Lift/tray status (0.0)
	obs.append(0.0)

	# 11..12: Nearest wall distance & relative angle
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	var min_wall_dist = minf(dist_x, dist_z)
	obs.append(clampf(min_wall_dist / arena_half_extent, 0.0, 1.0))
	obs.append(0.0) # Angle to nearest obstacle

	return obs

func _compute_reward(action: Array) -> float:
	var cur_dist = _get_current_distance_to_box()
	var delta_dist = prev_distance_to_box - cur_dist
	prev_distance_to_box = cur_dist

	var reward: float = 0.0

	# 1. Potential-based distance progress shaping
	reward += delta_dist * 3.0

	# 2. Time step penalty
	reward -= 0.01

	# 3. Orientation alignment shaping (facing box)
	var forward = -amr.global_transform.basis.z
	var to_box = (target_box.global_position - amr.global_position).normalized()
	var alignment = forward.dot(to_box)
	reward += alignment * 0.03

	# Soft penalty for driving backwards
	if amr._manual_linear_vel < -0.1:
		reward -= 0.05

	# 4. Success bonus on arrival (requires facing box within ~70 degrees and coming to a controlled stop)
	if cur_dist <= grasp_reach_threshold:
		if alignment >= 0.35:
			if amr.current_speed <= stop_speed_threshold:
				goal_reached = true
				reward += 3.0 + alignment * 1.0
			else:
				# Near box but still cruising: encourage deceleration
				reward += 0.08 - (amr.current_speed / maxf(amr.max_speed, 1.0)) * 0.12
		else:
			reward -= 0.1

	# 5. Wall collision penalty
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
		"distance_to_box": _get_current_distance_to_box(),
		"goal_reached": goal_reached,
		"wall_collided": wall_collided,
		"terminal_pose": [amr.global_position.x, amr.global_position.z, amr.rotation.y] if (goal_reached or wall_collided) else []
	}
