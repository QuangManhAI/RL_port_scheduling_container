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

	# Set physical surface velocity on the StaticBody3D
	# In Godot 4, constant_linear_velocity affects contacting RigidBody3D via surface friction
	if is_running:
		constant_linear_velocity = Vector3(belt_speed, 0.0, 0.0)
	else:
		constant_linear_velocity = Vector3.ZERO

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

	# Rotate visual rollers
	var rot_speed: float = (belt_speed / 0.04) * delta
	for r in _roller_meshes:
		r.rotate_z(-rot_speed)

func set_belt_speed(speed: float) -> void:
	belt_speed = speed
	if is_running:
		constant_linear_velocity = Vector3(belt_speed, 0.0, 0.0)
	else:
		constant_linear_velocity = Vector3.ZERO

func set_running(running: bool) -> void:
	is_running = running
	if is_running:
		constant_linear_velocity = Vector3(belt_speed, 0.0, 0.0)
	else:
		constant_linear_velocity = Vector3.ZERO

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
