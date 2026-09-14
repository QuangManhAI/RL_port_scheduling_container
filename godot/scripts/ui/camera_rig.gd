class_name CameraRig
extends Node3D

## Warehouse Simulation Camera Rig supporting RTS pan, zoom, orbit, and tactical presets.

@export var pan_speed: float = 35.0
@export var zoom_speed: float = 3.5
@export var min_zoom: float = 8.0
@export var max_zoom: float = 120.0
@export var orbit_sensitivity: float = 0.004

@onready var elevation_pivot: Node3D = $ElevationPivot
@onready var camera_3d: Camera3D = $ElevationPivot/Camera3D

var _is_orbiting: bool = false
var _current_zoom: float = 45.0

func _ready() -> void:
	_current_zoom = camera_3d.position.z
	set_view_overview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_zoom = clamp(_current_zoom - zoom_speed, min_zoom, max_zoom)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_zoom = clamp(_current_zoom + zoom_speed, min_zoom, max_zoom)

	elif event is InputEventMouseMotion and _is_orbiting:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		rotation.y -= mm.relative.x * orbit_sensitivity
		elevation_pivot.rotation.x = clamp(
			elevation_pivot.rotation.x - mm.relative.y * orbit_sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(-10.0)
		)

	elif event is InputEventKey and event.pressed:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_1:
			set_view_overview()
		elif key.keycode == KEY_2:
			set_view_topdown()
		elif key.keycode == KEY_3:
			set_view_pick_station()
		elif key.keycode == KEY_4:
			set_view_charging_dock()

func _process(delta: float) -> void:
	var move_dir: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir += -global_transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir += -global_transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir += global_transform.basis.x

	move_dir.y = 0.0
	if move_dir.length_squared() > 0.01:
		global_position += move_dir.normalized() * pan_speed * delta

	camera_3d.position.z = lerp(camera_3d.position.z, _current_zoom, delta * 10.0)

func set_view_overview() -> void:
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, 5.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(-25.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-42.0), 0.6)
	_current_zoom = 55.0

func set_view_topdown() -> void:
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, 0.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(0.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-88.0), 0.6)
	_current_zoom = 65.0

func set_view_pick_station() -> void:
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, 26.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(0.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-28.0), 0.6)
	_current_zoom = 22.0

func set_view_charging_dock() -> void:
	set_view_inbound_dock()

func set_view_inbound_dock() -> void:
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, -30.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(180.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-30.0), 0.6)
	_current_zoom = 24.0
