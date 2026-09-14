class_name AmrRobot
extends Node3D

## Autonomous Mobile Robot (AMR) designed for smart warehouse Goods-to-Person logistics.
## Features elevating turntable, multi-color state LED ring, and VDA 5050 state reporting.

enum AmrState {
	IDLE = 0,
	MOVING = 1,
	YIELDING = 2,
	BLOCKED_SAFETY = 3,
	LIFTING = 4,
	CHARGING = 5
}

const COLOR_MOVING: Color = Color(0.1, 0.9, 0.2)       # Green
const COLOR_YIELDING: Color = Color(1.0, 0.8, 0.0)     # Yellow (Anti-Deadlock)
const COLOR_BLOCKED: Color = Color(0.9, 0.1, 0.1)      # Red (OR Guardrail)
const COLOR_LIFTING: Color = Color(0.1, 0.6, 1.0)      # Blue (Docking)
const COLOR_CHARGING: Color = Color(0.0, 1.0, 0.8)     # Cyan (Charging)

@export var robot_id: String = "AMR-01"
@export var max_speed: float = 8.0
@export var battery_level: float = 100.0

@onready var turntable: Node3D = $Chassis/ElevatingTurntable
@onready var led_ring: MeshInstance3D = $Chassis/LedRing
@onready var label_status: Label3D = $StatusBadge

var current_state: AmrState = AmrState.IDLE
var carried_pod: ShelfPod = null
var _led_material: StandardMaterial3D

func _ready() -> void:
	if led_ring:
		_led_material = StandardMaterial3D.new()
		_led_material.roughness = 0.2
		_led_material.emission_enabled = true
		led_ring.set_surface_override_material(0, _led_material)
	set_amr_state(AmrState.IDLE)

func set_amr_state(new_state: AmrState) -> void:
	current_state = new_state
	var state_color: Color = COLOR_MOVING
	var state_text: String = "IDLE"

	match current_state:
		AmrState.IDLE:
			state_color = Color(0.5, 0.5, 0.5)
			state_text = "STANDBY"
		AmrState.MOVING:
			state_color = COLOR_MOVING
			state_text = "CRUISING" if carried_pod == null else "TRANSPORTING POD #%d" % carried_pod.pod_id
		AmrState.YIELDING:
			state_color = COLOR_YIELDING
			state_text = "YIELDING (MARL ANTI-DEADLOCK)"
		AmrState.BLOCKED_SAFETY:
			state_color = COLOR_BLOCKED
			state_text = "OR SAFETY GUARDRAIL STOP"
		AmrState.LIFTING:
			state_color = COLOR_LIFTING
			state_text = "LIFTING SHELF POD"
		AmrState.CHARGING:
			state_color = COLOR_CHARGING
			state_text = "CHARGING (%.0f%%)" % battery_level

	if _led_material:
		_led_material.albedo_color = state_color
		_led_material.emission = state_color
		_led_material.emission_energy_multiplier = 2.0

	if label_status:
		label_status.text = "%s [%s]\n🔋 %.0f%%" % [robot_id, state_text, battery_level]

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
