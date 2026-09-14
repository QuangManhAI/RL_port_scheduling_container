class_name QuayCraneEntity
extends Node3D

## Quay Crane (STS) handles ship loading/unloading with 3-axis motion.

@export var crane_id: int = 0
@export var gantry_speed: float = 8.0
@export var trolley_speed: float = 12.0
@export var hoist_speed: float = 6.0

@onready var trolley: Node3D = $Gantry/Boom/Trolley
@onready var spreader: Node3D = $Gantry/Boom/Trolley/Spreader
@onready var lock_point: Marker3D = $Gantry/Boom/Trolley/Spreader/LockPoint

var held_container: Node3D = null

func _ready() -> void:
	pass

func move_gantry_to(target_x: float) -> Tween:
	var dist: float = abs(target_x - position.x)
	var duration: float = max(0.4, dist / gantry_speed)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:x", target_x, duration)
	return tween

func move_trolley_to(target_z: float) -> Tween:
	if not trolley:
		return null
	var dist: float = abs(target_z - trolley.position.z)
	var duration: float = max(0.4, dist / trolley_speed)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(trolley, "position:z", target_z, duration)
	return tween

func hoist_spreader_to(target_y: float) -> Tween:
	if not spreader:
		return null
	var dist: float = abs(target_y - spreader.position.y)
	var duration: float = max(0.4, dist / hoist_speed)
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(spreader, "position:y", target_y, duration)
	return tween

func grab_container(container_node: Node3D) -> void:
	if not container_node or not lock_point:
		return
	held_container = container_node
	var current_global_pos: Vector3 = container_node.global_position
	container_node.get_parent().remove_child(container_node)
	lock_point.add_child(container_node)
	container_node.position = Vector3.ZERO

func release_container(new_parent: Node3D, target_global_pos: Vector3) -> void:
	if not held_container:
		return
	var c: Node3D = held_container
	held_container = null
	lock_point.remove_child(c)
	new_parent.add_child(c)
	c.global_position = target_global_pos
