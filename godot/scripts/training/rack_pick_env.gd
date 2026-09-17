class_name RackPickEnv
extends "res://scripts/training/rack_targeting_env.gd"

## Stage R3: Rack Box Pick & Stow Environment.
## Extends Stage R2 with active robotic arm pick execution and tray stowing.
## The AMR must dock in a valid stance where ArmIKSolver yields ik.success == true,
## fire the trigger action (action[2] > 0.25), extract the box from the assigned
## tier (1-4, Left/Right), and stow it into the onboard cargo tray.

var is_picked: bool = false
var is_stowed: bool = false
var trigger_attempted: bool = false
var failed_attempt: bool = false
var pick_in_progress: bool = false
var stow_in_progress: bool = false
var _stow_reset_timer: float = 0.0

func _ready() -> void:
	policy_json_path = "res://models/ppo_r3_policy.json"
	super._ready()
	max_episode_steps = 350

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	is_picked = false
	is_stowed = false
	trigger_attempted = false
	failed_attempt = false
	pick_in_progress = false
	stow_in_progress = false
	_stow_reset_timer = 0.0

	super._on_arena_reset(seed_val, difficulty)

	if amr:
		# Set fast tween speed for efficient RL training
		amr.arm_tween_speed_scale = 3.5

		# Stage R3 Curriculum Spawning:
		# Spawn in front approach corridor (1.8m to 3.4m from rack bay)
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
		var spawn_angle = rng.randf_range(-PI * 0.75, -PI * 0.25)
		var spawn_dist = rng.randf_range(2.0, 3.4)
		var spawn_x = clampf(cos(spawn_angle) * spawn_dist, -(arena_half_extent - 1.2), arena_half_extent - 1.2)
		var spawn_z = -absf(sin(spawn_angle) * spawn_dist)
		var spawn_yaw = rng.randf_range(-deg_to_rad(35.0), deg_to_rad(35.0))

		amr.reset_robot(Vector3(spawn_x, 0.0, spawn_z), spawn_yaw)
		amr.is_manual_control = false
		amr.is_rl_control = true

	prev_sub_goal_dist = _get_dist_to_target_box()

func _apply_action(action: Array) -> void:
	if not amr:
		return

	# If arm is actively tweening / manipulating, brake chassis to halt
	if amr._is_arm_tweening:
		amr.set_rl_control(0.0, 0.0)
		return

	# Otherwise apply normal docking driving controls
	super._apply_action(action)

	# Trigger action (action[2])
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0
	if not trigger_attempted and not pick_in_progress and not is_stowed:
		var target_box: ToteBox = boxes[target_box_idx] if target_box_idx < boxes.size() else null
		if target_box and is_instance_valid(target_box):
			var local_target = amr.arm.to_local(target_box.global_position)
			var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)
			var forward = -amr.global_transform.basis.z
			var rack_face_norm = _get_rack_face_normal()
			var face_align = forward.dot(-rack_face_norm)
			var in_reach = ik.success and amr.current_speed <= 0.45 and face_align >= 0.45 and not rack_toppled

			if in_reach and trigger > 0.0:
				trigger_attempted = true
				pick_in_progress = true
				amr.trigger_rl_action(target_box)
			elif trigger > 0.35 and not in_reach and _get_dist_to_target_box() > 2.2:
				# Premature trigger attempt while far away
				failed_attempt = true

func _physics_process(delta: float) -> void:
	# Monitor pick and stow completion in physics frames
	if amr and pick_in_progress:
		if amr.held_box != null:
			is_picked = true

		# Auto-chain into dynamic stow once arm reaches held-ready in aisle
		if amr.arm_motion_state == amr.ArmMotionState.HELD_READY and not stow_in_progress:
			stow_in_progress = true
			amr.execute_dynamic_stow()

		# Check when box is deposited into cargo tray and arm has returned to rest pose
		if amr.get_stowed_box_count() > 0 and not amr._is_arm_tweening:
			is_stowed = true
			pick_in_progress = false

	# Auto-cycle to next target after stowing (both in native AI and manual preview)
	if is_stowed and not amr._is_arm_tweening:
		_stow_reset_timer += delta
		if _stow_reset_timer >= 1.6:
			_stow_reset_timer = 0.0
			_on_arena_reset(0, 0.0)

	super._physics_process(delta)

func _compute_reward(action: Array) -> float:
	var reward: float = 0.0
	if not amr or not rack:
		return reward

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	var face_align = forward.dot(-rack_face_norm)

	# 1. Distance shaping toward target box (only while not stowed)
	if not is_stowed and not pick_in_progress:
		var progress = prev_sub_goal_dist - cur_dist
		reward += progress * 4.0
		prev_sub_goal_dist = cur_dist

		# Alignment bonus when approaching
		if cur_dist <= 3.5:
			reward += maxf(0.0, face_align) * 0.25

		# Controlled speed near rack (< 1.6m)
		if cur_dist <= 1.6 and amr.current_speed > 0.45:
			reward -= 0.15 * (amr.current_speed - 0.45)

		# Tier-aware distance guidance:
		# Higher tiers (3 & 4) have large vertical rise, requiring a closer horizontal approach
		# (1.45m - 1.75m) so the arm can reach. Lower tiers can reach from 1.85m - 2.25m.
		var ideal_dock_dist: float = 1.60 if target_tier >= 3 else 2.05
		if cur_dist > ideal_dock_dist:
			reward -= 0.20 * (cur_dist - ideal_dock_dist)

	# 2. Rack tilt & topple penalty
	var up_alignment = rack.global_transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.94:
		rack_toppled = true
		reward -= 10.0

	# 3. Continuous IK reachability bonus and trigger shaping
	var target_box: ToteBox = boxes[target_box_idx] if target_box_idx < boxes.size() else null
	if target_box and is_instance_valid(target_box) and not is_stowed:
		var local_target = amr.arm.to_local(target_box.global_position)
		var ik_res: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)
		last_ik_dist = ik_res.target_distance
		last_ik_err = ik_res.error_message

		if cur_dist <= 2.6:
			if ik_res.target_distance > ArmIKSolver.MAX_REACH:
				reward -= 0.60 * (ik_res.target_distance - ArmIKSolver.MAX_REACH)
			elif ik_res.success:
				reward += 0.45
				var sweet_margin = 1.0 - absf(ik_res.target_distance - 1.25) / 1.0
				reward += maxf(0.0, sweet_margin) * 0.35
				var trigger: float = float(action[2]) if action.size() > 2 else 0.0
				# Monotonic gradient encouraging positive trigger when reachable
				reward += (trigger + 1.0) * 0.70

	# 4. Trigger and Pick/Stow Milestones
	if failed_attempt:
		reward -= 0.05
		failed_attempt = false # One-shot penalty per false attempt

	if is_picked and not is_stowed:
		reward += 0.20 # Holding box reward

	if is_stowed:
		reward += 20.0 + maxf(0.0, face_align) * 3.0
		docking_success = true
		ik_success = true

	# 5. Time step penalty
	reward -= 0.02

	return reward

func _is_terminated() -> bool:
	return is_stowed or rack_toppled or wall_collided

func _get_info() -> Dictionary:
	var info = super._get_info()
	info["is_picked"] = is_picked
	info["is_stowed"] = is_stowed
	info["trigger_attempted"] = trigger_attempted
	info["failed_attempt"] = failed_attempt
	return info
