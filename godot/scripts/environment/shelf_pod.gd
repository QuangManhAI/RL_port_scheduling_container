class_name ShelfPod
extends RigidBody3D

## Mobile Multi-Tier Stackable Storage Pod.
## Stores categorized SKU goods across 4 vertical tiers (Tier 1 to Tier 4).
## Built with hollow physical bays & shelf plates. Boxes rest physically on shelves.

@export var pod_id: int = 1
@export var zone_name: String = "Zone A"
@export var sku_category: String = "FMCG"
@export var is_lifted: bool = false
@export var is_toppled: bool = false

var _initial_pos: Vector3 = Vector3.ZERO
var _initial_basis: Basis = Basis.IDENTITY
var _needs_reset: bool = false
var _zone_color: Color = Color.WHITE

@onready var label_3d: Label3D = $PodLabel
@onready var label_t1: Label3D = $LabelTier1
@onready var label_t2: Label3D = $LabelTier2
@onready var label_t3: Label3D = $LabelTier3
@onready var label_t4: Label3D = $LabelTier4

var _docked_boxes: Array[ToteBox] = []

func _ready() -> void:
	add_to_group("shelf_pods")
	if _initial_pos == Vector3.ZERO:
		_initial_pos = global_position
		_initial_basis = global_transform.basis

func _physics_process(_delta: float) -> void:
	if not is_lifted and not is_toppled:
		var up_alignment: float = global_transform.basis.y.dot(Vector3.UP)
		# Tilted past tipping point (~49 degrees): rack is toppled
		if up_alignment < 0.65:
			is_toppled = true
			SoundManager.play_spatial(self, SoundManager.sfx_brake, 2.0, 0.65)
			if label_3d:
				label_3d.text = "[%s]\n⚠️ RACK TOPPLED!\nSKU-%s-#%02d" % [zone_name, sku_category, pod_id]
				label_3d.modulate = Color(1.0, 0.2, 0.2, 1.0)

func register_tote(box: ToteBox) -> void:
	if not _docked_boxes.has(box):
		_docked_boxes.append(box)

func pick_tote(tier: int, check_pos: Vector3) -> Dictionary:
	var best_box: ToteBox = null
	var min_dist: float = 3.5

	for box in _docked_boxes:
		if is_instance_valid(box) and box.visible and box.tier == tier:
			var d: float = box.global_position.distance_to(check_pos)
			if d < min_dist:
				min_dist = d
				best_box = box

	if best_box:
		best_box.visible = false
		return {
			"found": true,
			"material": best_box._material,
			"tier": tier,
			"sku_zone": zone_name,
			"box_node": best_box
		}

	return {"found": false}

func setup(p_id: int, p_zone: String = "Zone A", p_cat: String = "FMCG", zone_col: Color = Color(0.0, 0.8, 1.0), p_pos: Vector3 = Vector3.ZERO) -> void:
	pod_id = p_id
	zone_name = p_zone
	sku_category = p_cat
	_zone_color = zone_col

	if p_pos != Vector3.ZERO:
		_initial_pos = p_pos
		_initial_basis = Basis.IDENTITY
		global_position = p_pos
		global_transform = Transform3D(Basis.IDENTITY, p_pos)
	elif _initial_pos == Vector3.ZERO:
		_initial_pos = global_position
		_initial_basis = global_transform.basis

	if label_3d:
		label_3d.text = "[%s]\nSKU-%s-#%02d\n▼ T1 / T2 / T3 / T4 ▼" % [zone_name, sku_category, pod_id]
		label_3d.modulate = zone_col

	if label_t1: label_t1.modulate = Color(0.1, 0.45, 0.85)
	if label_t2: label_t2.modulate = Color(0.0, 0.75, 0.95)
	if label_t3: label_t3.modulate = Color(0.95, 0.6, 0.1)
	if label_t4: label_t4.modulate = Color(1.0, 0.85, 0.2)

func reset_rack() -> void:
	is_toppled = false
	is_lifted = false
	freeze = false
	_needs_reset = true

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(_initial_basis, _initial_pos))
	global_transform = Transform3D(_initial_basis, _initial_pos)

	if label_3d:
		label_3d.text = "[%s]\nSKU-%s-#%02d\n▼ T1 / T2 / T3 / T4 ▼" % [zone_name, sku_category, pod_id]
		label_3d.modulate = _zone_color

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _needs_reset:
		state.transform = Transform3D(_initial_basis, _initial_pos)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_needs_reset = false

func lift_by_amr(amr_turntable: Node3D) -> Tween:
	freeze = true
	is_lifted = true
	var current_global_pos: Vector3 = global_position
	get_parent().remove_child(self)
	amr_turntable.add_child(self)
	global_position = current_global_pos
	
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", Vector3(0.0, 0.18, 0.0), 0.5)
	return tween

func drop_to_floor(new_parent: Node3D, floor_pos: Vector3) -> Tween:
	is_lifted = false
	var current_global_pos: Vector3 = global_position
	get_parent().remove_child(self)
	new_parent.add_child(self)
	global_position = current_global_pos

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", floor_pos, 0.5)
	tween.finished.connect(func(): freeze = false)
	return tween

func highlight(active: bool) -> void:
	if label_3d:
		label_3d.outline_size = 12 if active else 6
