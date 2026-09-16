class_name DifficultyRamp
extends RefCounted

## Manages continuous curriculum difficulty progression from 0.0 to 1.0.

static func get_min_box_distance(difficulty: float, base_dist: float = 2.0, max_dist: float = 6.0) -> float:
	return lerpf(base_dist, max_dist, clampf(difficulty, 0.0, 1.0))

static func get_obstacle_count(difficulty: float, max_obstacles: int = 3) -> int:
	return int(round(clampf(difficulty, 0.0, 1.0) * max_obstacles))
