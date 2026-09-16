class_name SpawnRandomizer
extends RefCounted

## Utility for deterministic procedural spawn randomization across training stages.

static func spawn_agent(agent: AmrRobot, arena_half_extent: float, rng: RandomNumberGenerator) -> void:
	if not agent:
		return
	var margin: float = 1.5
	var max_r = maxf(0.5, arena_half_extent - margin)
	var x = rng.randf_range(-max_r, max_r)
	var z = rng.randf_range(-max_r, max_r)
	var heading = rng.randf_range(-PI, PI)

	agent.global_position = Vector3(x, 0.0, z)
	agent.rotation = Vector3(0.0, heading, 0.0)
	agent.velocity = Vector3.ZERO
	agent.set_rl_control(0.0, 0.0)

static func spawn_target_box(box: ToteBox, agent: AmrRobot, arena_half_extent: float, min_dist: float, rng: RandomNumberGenerator) -> void:
	if not box or not agent:
		return
	var margin: float = 1.0
	var max_r = maxf(0.5, arena_half_extent - margin)
	var found = false
	var pos = Vector3.ZERO

	for attempt in range(50):
		var x = rng.randf_range(-max_r, max_r)
		var z = rng.randf_range(-max_r, max_r)
		pos = Vector3(x, 0.15, z)
		if pos.distance_to(agent.global_position) >= min_dist:
			found = true
			break

	if not found:
		var fwd = -agent.global_transform.basis.z
		pos = agent.global_position + fwd * min_dist
		pos.y = 0.15

	box.freeze = true
	box.global_position = pos
	box.rotation = Vector3(0.0, rng.randf_range(-PI, PI), 0.0)
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.visible = true

static func spawn_drop_zone(marker: Node3D, agent: AmrRobot, arena_half_extent: float, min_dist: float, rng: RandomNumberGenerator) -> void:
	if not marker or not agent:
		return
	var margin: float = 1.5
	var max_r = maxf(0.5, arena_half_extent - margin)
	for attempt in range(50):
		var x = rng.randf_range(-max_r, max_r)
		var z = rng.randf_range(-max_r, max_r)
		var pos = Vector3(x, 0.02, z)
		if pos.distance_to(agent.global_position) >= min_dist:
			marker.global_position = pos
			marker.rotation = Vector3(0.0, rng.randf_range(-PI, PI), 0.0)
			return
	marker.global_position = agent.global_position + Vector3(min_dist, 0.02, 0.0)
