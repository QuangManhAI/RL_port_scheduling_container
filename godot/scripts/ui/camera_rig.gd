class_name CameraRig
extends Node3D

## Warehouse Simulation Camera Rig supporting RTS pan, zoom, orbit, and tactical presets.

@export var pan_speed: float = 35.0
@export var zoom_speed: float = 3.5
@export var min_zoom: float = 8.0
@export var max_zoom: float = 120.0
@export var orbit_sensitivity: float = 0.004

@export var warehouse_shell: Node3D = null

@onready var elevation_pivot: Node3D = $ElevationPivot
@onready var camera_3d: Camera3D = $ElevationPivot/Camera3D

var _is_orbiting: bool = false
var _current_zoom: float = 55.0
var follow_target: Node3D = null
var is_following: bool = false

func _ready() -> void:
	_current_zoom = camera_3d.position.z
	set_view_cutaway_chart()

func toggle_follow_target(target: Node3D = null) -> bool:
	if target != null:
		follow_target = target
	if follow_target == null:
		is_following = false
		return false

	is_following = not is_following
	if is_following:
		_current_zoom = 18.0
		elevation_pivot.rotation.x = deg_to_rad(-32.0)
		if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
			warehouse_shell.set_cutaway_mode(false)
	return is_following

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

	elif event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_C:
			toggle_follow_target()
		elif key.keycode == KEY_T:
			if warehouse_shell and warehouse_shell.has_method("toggle_cutaway_mode"):
				warehouse_shell.toggle_cutaway_mode()
		elif not is_following and key.keycode == KEY_1:
			set_view_cutaway_chart()
		elif not is_following and key.keycode == KEY_2:
			set_view_mezzanine()
		elif not is_following and key.keycode == KEY_3:
			set_view_topdown()
		elif not is_following and key.keycode == KEY_4:
			set_view_pick_station()
		elif not is_following and key.keycode == KEY_5:
			set_view_inbound_dock()

func _process(delta: float) -> void:
	if is_following and follow_target != null:
		global_position = lerp(global_position, follow_target.global_position, delta * 10.0)
	else:
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

## Preset 1: Hero Chart / Cutaway Overview (Interlake Mecalux isometric layout chart)
func set_view_cutaway_chart() -> void:
	if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
		warehouse_shell.set_cutaway_mode(true)
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(10.0, 0.0, 4.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(-38.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-36.0), 0.6)
	_current_zoom = 82.0

## Backward compatibility alias
func set_view_overview() -> void:
	set_view_cutaway_chart()

## Preset 2: Mezzanine Control Room Operator View
func set_view_mezzanine() -> void:
	if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
		warehouse_shell.set_cutaway_mode(false)
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(38.0, 6.2, -32.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(-65.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-18.0), 0.6)
	_current_zoom = 16.0

## Preset 3: Top-Down Tactical Management Grid
func set_view_topdown() -> void:
	if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
		warehouse_shell.set_cutaway_mode(true)
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, 0.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(0.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-88.0), 0.6)
	_current_zoom = 75.0

## Preset 4: Pick & Pack Fulfillment Modules Close-Up
func set_view_pick_station() -> void:
	if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
		warehouse_shell.set_cutaway_mode(false)
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, 26.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(0.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-28.0), 0.6)
	_current_zoom = 24.0

## Preset 5: Inbound Receiving Dock & Truck Yard
func set_view_inbound_dock() -> void:
	if warehouse_shell and warehouse_shell.has_method("set_cutaway_mode"):
		warehouse_shell.set_cutaway_mode(false)
	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", Vector3(0.0, 0.0, -38.0), 0.6)
	tween.tween_property(self, "rotation:y", deg_to_rad(180.0), 0.6)
	tween.tween_property(elevation_pivot, "rotation:x", deg_to_rad(-30.0), 0.6)
	_current_zoom = 28.0

func set_view_charging_dock() -> void:
	set_view_inbound_dock()
