class_name ShelfPod
extends Node3D

## Mobile Storage Shelf Pod designed for under-chassis AMR lifting.

@export var pod_id: int = 1
@export var is_lifted: bool = false

@onready var frame_mesh: MeshInstance3D = $PodFrame
var _material: StandardMaterial3D

func _ready() -> void:
	if frame_mesh and frame_mesh.get_surface_override_material(0):
		_material = frame_mesh.get_surface_override_material(0).duplicate()
		frame_mesh.set_surface_override_material(0, _material)

func setup(p_id: int) -> void:
	pod_id = p_id

func lift_by_amr(amr_turntable: Node3D) -> Tween:
	is_lifted = true
	var current_global_pos: Vector3 = global_position
	get_parent().remove_child(self)
	amr_turntable.add_child(self)
	global_position = current_global_pos
	
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", Vector3(0.0, 0.15, 0.0), 0.5)
	return tween

func drop_to_floor(new_parent: Node3D, floor_pos: Vector3) -> Tween:
	is_lifted = false
	var current_global_pos: Vector3 = global_position
	get_parent().remove_child(self)
	new_parent.add_child(self)
	global_position = current_global_pos

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", floor_pos, 0.5)
	return tween

func highlight(active: bool) -> void:
	if not _material:
		return
	if active:
		_material.emission_enabled = true
		_material.emission = Color(0.2, 0.8, 1.0)
		_material.emission_energy_multiplier = 1.0
	else:
		_material.emission_enabled = false
