class_name ShelfPod
extends Node3D

## Mobile Multi-Tier Stackable Storage Pod.
## Stores categorized SKU goods stacked across 4 vertical tiers (Tier 1 to Tier 4).

@export var pod_id: int = 1
@export var zone_name: String = "Zone A"
@export var sku_category: String = "FMCG"
@export var is_lifted: bool = false

@onready var label_3d: Label3D = $PodLabel
@onready var label_t1: Label3D = $LabelTier1
@onready var label_t2: Label3D = $LabelTier2
@onready var label_t3: Label3D = $LabelTier3
@onready var label_t4: Label3D = $LabelTier4

var _tote_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	pass

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

func lift_by_amr(amr_turntable: Node3D) -> Tween:
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
	return tween

func highlight(active: bool) -> void:
	if label_3d:
		label_3d.outline_size = 12 if active else 6
