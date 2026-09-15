class_name AmrRobot
extends Node3D

## Autonomous Mobile Robot (AMR) designed for smart warehouse Goods-to-Person logistics.
## Features elevating turntable, multi-color state LED ring, rotating LiDAR, and VDA 5050 state reporting.

enum AmrState {
	IDLE = 0,
	MOVING = 1,
	YIELDING = 2,
	BLOCKED_SAFETY = 3,
	LIFTING = 4,
	CHARGING = 5
}

const COLOR_MOVING: Color = Color(0.0, 0.95, 1.0)      # Cyan (Cruising)
const COLOR_YIELDING: Color = Color(1.0, 0.82, 0.0)    # Amber (MARL Anti-Deadlock)
const COLOR_BLOCKED: Color = Color(1.0, 0.2, 0.2)     # Red (OR Guardrail Stop)
const COLOR_LIFTING: Color = Color(0.7, 0.2, 1.0)      # Electric Purple (G2P Docking)
const COLOR_CHARGING: Color = Color(0.1, 0.9, 0.4)     # Emerald (Charging)

@export var robot_id: String = "AMR-01"
@export var max_speed: float = 6.5
@export var battery_level: float = 100.0
@export var current_task_str: String = "STANDBY"
@export var is_manual_control: bool = false
@export var linear_acceleration: float = 9.0
@export var linear_deceleration: float = 14.0
@export var turn_speed: float = 3.2

@onready var turntable: Node3D = $Chassis/ElevatingTurntable
@onready var led_ring: MeshInstance3D = $Chassis/LedRing
@onready var laser_plane: MeshInstance3D = $Chassis/LidarTurret/LaserScanPlane
@onready var label_status: Label3D = $StatusBadge

var current_state: AmrState = AmrState.IDLE
var carried_pod: ShelfPod = null
var current_speed: float = 0.0
var _manual_linear_vel: float = 0.0
var _led_material: StandardMaterial3D
var _laser_material: StandardMaterial3D

func _ready() -> void:
	if led_ring:
		_led_material = StandardMaterial3D.new()
		_led_material.roughness = 0.2
		_led_material.emission_enabled = true
		led_ring.set_surface_override_material(0, _led_material)
	if laser_plane:
		_laser_material = StandardMaterial3D.new()
		_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_laser_material.albedo_color = Color(0.0, 0.9, 1.0, 0.18)
		_laser_material.emission_enabled = true
		_laser_material.emission = Color(0.0, 0.9, 1.0, 1.0)
		_laser_material.emission_energy_multiplier = 1.5
		laser_plane.set_surface_override_material(0, _laser_material)

	set_amr_state(AmrState.IDLE)

func _process(delta: float) -> void:
	if laser_plane:
		laser_plane.rotate_y(delta * 8.0)

func _physics_process(delta: float) -> void:
	if is_manual_control:
		_process_manual_driving(delta)

func _process_manual_driving(delta: float) -> void:
	var move_input: float = 0.0
	var turn_input: float = 0.0
	var is_braking: bool = Input.is_key_pressed(KEY_SPACE)

	# Forward / Reverse
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_input += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_input -= 0.65

	# Left / Right Rotation
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn_input += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn_input -= 1.0

	# Apply rotation in place
	if abs(turn_input) > 0.01:
		rotate_y(turn_input * turn_speed * delta)

	# Apply linear acceleration / deceleration
	if is_braking:
		_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, linear_deceleration * 2.0 * delta)
		set_amr_state(AmrState.BLOCKED_SAFETY)
	elif abs(move_input) > 0.01:
		var target_v: float = move_input * max_speed
		_manual_linear_vel = move_toward(_manual_linear_vel, target_v, linear_acceleration * delta)
		set_amr_state(AmrState.MOVING)
	else:
		_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, linear_deceleration * delta)
		if abs(_manual_linear_vel) < 0.05:
			_manual_linear_vel = 0.0
			set_amr_state(AmrState.IDLE)

	# Forward translation (-transform.basis.z is forward in Godot 3D)
	if abs(_manual_linear_vel) > 0.01:
		var forward_vec: Vector3 = -global_transform.basis.z
		global_position += forward_vec * _manual_linear_vel * delta

	# Floor boundary safety clamp
	global_position.x = clamp(global_position.x, -33.0, 33.0)
	global_position.z = clamp(global_position.z, -35.0, 32.0)

	current_speed = abs(_manual_linear_vel)
	current_task_str = "MANUAL PILOT"

	if label_status:
		label_status.text = "%s [DEV BOT]\n⚡ %.0f%% | %.1f m/s" % [robot_id, battery_level, current_speed]

func set_amr_state(new_state: AmrState) -> void:
	current_state = new_state
	var state_color: Color = COLOR_MOVING
	var state_text: String = "IDLE"

	match current_state:
		AmrState.IDLE:
			state_color = Color(0.4, 0.5, 0.6)
			state_text = "STANDBY"
			current_speed = 0.0
		AmrState.MOVING:
			state_color = COLOR_MOVING
			state_text = "CRUISING" if carried_pod == null else "TRANSPORTING POD #%d" % carried_pod.pod_id
			current_speed = 1.8
		AmrState.YIELDING:
			state_color = COLOR_YIELDING
			state_text = "YIELDING (MARL NEGOTIATION)"
			current_speed = 0.0
		AmrState.BLOCKED_SAFETY:
			state_color = COLOR_BLOCKED
			state_text = "OR SAFETY STOP"
			current_speed = 0.0
		AmrState.LIFTING:
			state_color = COLOR_LIFTING
			state_text = "LIFTING SHELF POD"
			current_speed = 0.2
		AmrState.CHARGING:
			state_color = COLOR_CHARGING
			state_text = "CHARGING"
			current_speed = 0.0

	current_task_str = state_text

	if _led_material:
		_led_material.albedo_color = state_color
		_led_material.emission = state_color
		_led_material.emission_energy_multiplier = 3.5

	if _laser_material:
		_laser_material.emission = state_color

	if label_status:
		label_status.text = "%s [%s]\n⚡ %.0f%% | %.1f m/s" % [robot_id, state_text, battery_level, current_speed]
		label_status.modulate = Color(1.0, 1.0, 1.0, 1.0)
		label_status.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
		label_status.outline_size = 14

func drive_to(target: Vector3, duration_override: float = -1.0) -> Tween:
	set_amr_state(AmrState.MOVING)
	var dist: float = global_position.distance_to(target)
	var duration: float = (dist / max_speed) if duration_override <= 0.0 else duration_override
	duration = max(0.4, duration)

	var look_target: Vector3 = Vector3(target.x, global_position.y, target.z)
	if global_position.distance_squared_to(look_target) > 0.05:
		look_at(look_target, Vector3.UP)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", target, duration)
	tween.finished.connect(func(): set_amr_state(AmrState.IDLE))
	return tween

func yield_at_intersection(wait_seconds: float = 1.2) -> Tween:
	set_amr_state(AmrState.YIELDING)
	var tween: Tween = create_tween()
	tween.tween_interval(wait_seconds)
	return tween

func dock_and_lift_pod(pod: ShelfPod) -> Tween:
	set_amr_state(AmrState.LIFTING)
	carried_pod = pod
	var tween: Tween = pod.lift_by_amr(turntable)
	tween.finished.connect(func(): set_amr_state(AmrState.MOVING))
	return tween

func dock_and_drop_pod(new_parent: Node3D, floor_pos: Vector3) -> Tween:
	if not carried_pod:
		return null
	set_amr_state(AmrState.LIFTING)
	var pod: ShelfPod = carried_pod
	carried_pod = null
	var tween: Tween = pod.drop_to_floor(new_parent, floor_pos)
	tween.finished.connect(func(): set_amr_state(AmrState.IDLE))
	return tween

func get_telemetry_dict() -> Dictionary:
	return {
		"id": robot_id,
		"state_str": current_task_str,
		"battery": battery_level,
		"speed": current_speed,
		"pos": global_position,
		"carried_pod_id": carried_pod.pod_id if carried_pod else 0,
		"vda_node": "NODE_(%.0f,%.0f)" % [global_position.x, global_position.z]
	}
