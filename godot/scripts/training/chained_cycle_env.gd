class_name ChainedCycleEnv
extends TrainingEnvBase

## Stage S5: Chained Full Cycle Training Environment (S1 -> S2 -> S3 -> S4)
## Validates end-to-end skill composition across navigate, pickup, carry, and drop-off.

@export var arena_half_extent: float = 8.0
@export var force_full_cycle_start: bool = false

@onready var target_box: ToteBox = $TargetBox
@onready var drop_zone_marker: Node3D = $DropZoneMarker

enum CycleSubStage {
	NAVIGATE_TO_ITEM = 1,
	NAVIGATE_CARRYING = 2,
	CYCLE_COMPLETE = 3
}

var current_sub_stage: CycleSubStage = CycleSubStage.NAVIGATE_TO_ITEM
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prev_sub_goal_dist: float = 0.0
var wall_collided: bool = false
var cycle_success: bool = false
var trigger_attempted: bool = false

func _ready() -> void:
	max_episode_steps = 300
	super._ready()

func _stow_box_in_tray() -> void:
	if target_box and amr and amr.cargo_tray:
		target_box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		target_box.freeze = true
		if target_box.get_parent():
			target_box.get_parent().remove_child(target_box)
		amr.cargo_tray.add_child(target_box)
		target_box.position = amr.slot_1_marker.position if amr.slot_1_marker else Vector3(0.0, 0.16, 0.22)
		target_box.rotation = Vector3.ZERO

func _place_box_in_drop_zone() -> void:
	if target_box and amr and target_box.get_parent() == amr.cargo_tray:
		amr.cargo_tray.remove_child(target_box)
		add_child(target_box)
		target_box.global_position = drop_zone_marker.global_position + Vector3(0.0, 0.16, 0.0)
		target_box.rotation = Vector3.ZERO
		target_box.linear_velocity = Vector3.ZERO
		target_box.angular_velocity = Vector3.ZERO
		target_box.freeze = false

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
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

	# Curriculum spawn distribution:
	# If difficulty < 1.0 and not force_full_cycle_start, 25% chance of starting carrying
	# so that the single network learns both pick-up and drop-off in parallel.
	var start_carrying = false
	if not force_full_cycle_start and difficulty < 1.0:
		start_carrying = (rng.randf() < 0.25)

	if start_carrying:
		current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
		_stow_box_in_tray()
		SpawnRandomizer.spawn_agent(amr, 4.0, rng)
		SpawnRandomizer.spawn_drop_zone(drop_zone_marker, amr, arena_half_extent - 1.5, 4.0, rng)
	else:
		current_sub_stage = CycleSubStage.NAVIGATE_TO_ITEM
		SpawnRandomizer.spawn_agent(amr, 3.0, rng)
		SpawnRandomizer.spawn_target_box(target_box, amr, arena_half_extent - 1.5, 3.5, rng)
		SpawnRandomizer.spawn_drop_zone(drop_zone_marker, amr, arena_half_extent - 1.5, 5.0, rng)

	prev_sub_goal_dist = _get_dist_to_active_subgoal()

func _get_active_subgoal_pos() -> Vector3:
	var is_carrying = (amr.get_stowed_box_count() > 0 or amr.held_box != null) if amr else false
	if not is_carrying:
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

	# 0..3: Global arena pose normalized to [-1.0, 1.0] (Zero coordinate jump)
	var norm_x = clampf(amr.global_position.x / arena_half_extent, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / arena_half_extent, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Normalized velocities [v_lin/max_speed, v_ang/turn_speed]
	var norm_v = clampf(amr._manual_linear_vel / maxf(amr.max_speed, 1.0), -1.0, 1.0)
	var norm_w = clampf(amr._rl_target_v_ang / maxf(amr.turn_speed, 1.0), -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative horizontal vector to active sub-goal in robot local frame
	var sub_pos = _get_active_subgoal_pos()
	var local_rel = amr.global_transform.basis.inverse() * (sub_pos - amr.global_position)
	var dist = _get_dist_to_active_subgoal()
	var norm_scale = arena_half_extent * 2.0
	obs.append(clampf(local_rel.x / norm_scale, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / norm_scale, -1.0, 1.0))
	obs.append(clampf(dist / norm_scale, 0.0, 1.0))

	# 9: Carrying status (0.0 if seeking box, 1.0 if seeking drop zone)
	var is_carrying = 1.0 if (amr.get_stowed_box_count() > 0 or amr.held_box != null) else 0.0
	obs.append(is_carrying)

	# 10: Lift/tray status (matches carrying flag for single-slot payload)
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
	# 1. Continuous potential-based progress reward
	reward += delta_dist * 2.5
	reward -= 0.01 # Time step penalty

	# 2. Anti-spinning turning stability penalty
	reward -= 0.015 * abs(amr._rl_target_v_ang)

	var forward = -amr.global_transform.basis.z
	var sub_pos = _get_active_subgoal_pos()
	var to_subgoal = (sub_pos - amr.global_position).normalized()
	var alignment = forward.dot(to_subgoal)

	# 3. Heading alignment toward active sub-goal
	if cur_dist <= 2.5:
		reward += maxf(0.0, alignment) * 0.05

	# 4. Soft penalty for driving backwards
	if amr._manual_linear_vel < -0.1:
		reward -= 0.03

	# 5. Deceleration / controlled approach near target
	if cur_dist <= 1.4 and abs(amr._manual_linear_vel) > 0.9:
		reward -= 0.03 * (abs(amr._manual_linear_vel) - 0.9)

	var trigger = float(action[2]) if action.size() > 2 else 0.0
	var is_carrying = (amr.get_stowed_box_count() > 0 or amr.held_box != null)

	if not is_carrying:
		# Approach & Pick Up Box
		if cur_dist <= 1.35 and alignment >= 0.40:
			# Positive guidance gradient for trigger when in grasp range
			reward += maxf(0.0, trigger) * 0.15

			if trigger > 0.40 or cur_dist <= 0.65:
				_stow_box_in_tray()
				current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
				reward += 5.0 + maxf(0.0, trigger) * 0.5
				prev_sub_goal_dist = _get_dist_to_active_subgoal()
		elif trigger > 0.50 and cur_dist > 1.8:
			reward -= 0.05
	else:
		# Carry & Drop Off Box
		if cur_dist <= 1.35 and alignment >= 0.40:
			# Positive guidance gradient for trigger when inside drop zone
			reward += maxf(0.0, trigger) * 0.15

			if trigger > 0.40 or cur_dist <= 0.65:
				_place_box_in_drop_zone()
				cycle_success = true
				current_sub_stage = CycleSubStage.CYCLE_COMPLETE
				reward += 10.0 + maxf(0.0, trigger) * 1.0
		elif trigger > 0.50 and cur_dist > 1.8:
			reward -= 0.05

	# 6. Wall collision
	var wall_limit = arena_half_extent - 0.40
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
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
