class_name ProceduralWarehouse
extends Node3D

## ProceduralWarehouse generates 4 distinct zoned inventory areas:
## Zone A: Fast-Moving FMCG (Cyan)
## Zone B: Electronics & High-Tech (Emerald)
## Zone C: Pharmaceuticals & Sensitive (Purple)
## Zone D: Heavy Bulky Pallet Stacks (Amber)
## Generates 32 hollow physical ShelfPods and 256 physical ToteBoxes resting on shelf plates.

@export var pod_scene: PackedScene = preload("res://scenes/environment/shelf_pod.tscn")
@export var tote_scene: PackedScene = preload("res://scenes/environment/tote_box.tscn")

const ZONE_CONFIGS: Array[Dictionary] = [
	{
		"name": "Zone A",
		"category": "FMCG",
		"desc": "FAST-MOVING CONSUMER GOODS",
		"color": Color(0.0, 0.85, 1.0, 1),
		"center_x": -24.0,
		"sign_pos": Vector3(-24.0, 8.5, -2.0)
	},
	{
		"name": "Zone B",
		"category": "TECH",
		"desc": "ELECTRONICS & HARDWARE",
		"color": Color(0.1, 0.95, 0.45, 1),
		"center_x": -8.0,
		"sign_pos": Vector3(-8.0, 8.5, -2.0)
	},
	{
		"name": "Zone C",
		"category": "PHARMA",
		"desc": "PHARMACEUTICALS & COLD-CHAIN",
		"color": Color(0.75, 0.25, 1.0, 1),
		"center_x": 8.0,
		"sign_pos": Vector3(8.0, 8.5, -2.0)
	},
	{
		"name": "Zone D",
		"category": "BULKY",
		"desc": "HEAVY BULKY PALLET STACKS",
		"color": Color(1.0, 0.65, 0.1, 1),
		"center_x": 24.0,
		"sign_pos": Vector3(24.0, 8.5, -2.0)
	}
]

const TOTE_SLOT_DEFS: Array[Dictionary] = [
	{"tier": 1, "side": "L", "offset": Vector3(-0.36, 0.56, 0.0)},
	{"tier": 1, "side": "R", "offset": Vector3(0.36, 0.56, 0.0)},
	{"tier": 2, "side": "L", "offset": Vector3(-0.36, 1.11, 0.0)},
	{"tier": 2, "side": "R", "offset": Vector3(0.36, 1.11, 0.0)},
	{"tier": 3, "side": "L", "offset": Vector3(-0.36, 1.67, 0.0)},
	{"tier": 3, "side": "R", "offset": Vector3(0.36, 1.67, 0.0)},
	{"tier": 4, "side": "L", "offset": Vector3(-0.36, 2.23, 0.0)},
	{"tier": 4, "side": "R", "offset": Vector3(0.36, 2.23, 0.0)},
]

var _pods: Dictionary = {}
var _pods_by_zone: Dictionary = {"Zone A": [], "Zone B": [], "Zone C": [], "Zone D": []}
var _pods_root: Node3D
var _totes_root: Node3D
var _signs_root: Node3D

func _ready() -> void:
	_pods_root = Node3D.new()
	_pods_root.name = "PodsRoot"
	add_child(_pods_root)

	_totes_root = Node3D.new()
	_totes_root.name = "TotesRoot"
	add_child(_totes_root)

	_signs_root = Node3D.new()
	_signs_root.name = "SignsRoot"
	add_child(_signs_root)

	generate_zoned_warehouse()

func generate_zoned_warehouse() -> void:
	var next_id: int = 1

	for z_cfg in ZONE_CONFIGS:
		var z_name: String = z_cfg["name"]
		var z_cat: String = z_cfg["category"]
		var z_col: Color = z_cfg["color"]
		var center_x: float = z_cfg["center_x"]

		# Create Overhead 3D Zone Banner hanging from roof truss
		_create_overhead_banner(z_cfg["sign_pos"], "[ %s • %s ]\n4-Tier Stacked Inventory" % [z_name.to_upper(), z_cfg["desc"]], z_col)

		# Generate 2 rows of 4 pods per zone (8 pods per zone, 32 total pods across 4 tiers)
		for side in [-1.4, 1.4]:
			var row_x: float = center_x + side
			for p in range(4):
				var pod_z: float = -14.0 + float(p) * 6.5
				var pod_pos: Vector3 = Vector3(row_x, 0.02, pod_z)
				var instance: ShelfPod = spawn_pod(next_id, pod_pos, z_name, z_cat, z_col)
				_pods_by_zone[z_name].append(instance)
				next_id += 1

	# Create Inbound and Outbound Dock Banners
	_create_overhead_banner(Vector3(0.0, 8.5, -34.0), "[ 📥 INBOUND RECEIVING DOCK ]\nReceiving Manifest Staging", Color(0.2, 0.8, 1.0, 1))
	_create_overhead_banner(Vector3(0.0, 8.5, 30.0), "[ 📤 OUTBOUND DISPATCH DOCK ]\nGoods-to-Person Pick & Pack Stations", Color(0.1, 0.95, 0.45, 1))

func _create_overhead_banner(pos: Vector3, text: String, col: Color) -> void:
	var banner: Node3D = Node3D.new()
	banner.position = pos
	_signs_root.add_child(banner)

	# Label 3D Billboard
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 30
	label.outline_size = 14
	label.modulate = col
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.add_child(label)

func spawn_pod(p_id: int, pos: Vector3, z_name: String, z_cat: String, z_col: Color) -> ShelfPod:
	var instance: ShelfPod = pod_scene.instantiate() as ShelfPod
	instance.position = pos
	_pods_root.add_child(instance)
	instance.setup(p_id, z_name, z_cat, z_col, pos)
	_pods[p_id] = instance

	# Spawn 8 physical ToteBox instances resting on the shelf plates of this rack
	for s_def in TOTE_SLOT_DEFS:
		var tier_idx: int = s_def["tier"]
		var side_str: String = s_def["side"]
		var offset_vec: Vector3 = s_def["offset"]

		var box_mat := StandardMaterial3D.new()
		var tier_factor: float = 0.75 + float(tier_idx) * 0.08
		box_mat.albedo_color = Color(z_col.r * tier_factor, z_col.g * tier_factor, z_col.b * tier_factor, 1.0)
		box_mat.roughness = 0.35
		box_mat.metallic = 0.2

		var box_pos: Vector3 = pos + offset_vec
		var box_inst: ToteBox = tote_scene.instantiate() as ToteBox
		box_inst.position = box_pos
		_totes_root.add_child(box_inst)
		box_inst.dock_to_shelf(instance, tier_idx, side_str, offset_vec, box_mat, z_name, z_cat, box_pos)
		instance.register_tote(box_inst)

	return instance

func get_pod(p_id: int) -> ShelfPod:
	return _pods.get(p_id, null)

func get_first_pod_in_zone(z_name: String) -> ShelfPod:
	var list = _pods_by_zone.get(z_name, [])
	if list.size() > 0:
		return list[0]
	return null

func get_all_pods() -> Array:
	return _pods.values()
