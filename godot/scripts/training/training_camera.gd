class_name TrainingCamera
extends Camera3D

## Interactive Camera for RL Training Scenes
## Operates with process_mode = PROCESS_MODE_ALWAYS so navigation, orbiting,
## and zooming work even when physics simulation is paused between RL steps.

@export var target_node: Node3D = null
@export var default_distance: float = 14.0
@export var follow_distance: float = 4.5
@export var follow_height: float = 2.8
@export var orbit_sensitivity: float = 0.005
@export var zoom_speed: float = 1.0

var follow_mode: bool = false
var _pivot_pos: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-45.0)
var _current_dist: float = 14.0
var _is_orbiting: bool = false
var _is_panning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = true
	_current_dist = default_distance
	_update_camera_transform()

func _process(delta: float) -> void:
	if follow_mode and is_instance_valid(target_node):
		_pivot_pos = _pivot_pos.lerp(target_node.global_position, 8.0 * delta)
	_update_camera_transform()

func _update_camera_transform() -> void:
	var cam_offset = Vector3(
		_current_dist * cos(_pitch) * sin(_yaw),
		_current_dist * -sin(_pitch),
		_current_dist * cos(_pitch) * cos(_yaw)
	)
	global_position = _pivot_pos + cam_offset
	look_at(_pivot_pos, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_dist = clampf(_current_dist - zoom_speed, 2.0, 40.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_dist = clampf(_current_dist + zoom_speed, 2.0, 40.0)

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if _is_orbiting:
			_yaw -= mm.relative.x * orbit_sensitivity
			_pitch = clampf(_pitch + mm.relative.y * orbit_sensitivity, deg_to_rad(-85.0), deg_to_rad(-10.0))
		elif _is_panning:
			var right = global_transform.basis.x
			var up = global_transform.basis.y
			_pivot_pos -= (right * mm.relative.x - up * mm.relative.y) * 0.02

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C:
			follow_mode = not follow_mode
			if follow_mode and is_instance_valid(target_node):
				_pivot_pos = target_node.global_position
				_current_dist = follow_distance
				_pitch = deg_to_rad(-30.0)
			else:
				_pivot_pos = Vector3.ZERO
				_current_dist = default_distance
				_pitch = deg_to_rad(-45.0)
				_yaw = 0.0
		elif event.keycode == KEY_R:
			_pivot_pos = Vector3.ZERO
			_current_dist = default_distance
			_yaw = 0.0
			_pitch = deg_to_rad(-45.0)
			follow_mode = false
