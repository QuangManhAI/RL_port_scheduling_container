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

# Global metrics for normalization
const GLOBAL_SPAN_XZ: float = 20.0
const MAX_LINEAR_SPEED: float = 2.80
const MAX_ANGULAR_SPEED: float = 2.20

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

	# Reset Rack locations
	if rack_north:
		rack_north.global_position = Vector3(0.0, 0.02, -4.0)
		rack_north.rotation = Vector3(0.0, PI, 0.0) # Faces south (+Z)
	if rack_south:
		rack_south.global_position = Vector3(0.0, 0.02, 4.0)
		rack_south.rotation = Vector3.ZERO # Faces north (-Z)

	# Reset All Boxes
	for b in all_boxes:
		if is_instance_valid(b):
			b.reset_box()

	# Reset Conveyor
	if conveyor and conveyor.has_method("reset_conveyor"):
		conveyor.reset_conveyor()

	# Reset AMRs to staggered aisle starting positions
	var start_positions = [
		Vector3(-4.0, 0.02, -0.8),
		Vector3(-4.0, 0.02, 0.8)
	]

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

		if i < start_positions.size():
			a.global_position = start_positions[i]
			a.rotation = Vector3(0.0, 0.0 if i % 2 == 0 else PI, 0.0)

		a.velocity = Vector3.ZERO
		a._manual_linear_vel = 0.0
		a._manual_angular_vel = 0.0
		a._rl_target_v_lin = 0.0
		a._rl_target_v_ang = 0.0
		a.held_box = null
		a._clear_cargo_tray()
		a._fold_arm_to_home_instant()

		st.prev_subgoal_dist = a.global_position.distance_to(st.target_subgoal_pos)

func _get_box_target_world_pos(is_north: bool, box_idx: int) -> Vector3:
	var target_list = boxes_north if is_north else boxes_south
	if box_idx >= 0 and box_idx < target_list.size() and is_instance_valid(target_list[box_idx]):
		return target_list[box_idx].global_position
	# Fallback coordinate
	var z_sign = -1.0 if is_north else 1.0
	return Vector3(0.0, 0.56, z_sign * 3.4)

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
		a.set_rl_action(target_v, target_w)

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
				var dist = a.global_position.distance_to(st.target_subgoal_pos)
				if dist <= 2.2 and a.current_speed <= 0.60:
					# Dock at rack and pick box via Phase 07 skill
					st.sub_stage = FleetSubStage.DOCK_AND_PICK
					st.is_docked = true
					_execute_agent_pick(st)

			FleetSubStage.DOCK_AND_PICK:
				if a.held_box != null or a.arm_motion_state == a.ArmMotionState.HELD_READY:
					st.sub_stage = FleetSubStage.TRAY_STOW
					a.execute_dynamic_stow()

			FleetSubStage.TRAY_STOW:
				if a.get_stowed_box_count() > 0 and not a._is_arm_tweening:
					# Stowed! Retarget sub-goal to Conveyor dock
					st.sub_stage = FleetSubStage.NAVIGATE_TO_CONVEYOR
					st.is_docked = false
					st.target_subgoal_pos = _get_conveyor_dock_pos()
					st.prev_subgoal_dist = a.global_position.distance_to(st.target_subgoal_pos)

			FleetSubStage.NAVIGATE_TO_CONVEYOR:
				var dock_dist = a.global_position.distance_to(_get_conveyor_dock_pos())
				if dock_dist <= 1.85 and a.current_speed <= 0.50:
					# Arrived at Conveyor dock! Unstow and place
					st.sub_stage = FleetSubStage.CONVEYOR_PLACE
					st.is_docked = true
					var drop_pos = _get_conveyor_dock_pos()
					a.execute_dynamic_unstow_and_place(drop_pos)

			FleetSubStage.CONVEYOR_PLACE:
				if not a._is_arm_tweening and a.held_box == null and a.get_stowed_box_count() == 0:
					st.total_delivered += 1
					total_fleet_delivered += 1
					st.is_docked = false

					# Retask agent to pick another box
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
			"speed": st.amr.current_speed
		})

	return {
		"total_fleet_delivered": total_fleet_delivered,
		"global_state": _get_global_state(),
		"agent_info": per_agent_info,
		"num_amrs": amrs.size()
	}
