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
var trigger_attempted: bool = false

func _ready() -> void:
	max_episode_steps = 1200
	super._ready()

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	current_sub_stage = CycleSubStage.NAVIGATE_TO_ITEM
	wall_collided = false
	cycle_success = false
	trigger_attempted = false

	if amr:
		amr.reset_robot(Vector3.ZERO, 0.0)
		amr.is_manual_control = false
		amr.is_rl_control = true
		amr.held_box = null

	# Reset target box back to arena root
	if target_box:
		if target_box.get_parent() != self:
			if target_box.get_parent():
				target_box.get_parent().remove_child(target_box)
			add_child(target_box)
		target_box.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		target_box.freeze = true
		target_box.linear_velocity = Vector3.ZERO
		target_box.angular_velocity = Vector3.ZERO
		target_box.visible = true

	# 1. Randomize agent at origin area
	SpawnRandomizer.spawn_agent(amr, 3.0, rng)

	# 2. Randomize target box in one sector (>= 3.5m from agent)
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

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0

	var lin_vel = v_lin * amr.max_speed
	var ang_vel = v_ang * amr.turn_speed
	amr.set_rl_control(lin_vel, ang_vel)

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr:
		for i in range(13): obs.append(0.0)
		return obs

	# 0..3: Local pose
	var sub_pos = _get_active_subgoal_pos()
	var norm_x: float
	var norm_z: float
	if current_sub_stage in [CycleSubStage.PICK_UP, CycleSubStage.DROP_OFF]:
		norm_x = clampf((amr.global_position.x - sub_pos.x) / 2.5, -1.0, 1.0)
		norm_z = clampf((amr.global_position.z - sub_pos.z) / 2.5, -1.0, 1.0)
	else:
		norm_x = clampf(amr.global_position.x / arena_half_extent, -1.0, 1.0)
		norm_z = clampf(amr.global_position.z / arena_half_extent, -1.0, 1.0)

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
	var local_rel = amr.global_transform.basis.inverse() * (sub_pos - amr.global_position)
	var dist = _get_dist_to_active_subgoal()
	var sub_scale = 5.0 if (current_sub_stage in [CycleSubStage.PICK_UP, CycleSubStage.DROP_OFF]) else (arena_half_extent * 2.0)
	obs.append(clampf(local_rel.x / sub_scale, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / sub_scale, -1.0, 1.0))
	obs.append(clampf(dist / sub_scale, 0.0, 1.0))

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

	# Anti-spinning turning stability penalty
	reward -= 0.015 * abs(amr._rl_target_v_ang)

	var trigger = float(action[2]) if action.size() > 2 else 0.0

	match current_sub_stage:
		CycleSubStage.NAVIGATE_TO_ITEM:
			if cur_dist <= 1.25:
				current_sub_stage = CycleSubStage.PICK_UP
				reward += 1.0

		CycleSubStage.PICK_UP:
			if (trigger > 0.20 and cur_dist <= 1.6) or cur_dist <= 0.6:
				# Stows target box into cargo tray cleanly
				if target_box and amr and amr.cargo_tray:
					target_box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					target_box.freeze = true
					if target_box.get_parent():
						target_box.get_parent().remove_child(target_box)
					amr.cargo_tray.add_child(target_box)
					target_box.position = amr.slot_1_marker.position if amr.slot_1_marker else Vector3(0.0, 0.17, 0.3)
					target_box.rotation = Vector3.ZERO
				current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
				reward += 2.5
				prev_sub_goal_dist = _get_dist_to_active_subgoal()

		CycleSubStage.NAVIGATE_CARRYING:
			if cur_dist <= 1.15:
				current_sub_stage = CycleSubStage.DROP_OFF
				reward += 1.0

		CycleSubStage.DROP_OFF:
			if (trigger > 0.20 and cur_dist <= 1.35) or cur_dist <= 0.6:
				current_sub_stage = CycleSubStage.CYCLE_COMPLETE
				cycle_success = true
				reward += 5.0 # Full cycle completion bonus!
				if target_box and amr and target_box.get_parent() == amr.cargo_tray:
					amr.cargo_tray.remove_child(target_box)
					add_child(target_box)
					target_box.global_position = drop_zone_marker.global_position + Vector3(0.0, 0.16, 0.0)
					target_box.rotation = Vector3.ZERO
					target_box.linear_velocity = Vector3.ZERO
					target_box.angular_velocity = Vector3.ZERO
					target_box.freeze = false

	# Wall collision
	if abs(amr.global_position.x) >= (arena_half_extent - 0.4) or abs(amr.global_position.z) >= (arena_half_extent - 0.4):
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return cycle_success or wall_collided

func _get_info() -> Dictionary:
	return {
		"step": step_count,
		"sub_stage": int(current_sub_stage),
		"dist_to_subgoal": _get_dist_to_active_subgoal(),
		"cycle_success": cycle_success,
		"wall_collided": wall_collided
	}
