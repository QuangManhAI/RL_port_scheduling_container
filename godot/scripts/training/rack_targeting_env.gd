class_name RackTargetingEnv
extends "res://scripts/training/rack_docking_env.gd"

## Stage R2: Tier-Aware Fine Positioning & Arm IK Targeting Environment.
## Extends Stage R1 with physical robotic arm IK feasibility validation.
## The AMR must dock in a stance where ArmIKSolver yields ik.success == true
## for the specific target tier (1-4) and slot side (Left/Right).

var ik_success: bool = false
var last_ik_dist: float = 0.0
var last_ik_err: String = ""

func _ready() -> void:
	policy_json_path = "res://models/ppo_r2_policy.json"
	super._ready()

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	ik_success = false
	last_ik_dist = 0.0
	last_ik_err = ""
	super._on_arena_reset(seed_val, difficulty)

func _compute_reward(_action: Array) -> float:
	var reward: float = 0.0
	if not amr or not rack:
		return reward

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	var face_align = forward.dot(-rack_face_norm)

	# 1. Distance shaping reward towards target box
	var progress = prev_sub_goal_dist - cur_dist
	reward += progress * 4.0
	prev_sub_goal_dist = cur_dist

	# 2. Alignment bonus when approaching
	if cur_dist <= 3.5:
		reward += maxf(0.0, face_align) * 0.25

	# 3. Controlled speed near rack (< 1.6m)
	if cur_dist <= 1.6 and amr.current_speed > 0.45:
		reward -= 0.15 * (amr.current_speed - 0.45)

	# 4. Rack tilt & topple detection
	var up_alignment = rack.global_transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.94:
		rack_toppled = true
		reward -= 10.0

	# 5. Step penalty
	reward -= 0.02

	if not amr.arm:
		return reward

	# Arm IK evaluation
	var target_box_pos = _get_target_box_pos()
	var local_target = amr.arm.to_local(target_box_pos)
	var ik_res: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)

	last_ik_dist = ik_res.target_distance
	last_ik_err = ik_res.error_message

	# Continuous IK reach distance shaping when approaching dock
	if cur_dist <= 2.6:
		if ik_res.target_distance > ArmIKSolver.MAX_REACH:
			# Upper tiers (T3, T4) require driving closer into the bay
			reward -= 0.35 * (ik_res.target_distance - ArmIKSolver.MAX_REACH)
		elif ik_res.target_distance >= ArmIKSolver.MIN_REACH:
			# Reward being inside the valid kinematic reach envelope
			reward += 0.30
			var sweet_margin = 1.0 - absf(ik_res.target_distance - 1.25) / 1.0
			reward += maxf(0.0, sweet_margin) * 0.30

	# Stage R2 Completion Gate:
	# 1. Arm IK Solver successfully found valid joint angles
	# 2. AMR controlled crawling/stationary (speed <= 0.45 m/s)
	# 3. Rack stable (tilt < 10 deg)
	var is_stable = up_alignment >= 0.985
	if ik_res.success and amr.current_speed <= 0.45 and is_stable and face_align >= 0.50:
		ik_success = true
		docking_success = true
		reward += 15.0 + face_align * 3.0

	return reward

func _is_terminated() -> bool:
	return ik_success or rack_toppled or wall_collided

func _get_info() -> Dictionary:
	var info = super._get_info()
	info["ik_success"] = ik_success
	info["ik_dist"] = last_ik_dist
	info["ik_err"] = last_ik_err
	return info
