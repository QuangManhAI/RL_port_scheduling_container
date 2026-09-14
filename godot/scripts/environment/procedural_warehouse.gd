class_name ProceduralWarehouse
extends Node3D

## ProceduralWarehouse generates storage rack aisles, navigation corridors,
## and spawns mobile shelf pods at designated inventory coordinates.

@export var aisles_count: int = 4
@export var pods_per_aisle: int = 6
@export var pod_scene: PackedScene = preload("res://scenes/environment/shelf_pod.tscn")

const POD_SIZE: float = 1.6
const POD_GAP: float = 0.8
const AISLE_WIDTH: float = 4.5

var _pods: Dictionary = {}
var _pods_root: Node3D

func _ready() -> void:
	_pods_root = Node3D.new()
	_pods_root.name = "PodsRoot"
	add_child(_pods_root)
	generate_storage_racks()

func generate_storage_racks() -> void:
	var total_width_x: float = aisles_count * AISLE_WIDTH
	var start_x: float = -total_width_x * 0.5 + AISLE_WIDTH * 0.5
	var start_z: float = -((pods_per_aisle * (POD_SIZE + POD_GAP)) * 0.5)

	var next_id: int = 1
	for a: int in range(aisles_count):
		var aisle_x: float = start_x + a * AISLE_WIDTH
		# Place two rows of pods facing the aisle
		for side: int in [-1, 1]:
			var row_x: float = aisle_x + (side * (POD_SIZE * 0.5 + 0.3))
			for p: int in range(pods_per_aisle):
				var pod_z: float = start_z + p * (POD_SIZE + POD_GAP)
				spawn_pod(next_id, Vector3(row_x, 0.0, pod_z))
				next_id += 1

func spawn_pod(p_id: int, pos: Vector3) -> ShelfPod:
	var instance: ShelfPod = pod_scene.instantiate() as ShelfPod
	_pods_root.add_child(instance)
	instance.position = pos
	instance.setup(p_id)
	_pods[p_id] = instance
	return instance

func get_pod(p_id: int) -> ShelfPod:
	return _pods.get(p_id, null)

func get_all_pods() -> Array:
	return _pods.values()
