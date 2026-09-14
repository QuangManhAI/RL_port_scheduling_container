class_name ShipEntity
extends Node3D

## Ship Entity represents a docked or arriving container vessel.

@export var ship_name: String = "MV PACIFIC VOYAGER"
@export var total_cargo: int = 40
@export var remaining_cargo: int = 40

func _ready() -> void:
	pass

func update_cargo_status(remaining: int) -> void:
	remaining_cargo = remaining
