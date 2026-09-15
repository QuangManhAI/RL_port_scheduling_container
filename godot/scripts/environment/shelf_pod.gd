class_name ShelfPod
extends RigidBody3D

## Mobile Multi-Tier Stackable Storage Pod.
## Stores categorized SKU goods stacked across 4 vertical tiers (Tier 1 to Tier 4).
## Supports dynamic physical toppling, momentum impact response, and tote inventory.

@export var pod_id: int = 1
@export var zone_name: String = "Zone A"
@export var sku_category: String = "FMCG"
@export var is_lifted: bool = false
@export var is_toppled: bool = false

var _initial_pos: Vector3
var _initial_basis: Basis

@onready var label_3d: Label3D = $PodLabel
@onready var label_t1: Label3D = $LabelTier1
@onready var label_t2: Label3D = $LabelTier2
@onready var label_t3: Label3D = $LabelTier3
@onready var label_t4: Label3D = $LabelTier4

@onready var tote_t1_l: MeshInstance3D = $ToteTier1_L
@onready var tote_t1_r: MeshInstance3D = $ToteTier1_R
@onready var tote_t2_l: MeshInstance3D = $ToteTier2_L
@onready var tote_t2_r: MeshInstance3D = $ToteTier2_R
@onready var tote_t3_l: MeshInstance3D = $ToteTier3_L
@onready var tote_t3_r: MeshInstance3D = $ToteTier3_R
@onready var tote_t4_l: MeshInstance3D = $ToteTier4_L
@onready var tote_t4_r: MeshInstance3D = $ToteTier4_R

var _tote_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	add_to_group("shelf_pods")
	_initial_pos = global_position
	_initial_basis = global_transform.basis

func _physics_process(_delta: float) -> void:
	if not is_lifted and not is_toppled:
		var up_alignment: float = global_transform.basis.y.dot(Vector3.UP)
		if up_alignment < 0.72:
			is_toppled = true
			if label_3d:
				label_3d.text = "[%s]\n⚠️ RACK TOPPLED!\nSKU-%s-#%02d" % [zone_name, sku_category, pod_id]
				label_3d.modulate = Color(1.0, 0.2, 0.2, 1.0)

func get_tote_at(tier: int, check_pos: Vector3) -> MeshInstance3D:
	var left_node: MeshInstance3D = null
	var right_node: MeshInstance3D = null
	match tier:
		1:
			left_node = tote_t1_l
			right_node = tote_t1_r
		2:
			left_node = tote_t2_l
			right_node = tote_t2_r
		3:
			left_node = tote_t3_l
			right_node = tote_t3_r
		4:
			left_node = tote_t4_l
			right_node = tote_t4_r

	if not left_node or not right_node:
		return null

	var left_dist: float = left_node.global_position.distance_to(check_pos)
	var right_dist: float = right_node.global_position.distance_to(check_pos)

	if left_dist < right_dist:
		if left_node.visible:
			return left_node
		elif right_node.visible:
			return right_node
	else:
		if right_node.visible:
			return right_node
		elif left_node.visible:
			return left_node
	return null

func pick_tote(tier: int, check_pos: Vector3) -> Dictionary:
	var tote: MeshInstance3D = get_tote_at(tier, check_pos)
	if tote and tote.visible:
		tote.visible = false
		return {
			"found": true,
			"material": tote.material_override,
			"tier": tier,
			"sku_zone": zone_name
		}
	return {"found": false}

func reset_totes() -> void:
	for t in [tote_t1_l, tote_t1_r, tote_t2_l, tote_t2_r, tote_t3_l, tote_t3_r, tote_t4_l, tote_t4_r]:
		if t:
			t.visible = true


func setup(p_id: int, p_zone: String = "Zone A", p_cat: String = "FMCG", zone_col: Color = Color(0.0, 0.8, 1.0)) -> void:
	pod_id = p_id
	zone_name = p_zone
	sku_category = p_cat

	if label_3d:
		label_3d.text = "[%s]\nSKU-%s-#%02d\n▼ T1 / T2 / T3 / T4 ▼" % [zone_name, sku_category, pod_id]
		label_3d.modulate = zone_col

	# Set tier labels to match zone accent
	if label_t1: label_t1.modulate = Color(0.1, 0.45, 0.85)
	if label_t2: label_t2.modulate = Color(0.0, 0.75, 0.95)
	if label_t3: label_t3.modulate = Color(0.95, 0.6, 0.1)
	if label_t4: label_t4.modulate = Color(1.0, 0.85, 0.2)

func reset_rack() -> void:
	is_toppled = false
	is_lifted = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = _initial_pos
	global_transform.basis = _initial_basis
	reset_totes()
	if label_3d:
		label_3d.text = "[%s]\nSKU-%s-#%02d\n▼ T1 / T2 / T3 / T4 ▼" % [zone_name, sku_category, pod_id]
		label_3d.modulate = Color.WHITE

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
