class_name FleetAisleEnv
extends TrainingEnvBase

## Multi-Agent Warehouse Coordination Environment (Phase 08 - Fleet MAPPO).
## Coordinates multiple Phase 07 AMRs operating between dual 4-tier racks and a motorized conveyor dock.
## Generates fixed 37-D ego-centric observations (Ego + k-NN + 16-ray LiDAR) for zero-shot fleet scalability.

@export var arena_half_x: float = 10.0
@export var arena_half_z: float = 8.0
@export var neighbor_sensing_radius: float = 6.0
@export var lidar_max_range: float = 6.0
@export var k_neighbors: int = 2

# Scene Nodes
@onready var amr_1: AmrRobot = get_node_or_null("AMR_1")
@onready var amr_2: AmrRobot = get_node_or_null("AMR_2")
@onready var rack_north: ShelfPod = get_node_or_null("RackNorth")
@onready var rack_south: ShelfPod = get_node_or_null("RackSouth")
@onready var conveyor: StaticBody3D = get_node_or_null("ConveyorTable")
@onready var drop_marker: Marker3D = get_node_or_null("ConveyorTable/DropTargetMarker")
@onready var boxes_north_root: Node3D = get_node_or_null("RackNorthBoxes")
@onready var boxes_south_root: Node3D = get_node_or_null("RackSouthBoxes")

var amrs: Array[AmrRobot] = []
var boxes_north: Array[ToteBox] = []
var boxes_south: Array[ToteBox] = []
var all_boxes: Array[ToteBox] = []

# Sub-stage enum aligned with Stage R4
enum FleetSubStage {
	NAVIGATE_TO_RACK = 0,
	DOCK_AND_PICK = 1,
	TRAY_STOW = 2,
	NAVIGATE_TO_CONVEYOR = 3,
	CONVEYOR_PLACE = 4,
	IDLE_WAIT = 5
}

# Per-agent coordination state
class AgentState:
	var amr: AmrRobot
	var sub_stage: int = FleetSubStage.NAVIGATE_TO_RACK
	var assigned_box_idx: int = -1
	var assigned_rack_is_north: bool = true
	var target_subgoal_pos: Vector3 = Vector3.ZERO
	var prev_subgoal_dist: float = 0.0
	var total_delivered: int = 0
	var is_docked: bool = false
	var near_miss_count: int = 0

var agent_states: Array[AgentState] = []
var total_fleet_delivered: int = 0
var fleet_deadlock_timer: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

const GLOBAL_SPAN_XZ: float = 20.0
const MAX_LINEAR_SPEED: float = 2.80
const MAX_ANGULAR_SPEED: float = 2.20

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

func _ready() -> void:
	max_episode_steps = 1200
	_init_fleet_nodes()
	super._ready()

func _init_fleet_nodes() -> void:
	amrs.clear()
	agent_states.clear()
	if amr_1: amrs.append(amr_1)
	if amr_2: amrs.append(amr_2)
	amr = amr_1 # Base class reference

	for a in amrs:
		var st = AgentState.new()
		st.amr = a
		agent_states.append(st)

	_init_boxes()

func _init_boxes() -> void:
	boxes_north.clear()
	boxes_south.clear()
	all_boxes.clear()

	if boxes_north_root:
		for c in boxes_north_root.get_children():
			if c is ToteBox:
				boxes_north.append(c)
				all_boxes.append(c)

	if boxes_south_root:
		for c in boxes_south_root.get_children():
			if c is ToteBox:
				boxes_south.append(c)
				all_boxes.append(c)

func _on_arena_reset(seed_val: int, _difficulty: float) -> void:
	rng.seed = seed_val if seed_val != 0 else Time.get_ticks_usec()
	step_count = 0
	total_fleet_delivered = 0
	fleet_deadlock_timer = 0.0

	# 1. Randomize Rack locations within realistic operational bounds
	var rack_north_x = rng.randf_range(-1.2, 1.2)
	var rack_north_z = rng.randf_range(-4.2, -3.6)
	var rack_south_x = rng.randf_range(-1.2, 1.2)
	var rack_south_z = rng.randf_range(3.6, 4.2)

	if rack_north:
		rack_north.global_position = Vector3(rack_north_x, 0.02, rack_north_z)
		rack_north.rotation = Vector3(0.0, PI, 0.0) # Faces south (+Z)
	if rack_south:
		rack_south.global_position = Vector3(rack_south_x, 0.02, rack_south_z)
		rack_south.rotation = Vector3.ZERO # Faces north (-Z)

	# Reset North Rack Boxes onto physical shelves relative to randomized rack position
	for i in range(min(boxes_north.size(), TOTE_SLOT_DEFS.size())):
		var b = boxes_north[i]
		var s_def = TOTE_SLOT_DEFS[i]
		var world_pos = rack_north.to_global(s_def["offset"]) if rack_north else (Vector3(rack_north_x, 0.0, rack_north_z) + s_def["offset"])
		b.visible = true
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		if b.get_parent() != boxes_north_root:
			b.get_parent().remove_child(b)
			boxes_north_root.add_child(b)
		b.global_position = world_pos
		b.global_rotation = rack_north.global_rotation if rack_north else Vector3(0.0, PI, 0.0)

	# Reset South Rack Boxes onto physical shelves relative to randomized rack position
	for i in range(min(boxes_south.size(), TOTE_SLOT_DEFS.size())):
		var b = boxes_south[i]
		var s_def = TOTE_SLOT_DEFS[i]
		var world_pos = rack_south.to_global(s_def["offset"]) if rack_south else (Vector3(rack_south_x, 0.0, rack_south_z) + s_def["offset"])
		b.visible = true
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		if b.get_parent() != boxes_south_root:
			b.get_parent().remove_child(b)
			boxes_south_root.add_child(b)
		b.global_position = world_pos
		b.global_rotation = rack_south.global_rotation if rack_south else Vector3.ZERO

	# 2. Randomize Conveyor dock position
	var conv_x = rng.randf_range(5.0, 5.6)
	var conv_z = rng.randf_range(-0.6, 0.6)
	if conveyor:
		conveyor.global_position = Vector3(conv_x, 0.0, conv_z)
		conveyor.rotation = Vector3(0.0, PI / 2.0, 0.0) # Faces West (-X) into the central aisle
		if conveyor.has_method("reset_conveyor"):
			conveyor.reset_conveyor()

	# 3. Randomize AMR aisle starting positions & orientations with guaranteed minimum 1.4m clearance
	var p1_x = rng.randf_range(-5.8, -4.2)
	var p1_z = rng.randf_range(-0.9, -0.2)
	var p1_yaw = -PI / 2.0 + rng.randf_range(-0.25, 0.25)

	var p2_x = rng.randf_range(-6.8, -5.2)
	var p2_z = rng.randf_range(0.2, 0.9)
	var p2_yaw = -PI / 2.0 + rng.randf_range(-0.25, 0.25)

	if Vector2(p1_x - p2_x, p1_z - p2_z).length() < 1.4:
		p2_x = p1_x - 1.5

	var start_positions = [
		Vector3(p1_x, 0.02, p1_z),
		Vector3(p2_x, 0.02, p2_z)
	]
	var start_yaws = [p1_yaw, p2_yaw]

	for i in range(amrs.size()):
		var a = amrs[i]
		var st = agent_states[i]
		st.sub_stage = FleetSubStage.NAVIGATE_TO_RACK
		st.total_delivered = 0
		st.near_miss_count = 0
		st.is_docked = false

		# Initial box assignments (Agent 1 targets North Rack, Agent 2 targets South Rack)
		st.assigned_rack_is_north = (i % 2 == 0)
		st.assigned_box_idx = (i * 2) % 8
		st.target_subgoal_pos = _get_box_target_world_pos(st.assigned_rack_is_north, st.assigned_box_idx)
		print("[FleetAisleEnv] Reset Agent %d: north=%s box_idx=%d target=%s" % [i, str(st.assigned_rack_is_north), st.assigned_box_idx, str(st.target_subgoal_pos)])

		if i < start_positions.size():
			a.reset_robot(start_positions[i], start_yaws[i])

		a.arm_tween_speed_scale = 3.5
		a.held_box = null
		a._fold_arm_to_home_instant()

		st.prev_subgoal_dist = a.global_position.distance_to(st.target_subgoal_pos)

func _get_box_target_world_pos(is_north: bool, box_idx: int) -> Vector3:
	var target_rack = rack_north if is_north else rack_south
	var slot_idx = clampi(box_idx, 0, TOTE_SLOT_DEFS.size() - 1)
	var s_def = TOTE_SLOT_DEFS[slot_idx]
	var res = Vector3.ZERO
	if target_rack:
		res = target_rack.to_global(s_def["offset"])
	else:
		var z_sign = -1.0 if is_north else 1.0
		res = Vector3(0.0, 0.02, z_sign * 4.0) + s_def["offset"]
	return res

func _get_conveyor_dock_pos() -> Vector3:
	if drop_marker:
		return drop_marker.global_position
	elif conveyor:
		return conveyor.to_global(Vector3(0.0, 0.77, -0.05))
	return Vector3(5.5, 0.77, 0.0)

## Apply Multi-Agent Joint Actions [ [v1, w1], [v2, w2], ... ] or flattened array
func _apply_action(action: Array) -> void:
	for i in range(amrs.size()):
		var a = amrs[i]
		var v_lin: float = 0.0
		var v_ang: float = 0.0

		if action.size() > i and action[i] is Array:
			var act_i: Array = action[i]
			v_lin = clampf(float(act_i[0]), -1.0, 1.0)
			v_ang = clampf(float(act_i[1]), -1.0, 1.0)
		elif action.size() >= (i + 1) * 2:
			v_lin = clampf(float(action[i * 2]), -1.0, 1.0)
			v_ang = clampf(float(action[i * 2 + 1]), -1.0, 1.0)

		# Scale continuous actions to physical kinematic limits
		var target_v = v_lin * MAX_LINEAR_SPEED
		var target_w = v_ang * MAX_ANGULAR_SPEED
		a.set_rl_control(target_v, target_w)

## Compute Decentralized 37-D Observations for all AMRs
func _compute_observation() -> Array:
	var fleet_obs: Array = []
	for i in range(amrs.size()):
		var obs_i = _build_agent_obs(i)
		fleet_obs.append(obs_i)
	return fleet_obs

func _build_agent_obs(agent_idx: int) -> Array:
	var a = amrs[agent_idx]
	var st = agent_states[agent_idx]
	var obs: Array = []

	# 1. Own State (11 Dimensions)
	obs.append(clampf(a.global_position.x / arena_half_x, -1.0, 1.0))
	obs.append(clampf(a.global_position.z / arena_half_z, -1.0, 1.0))
	obs.append(sin(a.rotation.y))
	obs.append(cos(a.rotation.y))
	obs.append(clampf(a._manual_linear_vel / MAX_LINEAR_SPEED, -1.0, 1.0))
	obs.append(clampf(a._manual_angular_vel / MAX_ANGULAR_SPEED, -1.0, 1.0))

	# Relative vector to active sub-goal
	var to_goal = st.target_subgoal_pos - a.global_position
	var local_dx = a.to_local(st.target_subgoal_pos).x
	var local_dz = a.to_local(st.target_subgoal_pos).z
	obs.append(clampf(local_dx / GLOBAL_SPAN_XZ, -1.0, 1.0))
	obs.append(clampf(local_dz / GLOBAL_SPAN_XZ, -1.0, 1.0))
	obs.append(float(a.get_stowed_box_count()) / 2.0)
	obs.append(float(st.sub_stage) / 5.0)

	# Sub-goal face alignment
	var forward_dir = -a.global_transform.basis.z
	var to_goal_norm = to_goal.normalized()
	obs.append(clampf(forward_dir.dot(to_goal_norm), -1.0, 1.0))

	# 2. k-Nearest Neighbors (k=2 -> 10 Dimensions: 5 features per neighbor)
	var neighbors = _get_k_nearest_neighbors(agent_idx, k_neighbors)
	for n_data in neighbors:
		obs.append(n_data["rel_dx"])
		obs.append(n_data["rel_dz"])
		obs.append(n_data["rel_dvx"])
		obs.append(n_data["rel_dvz"])
		obs.append(n_data["carrying_flag"])

	# 3. 360-Degree LiDAR Raycasts (16 Rays -> 16 Dimensions)
	var lidar_rays = _sample_360_lidar(a)
	for r_dist in lidar_rays:
		obs.append(r_dist)

	return obs

func _get_k_nearest_neighbors(ego_idx: int, k: int) -> Array:
	var ego = amrs[ego_idx]
	var neighbor_candidates: Array = []

	for j in range(amrs.size()):
		if j == ego_idx:
			continue
		var other = amrs[j]
		var dist = ego.global_position.distance_to(other.global_position)
		if dist <= neighbor_sensing_radius:
			neighbor_candidates.append({
				"amr": other,
				"dist": dist
			})

	# Sort by distance
	neighbor_candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	var result: Array = []
	for i in range(k):
		if i < neighbor_candidates.size():
			var other: AmrRobot = neighbor_candidates[i]["amr"]
			var rel_pos = other.global_position - ego.global_position
			var rel_vel_lin = other._manual_linear_vel - ego._manual_linear_vel
			var rel_vel_ang = other._manual_angular_vel - ego._manual_angular_vel

			result.append({
				"rel_dx": clampf(rel_pos.x / neighbor_sensing_radius, -1.0, 1.0),
				"rel_dz": clampf(rel_pos.z / neighbor_sensing_radius, -1.0, 1.0),
				"rel_dvx": clampf(rel_vel_lin / (MAX_LINEAR_SPEED * 2.0), -1.0, 1.0),
				"rel_dvz": clampf(rel_vel_ang / (MAX_ANGULAR_SPEED * 2.0), -1.0, 1.0),
				"carrying_flag": 1.0 if other.get_stowed_box_count() > 0 else 0.0
			})
		else:
			# Zero padding when fewer than k neighbors exist
			result.append({
				"rel_dx": 0.0,
				"rel_dz": 0.0,
				"rel_dvx": 0.0,
				"rel_dvz": 0.0,
				"carrying_flag": 0.0
			})

	return result

func _sample_360_lidar(ego: AmrRobot) -> Array:
	var rays: Array = []
	var num_rays: int = 16
	var angle_step: float = (2.0 * PI) / float(num_rays)
	var ego_pos: Vector3 = ego.global_position + Vector3(0.0, 0.25, 0.0) # Chassis height
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	if not space_state:
		for i in range(num_rays):
			rays.append(1.0)
		return rays

	var ego_heading = ego.rotation.y

	for i in range(num_rays):
		var theta = ego_heading + (float(i) * angle_step)
		var ray_dir = Vector3(-sin(theta), 0.0, -cos(theta)).normalized()
		var ray_end = ego_pos + (ray_dir * lidar_max_range)

		var query = PhysicsRayQueryParameters3D.create(ego_pos, ray_end)
		query.collision_mask = 3 # Static arena walls, racks, conveyor deck (ignore robots layer 4)
		query.exclude = [ego.get_rid()]

		var hit = space_state.intersect_ray(query)
		if hit and not hit.is_empty():
			var hit_dist = ego_pos.distance_to(hit.position)
			rays.append(clampf(hit_dist / lidar_max_range, 0.0, 1.0))
		else:
			rays.append(1.0)

	return rays

## Compute Centralized Critic Global State (Full Warehouse State)
func _get_global_state() -> Array:
	var g_state: Array = []
	for st in agent_states:
		var a = st.amr
		g_state.append(a.global_position.x / arena_half_x)
		g_state.append(a.global_position.z / arena_half_z)
		g_state.append(a._manual_linear_vel / MAX_LINEAR_SPEED)
		g_state.append(a._manual_angular_vel / MAX_ANGULAR_SPEED)
		g_state.append(float(a.get_stowed_box_count()))
		g_state.append(float(st.sub_stage))

	# Conveyor delivery count
	g_state.append(float(total_fleet_delivered))
	return g_state

## Multi-Agent Reward Calculation
func _compute_reward(_action: Array) -> float:
	var total_team_reward: float = 0.0

	for i in range(agent_states.size()):
		var st = agent_states[i]
		var a = st.amr
		var r_i: float = 0.0

		# 1. Potential-based progress toward sub-goal
		var cur_dist = a.global_position.distance_to(st.target_subgoal_pos)
		var dist_delta = st.prev_subgoal_dist - cur_dist
		st.prev_subgoal_dist = cur_dist
		r_i += dist_delta * 2.5

		# 2. Inter-agent near-miss penalty (soft safety shaping)
		for j in range(agent_states.size()):
			if i == j:
				continue
			var other = agent_states[j].amr
			var inter_dist = a.global_position.distance_to(other.global_position)
			if inter_dist < 1.40:
				st.near_miss_count += 1
				r_i -= 0.15 * (1.40 - inter_dist)

		# 3. Anti-deadlock / stall penalty
		if a.current_speed < 0.05 and not st.is_docked:
			r_i -= 0.02
		else:
			r_i -= 0.005 # Small time penalty

		# 4. Conveyor dock queuing reward
		if st.sub_stage == FleetSubStage.NAVIGATE_TO_CONVEYOR:
			var dock_dist = a.global_position.distance_to(_get_conveyor_dock_pos())
			if dock_dist < 3.0:
				r_i += 0.05

		total_team_reward += r_i

	return total_team_reward / float(max(1, agent_states.size()))

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	# Drive all AMRs
	for a in amrs:
		a._process_rl_driving(delta)

	# Manage sub-stage transitions and Phase 07 skill triggers
	_update_fleet_state_machine()

func _update_fleet_state_machine() -> void:
	for i in range(agent_states.size()):
		var st = agent_states[i]
		var a = st.amr

		match st.sub_stage:
			FleetSubStage.NAVIGATE_TO_RACK:
				var horiz_dist = Vector2(a.global_position.x - st.target_subgoal_pos.x, a.global_position.z - st.target_subgoal_pos.z).length()
				var shoulder_dist = a.shoulder.global_position.distance_to(st.target_subgoal_pos) if a.shoulder else horiz_dist
				if (horiz_dist <= 2.25 or shoulder_dist <= 2.15) and a.current_speed <= 0.65:
					# Dock at rack and pick box via Phase 07 skill
					st.sub_stage = FleetSubStage.DOCK_AND_PICK
					st.is_docked = true
					_execute_agent_pick(st)

			FleetSubStage.DOCK_AND_PICK:
				if a.held_box != null or a.arm_motion_state == a.ArmMotionState.HELD_READY:
					st.sub_stage = FleetSubStage.TRAY_STOW
					a.execute_dynamic_stow()
				elif not a._is_arm_tweening and a.held_box == null:
					_execute_agent_pick(st)

			FleetSubStage.TRAY_STOW:
				if a.get_stowed_box_count() > 0 and not a._is_arm_tweening:
					# Stowed! Retarget sub-goal to Conveyor dock
					st.sub_stage = FleetSubStage.NAVIGATE_TO_CONVEYOR
					st.is_docked = false
					st.target_subgoal_pos = _get_conveyor_dock_pos()
					st.prev_subgoal_dist = a.global_position.distance_to(st.target_subgoal_pos)

			FleetSubStage.NAVIGATE_TO_CONVEYOR:
				var drop_pos = _get_conveyor_dock_pos()
				var horiz_dock_dist = Vector2(a.global_position.x - drop_pos.x, a.global_position.z - drop_pos.z).length()
				if horiz_dock_dist <= 2.30 and a.current_speed <= 0.65:
					# Check if another AMR is actively placing to avoid simultaneous collision
					var dock_busy: bool = false
					for j in range(agent_states.size()):
						if j != i and agent_states[j].sub_stage == FleetSubStage.CONVEYOR_PLACE:
							dock_busy = true
							break
					if not dock_busy:
						st.sub_stage = FleetSubStage.CONVEYOR_PLACE
						st.is_docked = true
						a.execute_dynamic_unstow_and_place(drop_pos)

			FleetSubStage.CONVEYOR_PLACE:
				if not a._is_arm_tweening and a.held_box == null and a.get_stowed_box_count() == 0:
					st.total_delivered += 1
					total_fleet_delivered += 1
					st.is_docked = false

					# Retask agent to pick next available box
					st.sub_stage = FleetSubStage.NAVIGATE_TO_RACK
					st.assigned_box_idx = (st.assigned_box_idx + 2) % 8
					st.target_subgoal_pos = _get_box_target_world_pos(st.assigned_rack_is_north, st.assigned_box_idx)
					st.prev_subgoal_dist = a.global_position.distance_to(st.target_subgoal_pos)

func _execute_agent_pick(st: AgentState) -> void:
	var target_list = boxes_north if st.assigned_rack_is_north else boxes_south
	if st.assigned_box_idx >= 0 and st.assigned_box_idx < target_list.size():
		var target_box = target_list[st.assigned_box_idx]
		if is_instance_valid(target_box):
			st.amr.active_target_box = target_box
			st.amr._handle_pick_command()

func _is_terminated() -> bool:
	return total_fleet_delivered >= 6 # Episode terminates once 6 boxes are delivered

func _is_truncated() -> bool:
	return step_count >= max_episode_steps

func _get_info() -> Dictionary:
	var per_agent_info: Array = []
	for i in range(agent_states.size()):
		var st = agent_states[i]
		per_agent_info.append({
			"agent_id": i,
			"sub_stage": st.sub_stage,
			"delivered": st.total_delivered,
			"near_misses": st.near_miss_count,
			"speed": st.amr.current_speed,
			"pos": [st.amr.global_position.x, st.amr.global_position.y, st.amr.global_position.z],
			"yaw": st.amr.rotation.y,
			"target": [st.target_subgoal_pos.x, st.target_subgoal_pos.y, st.target_subgoal_pos.z]
		})

	return {
		"total_fleet_delivered": total_fleet_delivered,
		"global_state": _get_global_state(),
		"agent_info": per_agent_info,
		"num_amrs": amrs.size(),
		"env_positions": {
			"rack_north": [rack_north.global_position.x, rack_north.global_position.y, rack_north.global_position.z] if rack_north else [],
			"rack_south": [rack_south.global_position.x, rack_south.global_position.y, rack_south.global_position.z] if rack_south else [],
			"conveyor": [conveyor.global_position.x, conveyor.global_position.y, conveyor.global_position.z] if conveyor else [],
			"conveyor_dock": [_get_conveyor_dock_pos().x, _get_conveyor_dock_pos().y, _get_conveyor_dock_pos().z]
		}
	}
