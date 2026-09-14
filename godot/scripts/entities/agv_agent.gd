class_name AgvEntity
extends Node3D

## AGV Entity transports containers along ground lanes.

@export var agv_id: int = 0
@export var speed: float = 14.0

@onready var deck_lock: Marker3D = $DeckLock
var carried_container: Node3D = null

func _ready() -> void:
	pass

func drive_to(target_pos: Vector3) -> Tween:
	var dist: float = global_position.distance_to(target_pos)
	var duration: float = max(0.4, dist / speed)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	
	# Look toward target if moving significantly
	var look_target: Vector3 = Vector3(target_pos.x, global_position.y, target_pos.z)
	if global_position.distance_squared_to(look_target) > 0.05:
		look_at(look_target, Vector3.UP)
	
	tween.tween_property(self, "global_position", target_pos, duration)
	return tween

func load_container(container_node: Node3D) -> void:
	carried_container = container_node
	container_node.get_parent().remove_child(container_node)
	deck_lock.add_child(container_node)
	container_node.position = Vector3.ZERO

func unload_container(new_parent: Node3D, target_pos: Vector3) -> void:
	if not carried_container:
		return
	var c: Node3D = carried_container
	carried_container = null
	deck_lock.remove_child(c)
	new_parent.add_child(c)
	c.global_position = target_pos
