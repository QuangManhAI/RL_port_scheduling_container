class_name ProceduralWarehouse
extends Node3D

## ProceduralWarehouse generates 4 distinct zoned inventory areas:
## Zone A: Fast-Moving FMCG (Cyan)
## Zone B: Electronics & High-Tech (Emerald)
## Zone C: Pharmaceuticals & Sensitive (Purple)
## Zone D: Heavy Bulky Pallet Stacks (Amber)
## Plus Overhead 3D Zone Banners and Inbound/Outbound Staging Docks.

@export var pod_scene: PackedScene = preload("res://scenes/environment/shelf_pod.tscn")

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

var _pods: Dictionary = {}
var _pods_by_zone: Dictionary = {"Zone A": [], "Zone B": [], "Zone C": [], "Zone D": []}
var _pods_root: Node3D
var _signs_root: Node3D

func _ready() -> void:
	_pods_root = Node3D.new()
	_pods_root.name = "PodsRoot"
	add_child(_pods_root)

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
				var instance: ShelfPod = spawn_pod(next_id, Vector3(row_x, 0.02, pod_z), z_name, z_cat, z_col)
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
	_pods_root.add_child(instance)
	instance.position = pos
	instance.setup(p_id, z_name, z_cat, z_col)
	_pods[p_id] = instance
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
