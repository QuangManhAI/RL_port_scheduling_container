class_name WarehouseShell
extends Node3D

## WarehouseShell manages the realistic 3PL distribution center building envelope,
## including tilt-up concrete walls, roof trusses, skylights, two-story office mezzanine,
## exterior truck yard, zone dressing, high-bay lighting, and cutaway visualization mode.

signal cutaway_toggled(is_cutaway: bool)

@onready var near_wall: Node3D = $Structure/PerimeterWalls/WallEast
@onready var roof_group: Node3D = $Structure/Roof
@onready var skylights_group: Node3D = $Structure/Skylights
@onready var ceiling_dressing: Node3D = $Structure/CeilingDressing

var is_cutaway_mode: bool = false

func _ready() -> void:
	# Default to full shell; cutaway is activated for Chart/Cutaway camera preset
	set_cutaway_mode(false)

func set_cutaway_mode(enabled: bool) -> void:
	is_cutaway_mode = enabled
	if near_wall:
		near_wall.visible = not enabled
	if roof_group:
		roof_group.visible = not enabled
	if skylights_group:
		skylights_group.visible = not enabled
	if ceiling_dressing:
		ceiling_dressing.visible = not enabled
	cutaway_toggled.emit(enabled)

func toggle_cutaway_mode() -> bool:
	set_cutaway_mode(not is_cutaway_mode)
	return is_cutaway_mode
