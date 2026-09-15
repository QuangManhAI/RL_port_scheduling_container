class_name ToteBox
extends RigidBody3D

## Dynamic Physical Tote Box for Autonomous Mobile Manipulator & Racking.
## Supports full 3D physics: gravity, momentum transfer, falling/spilling,
## and collision response with floor, AMRs, and other boxes.

@export var tier: int = 1
@export var slot_side: String = "L"
@export var sku_category: String = "FMCG"
@export var zone_name: String = "Zone A"

var home_shelf: ShelfPod = null
var slot_offset: Vector3 = Vector3.ZERO

var _initial_transform: Transform3D
var _is_spilled: bool = false
var _needs_reset: bool = false
var _material: Material = null

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D
@onready var col_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("tote_boxes")
	_initial_transform = global_transform
	# Docked by default: frozen in rack until spilled or grabbed
	freeze = true

func dock_to_shelf(shelf: ShelfPod, p_tier: int, p_side: String, p_offset: Vector3, mat: Material, p_zone: String, p_cat: String) -> void:
	home_shelf = shelf
	tier = p_tier
	slot_side = p_side
	slot_offset = p_offset
	_material = mat
	zone_name = p_zone
	sku_category = p_cat

	if mesh_inst and mat:
		mesh_inst.material_override = mat

	update_dock_transform()
	_initial_transform = global_transform
	freeze = true
	_is_spilled = false

func update_dock_transform() -> void:
	if home_shelf and not _is_spilled and freeze:
		global_transform = home_shelf.global_transform
		global_position = home_shelf.global_position + home_shelf.global_transform.basis * slot_offset

func spill_from_rack() -> void:
	if _is_spilled:
		return
	_is_spilled = true
	freeze = false

	# Impart realistic tumble impulse: outward from rack center + upward wobble + rack velocity
	if home_shelf:
		var outward: Vector3 = (global_position - home_shelf.global_position)
		outward.y = 0.0
		if outward.length_squared() > 0.01:
			outward = outward.normalized()
		else:
			outward = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()

		linear_velocity = home_shelf.linear_velocity * 0.75 + outward * randf_range(1.6, 3.8) + Vector3.UP * randf_range(0.8, 2.0)
		angular_velocity = Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-3.0, 3.0),
			randf_range(-5.0, 5.0)
		)

func reset_box() -> void:
	_is_spilled = false
	freeze = true
	_needs_reset = true
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _initial_transform)
	global_transform = _initial_transform

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _needs_reset:
		state.transform = _initial_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_needs_reset = false
