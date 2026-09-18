class_name ToteBox
extends RigidBody3D

## Dynamic Physical Tote Box for Autonomous Mobile Manipulator & Racking.
## 100% Real Physical RigidBody3D at all times — rests directly on hollow rack shelf plates,
## slides naturally off tilting racks, tumbles under gravity, and responds to AMR impacts.

@export var tier: int = 1
@export var slot_side: String = "L"
@export var sku_category: String = "FMCG"
@export var zone_name: String = "Zone A"

var home_shelf: ShelfPod = null
var slot_offset: Vector3 = Vector3.ZERO

var _initial_transform: Transform3D
var _needs_reset: bool = false
var _material: Material = null

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D
@onready var col_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("tote_boxes")
	# Live physics: NEVER artificially frozen. Rests on physical shelf plates under gravity.
	freeze = false
	can_sleep = false

func dock_to_shelf(shelf: ShelfPod, p_tier: int, p_side: String, p_offset: Vector3, mat: Material, p_zone: String, p_cat: String, p_initial_world_pos: Vector3 = Vector3.ZERO) -> void:
	home_shelf = shelf
	tier = p_tier
	slot_side = p_side
	slot_offset = p_offset
	_material = mat
	zone_name = p_zone
	sku_category = p_cat

	if mesh_inst and mat:
		mesh_inst.material_override = mat

	if p_initial_world_pos != Vector3.ZERO:
		_initial_transform = Transform3D(Basis.IDENTITY, p_initial_world_pos)
		global_transform = _initial_transform
	else:
		_initial_transform = global_transform

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false

func reset_box() -> void:
	visible = true
	_needs_reset = true
	freeze = false
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
