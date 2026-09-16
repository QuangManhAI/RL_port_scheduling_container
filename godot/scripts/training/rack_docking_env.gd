class_name RackDockingEnv
extends TrainingEnvBase

## Stage R1: Gentle Rack Navigation & Docking Environment.
## Teaches the AMR to navigate from across the arena to dock square and stable
## in front of an assigned tier/slot on a physical 4-tier storage rack (ShelfPod).
## Implements a 2-stage physics curriculum (frozen until diff >= 0.70, then dynamic).

@export var arena_half_extent: float = 7.0

@onready var rack: ShelfPod = $ShelfPod
@onready var boxes_root: Node3D = $RackBoxes

const TOTE_SLOT_DEFS: Array[Dictionary] = [
	{"tier": 1, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 0.56, -0.60)},
	{"tier": 1, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 0.56, -0.60)},
	{"tier": 2, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 1.11, -0.60)},
	{"tier": 2, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 1.11, -0.60)},
	{"tier": 3, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 1.67, -0.60)},
	{"tier": 3, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 1.67, -0.60)},
	{"tier": 4, "side": "L", "side_val": -1.0, "offset": Vector3(-0.36, 2.23, -0.60)},
	{"tier": 4, "side": "R", "side_val": 1.0, "offset": Vector3(0.36, 2.23, -0.60)},
]

var boxes: Array[ToteBox] = []
var target_box_idx: int = 0
var target_tier: int = 1
var target_side_val: float = -1.0
var prev_sub_goal_dist: float = 0.0

var docking_success: bool = false
var rack_toppled: bool = false
var wall_collided: bool = false

var _mat_normal: StandardMaterial3D
var _mat_highlight: StandardMaterial3D

func _ready() -> void:
	max_episode_steps = 300
	_setup_materials()
	_init_boxes()
	super._ready()

func _setup_materials() -> void:
	_mat_normal = StandardMaterial3D.new()
	_mat_normal.albedo_color = Color(0.2, 0.65, 0.95, 1.0)
	_mat_normal.roughness = 0.4

	_mat_highlight = StandardMaterial3D.new()
	_mat_highlight.albedo_color = Color(1.0, 0.85, 0.1, 1.0)
	_mat_highlight.emission_enabled = true
	_mat_highlight.emission = Color(1.0, 0.75, 0.05, 1.0)
	_mat_highlight.emission_energy_multiplier = 2.0

func _init_boxes() -> void:
	if not boxes_root:
		return
	for child in boxes_root.get_children():
		if child is ToteBox:
			boxes.append(child)

func _on_arena_reset(seed_val: int, difficulty: float) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()

	docking_success = false
	rack_toppled = false
	wall_collided = false

	# 1. Reset Rack position and physics state
	if rack:
		rack.global_position = Vector3(0.0, 0.02, 0.0)
		rack.rotation = Vector3.ZERO
		rack.reset_rack()
		# Progressive Physics Curriculum:
		# Frozen until difficulty >= 0.70 to learn spatial approach first,
		# then full unconstrained RigidBody3D dynamics where impacts cause toppling.
		if difficulty < 0.70:
			rack.freeze = true
		else:
			rack.freeze = false

	# 2. Reset and dock all 8 boxes on rack
	for i in range(min(boxes.size(), TOTE_SLOT_DEFS.size())):
		var b = boxes[i]
		var s_def = TOTE_SLOT_DEFS[i]
		var world_box_pos = rack.global_position + s_def["offset"]
		b.visible = true
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.global_position = world_box_pos
		b.rotation = Vector3.ZERO
		if b.mesh_inst:
			b.mesh_inst.material_override = _mat_normal

	# 3. Uniformly select random target box (Tier 1-4, L/R)
	target_box_idx = rng.randi_range(0, min(boxes.size(), TOTE_SLOT_DEFS.size()) - 1)
	var active_slot = TOTE_SLOT_DEFS[target_box_idx]
	target_tier = active_slot["tier"]
	target_side_val = active_slot["side_val"]

	# Highlight active target box
	if target_box_idx < boxes.size():
		var target_box = boxes[target_box_idx]
		if target_box.mesh_inst:
			target_box.mesh_inst.material_override = _mat_highlight

	# 4. Spawn AMR at randomized perimeter position (distance 3.5m to 5.2m from rack)
	if amr:
		var spawn_angle = rng.randf_range(-PI, PI)
		var spawn_dist = rng.randf_range(3.5, 5.2)
		var spawn_x = clampf(cos(spawn_angle) * spawn_dist, -(arena_half_extent - 1.2), arena_half_extent - 1.2)
		var spawn_z = clampf(sin(spawn_angle) * spawn_dist, -(arena_half_extent - 1.2), arena_half_extent - 1.2)
		var spawn_yaw = rng.randf_range(-PI, PI)

		amr.reset_robot(Vector3(spawn_x, 0.0, spawn_z), spawn_yaw)
		amr.is_manual_control = false
		amr.is_rl_control = true

	prev_sub_goal_dist = _get_dist_to_target_box()

func _get_target_box_pos() -> Vector3:
	if target_box_idx < boxes.size() and boxes[target_box_idx]:
		return boxes[target_box_idx].global_position
	# Fallback to slot definition
	var s_def = TOTE_SLOT_DEFS[target_box_idx]
	return rack.global_position + s_def["offset"]

func _get_dist_to_target_box() -> float:
	if not amr:
		return 10.0
	var pos = _get_target_box_pos()
	var diff = amr.global_position - pos
	diff.y = 0.0 # Ground plane horizontal distance for chassis driving
	return diff.length()

func _get_rack_face_normal() -> Vector3:
	# Bay face points towards -Z in local rack coordinates
	if not rack:
		return Vector3.FORWARD
	return -rack.global_transform.basis.z

const GLOBAL_ARENA_HALF_EXTENT: float = 8.0
const GLOBAL_VECTOR_SPAN: float = 16.0

func _compute_observation() -> Array:
	var obs: Array = []
	if not amr:
		for i in range(16): obs.append(0.0)
		return obs

	# 0..3: Global arena pose normalized to 8m half-extent
	var norm_x = clampf(amr.global_position.x / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var norm_z = clampf(amr.global_position.z / GLOBAL_ARENA_HALF_EXTENT, -1.0, 1.0)
	var yaw = amr.rotation.y
	obs.append(norm_x)
	obs.append(norm_z)
	obs.append(sin(yaw))
	obs.append(cos(yaw))

	# 4..5: Normalized linear & angular velocity
	var norm_v = clampf(amr._manual_linear_vel / 2.8, -1.0, 1.0)
	var norm_w = clampf(amr._rl_target_v_ang / 2.2, -1.0, 1.0)
	obs.append(norm_v)
	obs.append(norm_w)

	# 6..8: Relative 3D vector to target box in robot local frame
	var box_pos = _get_target_box_pos()
	var local_rel = amr.global_transform.basis.inverse() * (box_pos - amr.global_position)
	var dist = amr.global_position.distance_to(box_pos)
	obs.append(clampf(local_rel.x / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(-local_rel.z / GLOBAL_VECTOR_SPAN, -1.0, 1.0))
	obs.append(clampf(dist / GLOBAL_VECTOR_SPAN, 0.0, 1.0))

	# 9..10: Carrying status (0.0 for docking) & Tray status (0.0)
	obs.append(0.0)
	obs.append(0.0)

	# 11..12: Nearest arena wall distance
	var dist_x = arena_half_extent - abs(amr.global_position.x)
	var dist_z = arena_half_extent - abs(amr.global_position.z)
	obs.append(clampf(minf(dist_x, dist_z) / GLOBAL_ARENA_HALF_EXTENT, 0.0, 1.0))
	obs.append(0.0)

	# 13: Target Tier (normalized: 0.25, 0.50, 0.75, 1.0)
	obs.append(float(target_tier) / 4.0)

	# 14: Target Slot Side (-1.0 for Left, +1.0 for Right)
	obs.append(target_side_val)

	# 15: Rack Face Alignment: dot product between robot forward and rack outward face normal
	# Robot forward is -basis.z. When robot is directly facing the rack bay opening, alignment is ~1.0
	var fwd = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	# Robot approaching from front of rack faces opposite the rack face normal
	var face_align = clampf(fwd.dot(-rack_face_norm), -1.0, 1.0)
	obs.append(face_align)

	return obs

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var to_box = (_get_target_box_pos() - amr.global_position).normalized()
	var align_to_box = forward.dot(to_box)

	# 180-degree symmetry breaker
	if align_to_box < -0.85 and cur_dist > 1.5 and abs(v_ang) < 0.15:
		v_ang = 0.8

	# Clamp reverse to small docking adjustment
	v_lin = clampf(v_lin, -0.15, 1.0)

	var lin_vel = v_lin * 2.8
	var ang_vel = v_ang * 2.2
	amr.set_rl_control(lin_vel, ang_vel)

func _compute_reward(_action: Array) -> float:
	var reward: float = 0.0
	if not amr or not rack:
		return reward

	var cur_dist = _get_dist_to_target_box()
	var forward = -amr.global_transform.basis.z
	var rack_face_norm = _get_rack_face_normal()
	var face_align = forward.dot(-rack_face_norm)

	# 1. Distance shaping reward
	var progress = prev_sub_goal_dist - cur_dist
	reward += progress * 3.0
	prev_sub_goal_dist = cur_dist

	# 2. Alignment bonus when approaching
	if cur_dist <= 3.0:
		reward += maxf(0.0, face_align) * 0.15

	# 3. Controlled speed near rack (< 1.8m): penalize high-speed ramming
	if cur_dist <= 1.8 and amr.current_speed > 0.40:
		reward -= 0.12 * (amr.current_speed - 0.40)

	# 4. Rack tilt & topple detection
	var up_alignment = rack.global_transform.basis.y.dot(Vector3.UP)
	if up_alignment < 0.96: # Tilted > ~16 degrees
		reward -= 0.50
	if up_alignment < 0.65 or rack.is_toppled: # Toppled (> ~49 degrees)
		rack_toppled = true
		reward -= 10.0

	# 5. Step penalty
	reward -= 0.01

	# 6. Kinematic Docking Completion Gate:
	# - Distance to target box <= 1.25m
	# - Robot facing rack face (face_align >= 0.85)
	# - Controlled docking crawl (speed <= 0.25 m/s)
	# - Rack untilted (up_alignment >= 0.996, < ~5 degrees)
	if cur_dist <= 1.25 and face_align >= 0.85 and amr.current_speed <= 0.25 and up_alignment >= 0.996:
		docking_success = true
		reward += 6.0 + face_align * 2.0

	# 7. Wall collision penalty
	var wall_limit = arena_half_extent - 0.40
	if abs(amr.global_position.x) >= wall_limit or abs(amr.global_position.z) >= wall_limit:
		wall_collided = true
		reward -= 2.0

	return reward

func _is_terminated() -> bool:
	return docking_success or rack_toppled or wall_collided

func _is_truncated() -> bool:
	return step_count >= max_episode_steps

func _get_info() -> Dictionary:
	return {
		"docking_success": docking_success,
		"rack_toppled": rack_toppled,
		"wall_collided": wall_collided,
		"target_tier": target_tier,
		"target_side": target_side_val,
		"dist_to_target": prev_sub_goal_dist,
		"dist_to_subgoal": prev_sub_goal_dist,
		"step_count": step_count,
	}
