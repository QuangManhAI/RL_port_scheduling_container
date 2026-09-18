class_name ConveyorBelt
extends StaticBody3D

## Motorized Logistics Conveyor Belt with Outbound Truck / Cargo Container Integration.
## Uses Godot StaticBody3D constant_linear_velocity to impart physical surface friction
## to ToteBox RigidBody3D payloads, smoothly transporting them from the AMR drop zone
## along the conveyor line and down the transition chute into the waiting delivery truck.

signal box_loaded_onto_truck(box: ToteBox)

@export var belt_speed: float = 1.2 ## Surface speed in meters/second along the X-axis
@export var is_running: bool = true

@onready var belt_col: CollisionShape3D = get_node_or_null("ColDeck")
@onready var drop_marker: Marker3D = get_node_or_null("DropTargetMarker")
@onready var truck_area: Area3D = get_node_or_null("TruckBed/CargoArea")
@onready var status_label: Label3D = get_node_or_null("StationLabel")

var delivered_boxes: Array[ToteBox] = []
var _roller_meshes: Array[MeshInstance3D] = []
var _uv_offset_x: float = 0.0

func _ready() -> void:
	add_to_group("conveyor_belts")

	_update_belt_velocity()

	# Collect all roller meshes for visual rotation
	for child in get_children():
		if child.name.begins_with("Roller") and child is MeshInstance3D:
			_roller_meshes.append(child)

	if truck_area:
		truck_area.body_entered.connect(_on_truck_body_entered)

	_update_status_display()

func _physics_process(delta: float) -> void:
	if not is_running:
		return

	# Keep surface velocity updated in world coordinates
	_update_belt_velocity()

	# Rotate visual rollers
	var rot_speed: float = (belt_speed / 0.04) * delta
	for r in _roller_meshes:
		r.rotate_z(-rot_speed)

	# Active physical propulsion for ToteBox payloads resting on the conveyor deck or chute
	var belt_dir_world: Vector3 = (global_transform.basis * Vector3(1.0, 0.0, 0.0)).normalized()
	var boxes = get_tree().get_nodes_in_group("tote_boxes")
	for b in boxes:
		if b is ToteBox and is_instance_valid(b) and b.visible and not b.freeze:
			var local_pos: Vector3 = to_local(b.global_position)
			# Deck length spans x = -1.4 to 2.4, transition chute to x = 2.9, deck height y ~ 0.57 to 1.2
			if local_pos.x >= -1.45 and local_pos.x <= 2.85 and local_pos.y >= 0.50 and local_pos.y <= 1.30 and abs(local_pos.z) <= 0.55:
				b.sleeping = false
				b.can_sleep = false
				var target_vel: Vector3 = belt_dir_world * belt_speed
				target_vel.y = b.linear_velocity.y # Maintain gravity
				b.linear_velocity = b.linear_velocity.move_toward(target_vel, 12.0 * delta)

func _update_belt_velocity() -> void:
	if is_running:
		# In Godot 4, StaticBody3D constant_linear_velocity is in GLOBAL coordinates
		constant_linear_velocity = (global_transform.basis * Vector3(belt_speed, 0.0, 0.0))
	else:
		constant_linear_velocity = Vector3.ZERO

func set_belt_speed(speed: float) -> void:
	belt_speed = speed
	_update_belt_velocity()

func set_running(running: bool) -> void:
	is_running = running
	_update_belt_velocity()


func _on_truck_body_entered(body: Node3D) -> void:
	if body is ToteBox and not delivered_boxes.has(body):
		delivered_boxes.append(body)
		box_loaded_onto_truck.emit(body)
		_update_status_display()

func _update_status_display() -> void:
	if status_label:
		status_label.text = "[OUTBOUND CONVEYOR SYSTEM]\nMOTORIZED BELT ACTIVE (%.1f m/s)\nTRUCK LOADED: %d BOXES" % [
			belt_speed if is_running else 0.0,
			delivered_boxes.size()
		]

func reset_conveyor() -> void:
	delivered_boxes.clear()
	_update_status_display()
