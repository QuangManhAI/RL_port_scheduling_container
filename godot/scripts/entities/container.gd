class_name ContainerEntity
extends Node3D

## Container Entity represents an ISO shipping container in 3D space.

enum ContainerType {
	IMPORT = 0,
	EXPORT = 1,
	TRANSSHIPMENT = 2
}

const COLOR_IMPORT: Color = Color(0.0, 0.467, 0.714)       # Marine Blue
const COLOR_EXPORT: Color = Color(0.165, 0.616, 0.561)     # Emerald Green
const COLOR_TRANS: Color = Color(0.957, 0.635, 0.380)      # Sunset Amber
const COLOR_HIGHLIGHT: Color = Color(1.0, 0.84, 0.0)       # Golden Yellow

@export var container_id: int = -1
@export var container_type: ContainerType = ContainerType.IMPORT

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _material: StandardMaterial3D

func _ready() -> void:
	_init_material()
	update_appearance()

func _init_material() -> void:
	if mesh_instance and mesh_instance.get_surface_override_material(0) == null:
		_material = StandardMaterial3D.new()
		_material.roughness = 0.45
		_material.metallic = 0.15
		mesh_instance.set_surface_override_material(0, _material)
	elif mesh_instance:
		_material = mesh_instance.get_surface_override_material(0).duplicate()
		mesh_instance.set_surface_override_material(0, _material)

func setup(p_id: int, p_type: int) -> void:
	container_id = p_id
	container_type = p_type as ContainerType
	update_appearance()

func update_appearance() -> void:
	if not _material:
		_init_material()
	if not _material:
		return

	var base_color: Color
	match container_type:
		ContainerType.IMPORT:
			base_color = COLOR_IMPORT
		ContainerType.EXPORT:
			base_color = COLOR_EXPORT
		ContainerType.TRANSSHIPMENT:
			base_color = COLOR_TRANS
		_:
			base_color = Color.GRAY

	_material.albedo_color = base_color

func highlight(active: bool) -> void:
	if not _material:
		return
	if active:
		_material.emission_enabled = true
		_material.emission = COLOR_HIGHLIGHT
		_material.emission_energy_multiplier = 0.8
	else:
		_material.emission_enabled = false

func animate_to_position(target_global_pos: Vector3, duration: float = 0.8) -> Tween:
	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", target_global_pos, duration)
	return tween
