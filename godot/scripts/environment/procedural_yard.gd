class_name ProceduralYard
extends Node3D

## ProceduralYard automatically builds 3D yard blocks, ground markings,
## and container slots according to port configuration.

@export var num_blocks: int = 2
@export var bays_per_block: int = 4
@export var stacks_per_bay: int = 4
@export var max_tiers: int = 3

@export var container_scene: PackedScene = preload("res://scenes/entities/container.tscn")

const CONTAINER_LENGTH: float = 6.06
const CONTAINER_WIDTH: float = 2.44
const CONTAINER_HEIGHT: float = 2.59

const GAP_STACK_Z: float = 0.3
const GAP_BAY_X: float = 1.2
const BLOCK_SPACING_Z: float = 16.0

# (block, bay, stack, tier) -> ContainerEntity
var _active_containers: Dictionary = {}
var _containers_root: Node3D

func _ready() -> void:
	_containers_root = Node3D.new()
	_containers_root.name = "Containers"
	add_child(_containers_root)
	generate_ground_layout()

func generate_ground_layout() -> void:
	# Clear existing ground nodes if re-generating
	for child in get_children():
		if child != _containers_root:
			child.queue_free()

	var block_width_z: float = stacks_per_bay * (CONTAINER_WIDTH + GAP_STACK_Z)
	var block_length_x: float = bays_per_block * (CONTAINER_LENGTH + GAP_BAY_X)

	for b: int in range(num_blocks):
		var block_origin_z: float = b * (block_width_z + BLOCK_SPACING_Z)
		var pad: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(block_length_x + 4.0, 0.2, block_width_z + 4.0)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.24, 0.26)
		mat.roughness = 0.85
		pad.mesh = box
		pad.set_surface_override_material(0, mat)

		var center_x: float = (block_length_x * 0.5) - (CONTAINER_LENGTH * 0.5)
		var center_z: float = block_origin_z + (block_width_z * 0.5) - (CONTAINER_WIDTH * 0.5)
		pad.position = Vector3(center_x, -0.1, center_z)
		add_child(pad)

func get_slot_position(block: int, bay: int, stack: int, tier: int) -> Vector3:
	var block_width_z: float = stacks_per_bay * (CONTAINER_WIDTH + GAP_STACK_Z)
	var block_origin_z: float = block * (block_width_z + BLOCK_SPACING_Z)

	var pos_x: float = bay * (CONTAINER_LENGTH + GAP_BAY_X)
	var pos_y: float = tier * CONTAINER_HEIGHT
	var pos_z: float = block_origin_z + stack * (CONTAINER_WIDTH + GAP_STACK_Z)

	return Vector3(pos_x, pos_y, pos_z)

func spawn_container(block: int, bay: int, stack: int, tier: int, c_id: int, c_type: int) -> ContainerEntity:
	var key: Vector4i = Vector4i(block, bay, stack, tier)
	if _active_containers.has(key):
		remove_container(block, bay, stack, tier)

	var instance: ContainerEntity = container_scene.instantiate() as ContainerEntity
	_containers_root.add_child(instance)
	instance.position = get_slot_position(block, bay, stack, tier)
	instance.setup(c_id, c_type)
	_active_containers[key] = instance
	return instance

func remove_container(block: int, bay: int, stack: int, tier: int) -> void:
	var key: Vector4i = Vector4i(block, bay, stack, tier)
	if _active_containers.has(key):
		var node: Node = _active_containers[key]
		if is_instance_valid(node):
			node.queue_free()
		_active_containers.erase(key)

func clear_all() -> void:
	for node: Node in _active_containers.values():
		if is_instance_valid(node):
			node.queue_free()
	_active_containers.clear()

## Synchronize 3D container state from a 4D array or dictionary snapshot
func sync_yard_state(grid: Array) -> void:
	# grid shape: [num_blocks][bays_per_block][stacks_per_bay][tiers]
	for b: int in range(grid.size()):
		var block_arr: Array = grid[b]
		for bay: int in range(block_arr.size()):
			var bay_arr: Array = block_arr[bay]
			for s: int in range(bay_arr.size()):
				var stack_arr: Array = bay_arr[s]
				for t: int in range(stack_arr.size()):
					var c_data = stack_arr[t]
					var key: Vector4i = Vector4i(b, bay, s, t)
					if c_data != null and (c_data is Dictionary or c_data is Array):
						var c_id: int = c_data["id"] if c_data is Dictionary else int(c_data[0])
						var c_type: int = c_data["type"] if c_data is Dictionary else int(c_data[1])
						if not _active_containers.has(key) or _active_containers[key].container_id != c_id:
							spawn_container(b, bay, s, t, c_id, c_type)
					elif c_data == null and _active_containers.has(key):
						remove_container(b, bay, s, t)
