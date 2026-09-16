class_name ChainedCycleEnv
extends TrainingEnvBase

## Stage S5: Chained Full Cycle Training Environment (S1 -> S2 -> S3 -> S4)
## Composes modular skills: Navigate-to-Item, Pick-Up, Navigate-while-Carrying, Drop-Off.
## Implements resilient alignment-gated handover, hysteresis fallback, and 180-deg saddle point resolution.

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
var _sub_stage_steps: int = 0

func _ready() -> void:
	max_episode_steps = 600
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

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	wall_collided = false
	cycle_success = false
	trigger_attempted = false
	_sub_stage_steps = 0
	current_sub_stage = CycleSubStage.NAVIGATE_TO_ITEM

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

	# Standard full-cycle task spawn:
	# 1. Spawn agent
	SpawnRandomizer.spawn_agent(amr, 3.0, rng)
	# 2. Spawn target box >= 3.5m away
	SpawnRandomizer.spawn_target_box(target_box, amr, arena_half_extent - 1.5, 3.5, rng)
	# 3. Spawn drop zone >= 5.0m away from agent
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

	var cur_dist = _get_dist_to_active_subgoal()
	var forward = -amr.global_transform.basis.z
	var sub_pos = _get_active_subgoal_pos()
	var to_subgoal = (sub_pos - amr.global_position).normalized()
	var alignment = forward.dot(to_subgoal)

	# 180-degree symmetry breaker: if target is directly behind and policy produces no turn command
	if alignment < -0.85 and cur_dist > 1.5 and abs(v_ang) < 0.15:
		v_ang = 0.8

	# Clamp reverse to small docking adjustment (-0.15), matching curriculum training
	v_lin = clampf(v_lin, -0.15, 1.0)

	# Controlled AMR speeds for smooth, stable warehouse docking
	var lin_vel = v_lin * 2.8 # 2.8 m/s max forward speed
	var ang_vel = v_ang * 2.2 # 2.2 rad/s max turning speed
	amr.set_rl_control(lin_vel, ang_vel)

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr:
		for i in range(13): obs.append(0.0)
		return obs

	# 0..3: Global arena pose normalized to universal 8m half-extent
	var norm_x = clampf(amr.global_position.x / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Normalized velocities [v_lin/max_speed, v_ang/turn_speed]
	var norm_v = clampf(amr._manual_linear_vel / 2.8, -1.0, 1.0)
	var norm_w = clampf(amr._rl_target_v_ang / 2.2, -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative horizontal vector to active sub-goal in robot local frame
	var sub_pos = _get_active_subgoal_pos()
	var local_rel = amr.global_transform.basis.inverse() * (sub_pos - amr.global_position)
	var dist = _get_dist_to_active_subgoal()
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9: Carrying status (0.0 if seeking box, 1.0 if seeking drop zone)
	var is_carrying = 1.0 if (current_sub_stage >= CycleSubStage.NAVIGATE_CARRYING) else 0.0
	obs.append(is_carrying)

	# 10: Lift/tray status (matches carrying flag for single-slot payload)
	var tray_status = 1.0 if (current_sub_stage >= CycleSubStage.NAVIGATE_CARRYING) else 0.0
	obs.append(tray_status)

	# 11..12: Nearest wall distance
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	return obs

func _compute_reward(action: Array) -> float:
	var cur_dist = _get_dist_to_active_subgoal()
	var delta_dist = prev_sub_goal_dist - cur_dist
	prev_sub_goal_dist = cur_dist

	var reward: float = 0.0
	# 1. Continuous potential-based progress reward
	reward += delta_dist * 3.0
	reward -= 0.01 # Time step penalty

	var forward = -amr.global_transform.basis.z
	var sub_pos = _get_active_subgoal_pos()
	var to_subgoal = (sub_pos - amr.global_position).normalized()
	var alignment = forward.dot(to_subgoal)

	# 2. Strict Anti-Spinning Penalty
	var v_ang = float(action[1]) if action.size() > 1 else 0.0
	reward -= 0.04 * abs(v_ang)

	# Severe penalty for spinning in place or pirouetting
	if abs(v_ang) > 0.4 and amr._manual_linear_vel < 0.3:
		reward -= 0.08 * (abs(v_ang) - 0.4)

	# 3. Heading alignment reward & penalty for turning away
	if alignment >= 0.0:
		reward += alignment * 0.08
	else:
		reward -= 0.08 * abs(alignment)

	# 4. Deceleration / controlled approach near target (prevents overshooting!)
	if cur_dist <= 2.2 and amr.current_speed > 0.8:
		reward -= 0.08 * (amr.current_speed - 0.8)

	var trigger = float(action[2]) if action.size() > 2 else 0.0
	_sub_stage_steps += 1

	match current_sub_stage:
		CycleSubStage.NAVIGATE_TO_ITEM:
			# S1 -> S2 Handover:
			# Matches S1 training goal condition (alignment >= 0.35 at grasp_reach_threshold 1.20m).
			# Hysteresis fallback on S2 recovers if the approach was marginal.
			if (cur_dist <= 1.25 and alignment >= 0.35) or (cur_dist <= 0.90 and alignment >= 0.20):
				current_sub_stage = CycleSubStage.PICK_UP
				_sub_stage_steps = 0
				reward += 3.0 + alignment * 1.0
				prev_sub_goal_dist = cur_dist

		CycleSubStage.PICK_UP:
			# S2 Grasp: unconditional at bumper contact (≤ 0.60m), or alignment ≥ 0.30 with trigger/proximity
			if cur_dist <= 0.60:
				# Unconditional auto-pick: robot is touching the box
				_stow_box_in_tray()
				current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
				_sub_stage_steps = 0
				reward += 6.0 + maxf(0.0, trigger) * 1.0
				prev_sub_goal_dist = _get_dist_to_active_subgoal()
			else:
				var in_grasp_range = (cur_dist <= 1.50) and (alignment >= 0.30)
				if in_grasp_range:
					reward += maxf(0.0, trigger) * 0.20
					if trigger > 0.30 or cur_dist <= 0.85:
						_stow_box_in_tray()
						current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
						_sub_stage_steps = 0
						reward += 6.0 + maxf(0.0, trigger) * 1.0
						prev_sub_goal_dist = _get_dist_to_active_subgoal()
				elif _sub_stage_steps >= 15 and (cur_dist > 1.50 or alignment < 0.20):
					# Resilient hysteresis fallback: if robot drifted or turned away after trying, let S1 re-navigate!
					current_sub_stage = CycleSubStage.NAVIGATE_TO_ITEM
					_sub_stage_steps = 0

		CycleSubStage.NAVIGATE_CARRYING:
			# S3 -> S4 Handover:
			# Matches S3 training goal condition (alignment >= 0.35 at arrival_threshold 1.20m).
			# Hysteresis fallback on S4 recovers if the approach was marginal.
			if (cur_dist <= 1.35 and alignment >= 0.35) or (cur_dist <= 0.90 and alignment >= 0.20):
				current_sub_stage = CycleSubStage.DROP_OFF
				_sub_stage_steps = 0
				reward += 3.0 + alignment * 1.0
				prev_sub_goal_dist = cur_dist

		CycleSubStage.DROP_OFF:
			# S4 Drop-off: unconditional at bumper contact (≤ 0.60m), or alignment ≥ 0.30 with trigger/proximity
			if cur_dist <= 0.60:
				# Unconditional auto-drop: robot is on top of the drop zone
				_place_box_in_drop_zone()
				cycle_success = true
				current_sub_stage = CycleSubStage.CYCLE_COMPLETE
				_sub_stage_steps = 0
				reward += 10.0 + maxf(0.0, trigger) * 2.0
			else:
				var in_drop_range = (cur_dist <= 1.50) and (alignment >= 0.30)
				if in_drop_range:
					reward += maxf(0.0, trigger) * 0.20
					if trigger > 0.30 or cur_dist <= 0.85:
						_place_box_in_drop_zone()
						cycle_success = true
						current_sub_stage = CycleSubStage.CYCLE_COMPLETE
						_sub_stage_steps = 0
						reward += 10.0 + maxf(0.0, trigger) * 2.0
				elif _sub_stage_steps >= 15 and (cur_dist > 1.50 or alignment < 0.20):
					# Resilient hysteresis fallback: if robot drifted or turned away after trying, let S3 re-navigate!
					current_sub_stage = CycleSubStage.NAVIGATE_CARRYING
					_sub_stage_steps = 0

	# 5. Wall collision penalty
	var wall_limit = arena_half_extent - 0.40
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return cycle_success or wall_collided

func _get_info() -> Dictionary:
	var forward: Vector3 = -amr.global_transform.basis.z if amr else Vector3.FORWARD
	var sub_pos = _get_active_subgoal_pos()
	var to_subgoal: Vector3 = (sub_pos - amr.global_position).normalized() if amr else Vector3.FORWARD
	return {
		"step": step_count,
		"sub_stage": int(current_sub_stage),
		"dist_to_subgoal": _get_dist_to_active_subgoal(),
		"speed": amr.current_speed if amr else 0.0,
		"alignment": forward.dot(to_subgoal),
		"is_carrying": (current_sub_stage >= CycleSubStage.NAVIGATE_CARRYING),
		"cycle_success": cycle_success,
		"wall_collided": wall_collided
	}
