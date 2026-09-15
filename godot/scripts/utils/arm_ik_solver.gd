class_name ArmIKSolver
extends RefCounted

## Analytical Closed-Form 3D Inverse Kinematics Solver for AMR 4-DOF Manipulator.
## Solves Base Yaw, Shoulder Pitch, Elbow Pitch, and Wrist Pitch in O(1) time.

const SHOULDER_OFFSET_Y: float = 0.10 # Height offset of shoulder joint relative to arm base (m)
const L1_BOOM: float = 0.65          # Shoulder to Elbow link length (m)
const L2_FOREARM: float = 0.55       # Elbow to Wrist link length (m)
const L3_GRIPPER: float = 0.22       # Wrist to Gripper contact center (m)
const MAX_REACH: float = 1.40        # Maximum reach envelope (m)
const MIN_REACH: float = 0.25        # Minimum reach envelope (m)

## Result struct containing calculated joint angles and reachability status
class IKResult:
	var success: bool = false
	var base_yaw: float = 0.0       # Rotation around Y (radians)
	var shoulder_pitch: float = 0.0 # Rotation around X (radians)
	var elbow_pitch: float = 0.0    # Rotation around X (radians)
	var wrist_pitch: float = 0.0    # Rotation around X (radians)
	var target_distance: float = 0.0
	var error_message: String = ""

## Solves IK for a target position in the local coordinate frame of RoboticArm
static func solve_local(target: Vector3, approach_pitch: float = 0.0) -> IKResult:
	var res := IKResult.new()

	# 1. Target relative to shoulder pivot
	var p_sh: Vector3 = target - Vector3(0.0, SHOULDER_OFFSET_Y, 0.0)
	res.target_distance = target.length()

	# 2. Base Azimuth Yaw
	# In Godot 3D, forward is -Z, right is +X, left is -X.
	# Positive rotation around Y rotates toward -X, negative rotation rotates toward +X.
	# atan2(-x, -z) gives 0 for -Z, -PI/2 for +X, +PI/2 for -X, and PI for +Z.
	var target_xz := Vector2(p_sh.x, p_sh.z)
	var r_total: float = target_xz.length()

	if r_total < 0.001:
		res.base_yaw = 0.0
	else:
		res.base_yaw = atan2(-p_sh.x, -p_sh.z)

	# 3. Reachability Check
	if res.target_distance > MAX_REACH:
		res.success = false
		res.error_message = "Target out of reach (%.2fm > %.2fm)" % [res.target_distance, MAX_REACH]
		return res

	if res.target_distance < MIN_REACH:
		res.success = false
		res.error_message = "Target too close to turret (%.2fm < %.2fm)" % [res.target_distance, MIN_REACH]
		return res

	# 4. Planar projection for Two-Bone 2D IK
	# Offset wrist backwards along horizontal approach direction by L3_GRIPPER
	var r_wrist: float = r_total - L3_GRIPPER * cos(approach_pitch)
	var y_wrist: float = p_sh.y - L3_GRIPPER * sin(approach_pitch)

	var d_wrist: float = sqrt(r_wrist * r_wrist + y_wrist * y_wrist)
	var max_two_bone: float = L1_BOOM + L2_FOREARM - 0.005
	var min_two_bone: float = abs(L1_BOOM - L2_FOREARM) + 0.005

	if d_wrist > max_two_bone or d_wrist < min_two_bone:
		res.success = false
		res.error_message = "Wrist target outside 2-bone envelope (d=%.2fm, range=[%.2f, %.2f])" % [d_wrist, min_two_bone, max_two_bone]
		return res

	# 5. Law of Cosines for Shoulder and Elbow
	var cos_alpha: float = (L1_BOOM * L1_BOOM + d_wrist * d_wrist - L2_FOREARM * L2_FOREARM) / (2.0 * L1_BOOM * d_wrist)
	var cos_beta: float = (L1_BOOM * L1_BOOM + L2_FOREARM * L2_FOREARM - d_wrist * d_wrist) / (2.0 * L1_BOOM * L2_FOREARM)

	cos_alpha = clampf(cos_alpha, -1.0, 1.0)
	cos_beta = clampf(cos_beta, -1.0, 1.0)

	var alpha: float = acos(cos_alpha)
	var beta: float = acos(cos_beta)
	var phi: float = atan2(y_wrist, r_wrist)

	# 6. Map into Godot arm joint reference frames:
	# Boom rest pose points along +Y. Tilting forward toward -Z is negative pitch.
	var shoulder_elevation: float = phi + alpha
	res.shoulder_pitch = -(PI * 0.5 - shoulder_elevation)

	# Elbow bends forward/downward toward target
	res.elbow_pitch = -(PI - beta)

	# Wrist keeps gripper horizontal (total pitch = -PI/2) plus approach_pitch
	res.wrist_pitch = -(PI * 0.5) - (res.shoulder_pitch + res.elbow_pitch) + approach_pitch

	res.success = true
	return res
