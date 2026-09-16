class_name ChainedCycleEnv
extends TrainingEnvBase

## Stage S5: Chained Full Cycle Training Environment (S1 -> S2 -> S3 -> S4)
## Validates end-to-end skill composition across navigate, pickup, carry, and drop-off.

@export var arena_half_extent: float = 8.0

@onready var target_box: ToteBox = $TargetBox
@onready var drop_zone_marker: Node3D = $DropZoneMarker

enum CycleSubStage {
	NAVIGATE_TO_ITEM = 1,
	PICK_UP = 2,
	NAVIGATE_CARRYING = 3,
	DROP_OFF = 4,
	CYCLE_COMPLETE = 5
}

var current_sub_stage: CycleSubStage = CycleSubStage.NAVIGATE_TO_ITEM
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prev_sub_goal_dist: float = 0.0
var wall_collided: bool = false
var cycle_success: bool = false

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	current_sub_stage = CycleSubStage.NAVIGATE_TO_ITEM
	wall_collided = false
	cycle_success = false

	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# 1. Randomize agent at origin area
	SpawnRandomizer.spawn_agent(amr, 3.0, rng)

	# 2. Randomize target box in one sector (e.g. Quadrant 1/2)
	SpawnRandomizer.spawn_target_box(target_box, amr, arena_half_extent - 1.5, 3.5, rng)

	# 3. Randomize drop zone in opposing sector (>= 5m from box)
	SpawnRandomizer.spawn_drop_zone(drop_zone_marker, amr, arena_half_extent - 1.5, 5.0, rng)

	prev_sub_goal_dist = _get_dist_to_active_subgoal()

func _get_active_subgoal_pos() -> Vector3:
	if current_sub_stage in [CycleSubStage.NAVIGATE_TO_ITEM, CycleSubStage.PICK_UP]:
		return target_box.global_position if target_box else Vector3.ZERO
	else:
		return drop_zone_marker.global_position if drop_zone_marker else Vector3.ZERO

func _get_dist_to_active_subgoal() -> float:
	if not amr:
		return 999.0
	return amr.global_position.distance_to(_get_active_subgoal_pos())

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr:
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

	# 6..8: Relative vector to active sub-goal (box if not carrying, drop zone if carrying)
	var sub_pos = _get_active_subgoal_pos()
	var local_rel = amr.global_transform.basis.inverse() * (sub_pos - amr.global_position)
	var dist = _get_dist_to_active_subgoal()
	obs.append(clampf(local_rel.x / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(local_rel.z / (arena_half_extent * 2.0), -1.0, 1.0))
	obs.append(clampf(dist / (arena_half_extent * 2.0), 0.0, 1.0))

	# 9: Carrying flag
	var is_carrying = 1.0 if (amr.get_stowed_box_count() > 0 or amr.held_box != null) else 0.0
	obs.append(is_carrying)

	# 10: Lift/tray status
	obs.append(is_carrying)

	# 11..12: Nearest wall distance
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / arena_half_extent, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var cur_dist = _get_dist_to_active_subgoal()
	var delta_dist = prev_sub_goal_dist - cur_dist
	prev_sub_goal_dist = cur_dist

	var reward: float = 0.0
	reward += delta_dist * 2.0
	reward -= 0.01

	var trigger = float(action[2]) if action.size() > 2 else 0.0

	match current_sub_stage:
		CycleSubStage.NAVIGATE_TO_ITEM:
			if cur_dist <= 1.2:
				current_sub_stage = CycleSubStage.PICK_UP
				reward += 1.0

		CycleSubStage.PICK_UP:
			if trigger > 0.5:
				if amr.held_box != null or amr.get_stowed_box_count() > 0:
					current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
					reward += 2.0
					prev_sub_goal_dist = _get_dist_to_active_subgoal()

		CycleSubStage.NAVIGATE_CARRYING:
			if cur_dist <= 1.2:
				current_sub_stage = CycleSubStage.DROP_OFF
				reward += 1.0

		CycleSubStage.DROP_OFF:
			if trigger > 0.5 and cur_dist <= 0.9:
				current_sub_stage = CycleSubStage.CYCLE_COMPLETE
				cycle_success = true
				reward += 5.0 # Full cycle completion bonus!

	# Wall collision
	if abs(amr.global_position.x) >= (arena_half_extent - 0.4) or abs(amr.global_position.z) >= (arena_half_extent - 0.4):
		wall_collided = true
		reward -= 1.0

	return reward

func _is_terminated() -> bool:
	return cycle_success or wall_collided

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"sub_stage": int(current_sub_stage),
		"cycle_success": cycle_success,
		"wall_collided": wall_collided
	}
