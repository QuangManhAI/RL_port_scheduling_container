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

@onready var arm: Node3D = $RoboticArm
@onready var shoulder: Node3D = $RoboticArm/ShoulderJoint
@onready var elbow: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint
@onready var wrist: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint
@onready var gripped_box: MeshInstance3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/GrippedBox
@onready var cargo_tray: Node3D = $Chassis/CargoTray
@onready var tray_box: MeshInstance3D = $Chassis/CargoTray/TrayBox1
@onready var side_strip_left: MeshInstance3D = $Chassis/SideLedStripLeft
@onready var side_strip_right: MeshInstance3D = $Chassis/SideLedStripRight
enum ArmMotionState {
	STATIONARY,
	PREPARING,
	AIMING_TIER,
	PICKING,
	GRIPPED,
	STOWING
}

@onready var label_status: Label3D = $StatusBadge

var current_state: AmrState = AmrState.IDLE
var arm_motion_state: ArmMotionState = ArmMotionState.STATIONARY
var carried_pod: ShelfPod = null
var current_speed: float = 0.0
var _manual_linear_vel: float = 0.0
var _led_material: StandardMaterial3D

var has_gripped_box: bool = false
var selected_tier: int = 1
var arm_reach_side: float = 1.0
var stowed_box_count: int = 0
var _current_box_material: Material = null
var _is_arm_tweening: bool = false
var _was_braking: bool = false
var _arm_status_text: String = "[WASD] Drive | [E] Prep Arm"

func _ready() -> void:
	_led_material = StandardMaterial3D.new()
	_led_material.roughness = 0.2
	_led_material.emission_enabled = true
	if side_strip_left:
		side_strip_left.set_surface_override_material(0, _led_material)
	if side_strip_right:
		side_strip_right.set_surface_override_material(0, _led_material)

	if gripped_box:
		gripped_box.visible = false
	if tray_box:
		tray_box.visible = false

	# Initial home fold (stationary resting pose)
	if arm: arm.rotation.y = 0.0
	if shoulder: shoulder.rotation.x = deg_to_rad(-25.0)
	if elbow: elbow.rotation.x = deg_to_rad(45.0)
	if wrist: wrist.rotation.x = deg_to_rad(-20.0)

	set_amr_state(AmrState.IDLE)
	_update_dev_status_label()

func _unhandled_input(event: InputEvent) -> void:
	if not is_manual_control or _is_arm_tweening:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey

		# [E] Key: State Machine Driver
		if key.keycode == KEY_E:
			match arm_motion_state:
				ArmMotionState.STATIONARY:
					prepare_arm_for_pickup()
					get_viewport().set_input_as_handled()
				ArmMotionState.PREPARING, ArmMotionState.AIMING_TIER:
					return_arm_to_stationary()
					get_viewport().set_input_as_handled()
				ArmMotionState.GRIPPED:
					stow_box_to_tray()
					get_viewport().set_input_as_handled()

		# [1, 2, 3, 4] Keys: Select Rack Tier
		elif key.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
			if arm_motion_state == ArmMotionState.PREPARING or arm_motion_state == ArmMotionState.AIMING_TIER:
				var tier: int = 1
				match key.keycode:
					KEY_1: tier = 1
					KEY_2: tier = 2
					KEY_3: tier = 3
					KEY_4: tier = 4
				aim_arm_at_tier(tier)
				get_viewport().set_input_as_handled()

		# [F] Key: Pick up Box
		elif key.keycode == KEY_F:
			if arm_motion_state == ArmMotionState.AIMING_TIER or arm_motion_state == ArmMotionState.PREPARING:
				execute_pick_attempt()
				get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if is_manual_control:
		_process_manual_driving(delta)

func _process_manual_driving(delta: float) -> void:
	var move_input: float = 0.0
	var turn_input: float = 0.0
	var is_braking: bool = Input.is_key_pressed(KEY_SPACE)

	# Only allow driving when arm is not extending/stowing
	if not _is_arm_tweening:
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
		if not _was_braking:
			SoundManager.play_spatial(self, SoundManager.sfx_brake, -4.0)
		_was_braking = true
		_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, linear_deceleration * 2.0 * delta)
		set_amr_state(AmrState.BLOCKED_SAFETY)
	else:
		_was_braking = false
		if abs(move_input) > 0.01:
			var target_v: float = move_input * max_speed
			_manual_linear_vel = move_toward(_manual_linear_vel, target_v, linear_acceleration * delta)
			set_amr_state(AmrState.MOVING)
		else:
			_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, linear_deceleration * delta)
			if abs(_manual_linear_vel) < 0.05:
				_manual_linear_vel = 0.0
				if not _is_arm_tweening and arm_motion_state == ArmMotionState.STATIONARY:
					set_amr_state(AmrState.IDLE)

	# Forward translation (-transform.basis.z is forward in Godot 3D)
	if abs(_manual_linear_vel) > 0.01:
		var forward_vec: Vector3 = -global_transform.basis.z
		global_position += forward_vec * _manual_linear_vel * delta

	# Floor boundary safety clamp
	global_position.x = clamp(global_position.x, -33.0, 33.0)
	global_position.z = clamp(global_position.z, -35.0, 32.0)

	current_speed = abs(_manual_linear_vel)
	_update_dev_status_label()

func _update_dev_status_label() -> void:
	if label_status:
		label_status.text = "%s [DEV BOT]\n⚡ %.0f%% | %.1f m/s\n%s\nTray: %d box(es)" % [
			robot_id,
			battery_level,
			current_speed,
			_arm_status_text,
			stowed_box_count
		]

func _find_nearest_shelf() -> ShelfPod:
	var nodes = get_tree().get_nodes_in_group("shelf_pods")
	var nearest: ShelfPod = null
	var min_dist: float = 5.0
	for node in nodes:
		if node is ShelfPod:
			var d: float = global_position.distance_to(node.global_position)
			if d < min_dist:
				min_dist = d
				nearest = node
	return nearest

func prepare_arm_for_pickup() -> void:
	if _is_arm_tweening:
		return
	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.PREPARING
	set_amr_state(AmrState.LIFTING)
	SoundManager.play_spatial(self, SoundManager.sfx_arm_prepare, -1.0)

	# Detect whether nearest rack is to Left or Right
	var shelf: ShelfPod = _find_nearest_shelf()
	if shelf:
		var to_shelf: Vector3 = shelf.global_position - global_position
		var local_shelf: Vector3 = global_transform.basis.inverse() * to_shelf
		arm_reach_side = -1.0 if local_shelf.x < 0.0 else 1.0
	else:
		arm_reach_side = 1.0

	_arm_status_text = "READY: [1-4] Select Tier | [E] Fold"
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(arm, "rotation:y", deg_to_rad(90.0 * arm_reach_side), 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", deg_to_rad(-35.0), 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", deg_to_rad(50.0), 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", deg_to_rad(-15.0), 0.35)

	tween.finished.connect(func():
		_is_arm_tweening = false
		aim_arm_at_tier(1)
	)

func aim_arm_at_tier(tier: int) -> void:
	selected_tier = clamp(tier, 1, 4)
	arm_motion_state = ArmMotionState.AIMING_TIER
	_is_arm_tweening = true

	# Play audio with slightly rising pitch based on tier height
	SoundManager.play_spatial(self, SoundManager.sfx_tier_select, 0.0, 0.85 + float(tier) * 0.12)

	var shoulder_angle: float = 0.0
	var elbow_angle: float = 0.0
	var wrist_angle: float = 0.0

	# Tier 1 is lowest floor (h=0.62m), Tier 4 is top floor (h=2.30m)
	match selected_tier:
		1: # Floor level (lowest)
			shoulder_angle = deg_to_rad(-68.0)
			elbow_angle = deg_to_rad(88.0)
			wrist_angle = deg_to_rad(-20.0)
		2: # Mid-low level
			shoulder_angle = deg_to_rad(-46.0)
			elbow_angle = deg_to_rad(65.0)
			wrist_angle = deg_to_rad(-19.0)
		3: # Mid-high level
			shoulder_angle = deg_to_rad(-24.0)
			elbow_angle = deg_to_rad(42.0)
			wrist_angle = deg_to_rad(-18.0)
		4: # Top rack floor (highest)
			shoulder_angle = deg_to_rad(-2.0)
			elbow_angle = deg_to_rad(20.0)
			wrist_angle = deg_to_rad(-18.0)

	_arm_status_text = "Tier %d Aimed: [F] Pick | [1-4] Tier | [E] Fold" % selected_tier
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(arm, "rotation:y", deg_to_rad(90.0 * arm_reach_side), 0.28)
	tween.parallel().tween_property(shoulder, "rotation:x", shoulder_angle, 0.28)
	tween.parallel().tween_property(elbow, "rotation:x", elbow_angle, 0.28)
	tween.parallel().tween_property(wrist, "rotation:x", wrist_angle, 0.28)

	tween.finished.connect(func():
		_is_arm_tweening = false
	)

func execute_pick_attempt() -> void:
	if _is_arm_tweening:
		return
	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.PICKING
	_arm_status_text = "Picking Tier %d..." % selected_tier
	_update_dev_status_label()

	var base_shoulder: float = shoulder.rotation.x
	var base_elbow: float = elbow.rotation.x
	var extend_shoulder: float = base_shoulder - deg_to_rad(8.0)
	var extend_elbow: float = base_elbow + deg_to_rad(14.0)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 1. Forward reach extension into shelf bay
	tween.tween_property(shoulder, "rotation:x", extend_shoulder, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", extend_elbow, 0.35)

	# 2. Collision / box pick check
	tween.tween_callback(func():
		var shelf: ShelfPod = _find_nearest_shelf()
		var picked: Dictionary = {"found": false}
		if shelf and global_position.distance_to(shelf.global_position) <= 3.8:
			var grip_pos: Vector3 = wrist.global_position
			picked = shelf.pick_tote(selected_tier, grip_pos)

		if picked.get("found", false):
			has_gripped_box = true
			_current_box_material = picked.get("material", null)
			if gripped_box:
				if _current_box_material:
					gripped_box.material_override = _current_box_material
				gripped_box.visible = true
		else:
			has_gripped_box = false
	)

	tween.tween_interval(0.2)
	# 3. Retract back to aimed pose
	tween.tween_property(shoulder, "rotation:x", base_shoulder, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", base_elbow, 0.35)

	tween.finished.connect(func():
		_is_arm_tweening = false
		if has_gripped_box:
			arm_motion_state = ArmMotionState.GRIPPED
			_arm_status_text = "📦 Box Gripped! Press [E] to stow in tray"
			SoundManager.play_spatial(self, SoundManager.sfx_box_pick, +2.0)
		else:
			arm_motion_state = ArmMotionState.AIMING_TIER
			_arm_status_text = "⚠️ No box reached. [1-4] Tier | [E] Fold"
			SoundManager.play_spatial(self, SoundManager.sfx_cancel, -3.0)
		_update_dev_status_label()
	)

func stow_box_to_tray() -> void:
	if _is_arm_tweening:
		return
	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.STOWING
	_arm_status_text = "Stowing box into cargo tray..."
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# 1. Swivel backwards 180 degrees towards rear tray
	tween.tween_property(arm, "rotation:y", deg_to_rad(180.0), 0.45)
	tween.parallel().tween_property(shoulder, "rotation:x", deg_to_rad(-45.0), 0.45)
	tween.parallel().tween_property(elbow, "rotation:x", deg_to_rad(75.0), 0.45)
	tween.parallel().tween_property(wrist, "rotation:x", deg_to_rad(-30.0), 0.45)

	# 2. Lower onto tray bed
	tween.tween_property(shoulder, "rotation:x", deg_to_rad(-55.0), 0.25)
	tween.parallel().tween_property(elbow, "rotation:x", deg_to_rad(90.0), 0.25)

	# 3. Release box to tray
	tween.tween_callback(func():
		if gripped_box:
			gripped_box.visible = false
		if tray_box:
			if _current_box_material:
				tray_box.material_override = _current_box_material
			tray_box.visible = true
		stowed_box_count += 1
		has_gripped_box = false
		SoundManager.play_spatial(self, SoundManager.sfx_box_stow, +1.0)
	)

	tween.tween_interval(0.12)

	# 4. Fold back to stationary home travel pose
	tween.tween_property(arm, "rotation:y", 0.0, 0.4)
	tween.parallel().tween_property(shoulder, "rotation:x", deg_to_rad(-25.0), 0.4)
	tween.parallel().tween_property(elbow, "rotation:x", deg_to_rad(45.0), 0.4)
	tween.parallel().tween_property(wrist, "rotation:x", deg_to_rad(-20.0), 0.4)

	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "📦 Box Stowed! [WASD] Drive | [E] Pick again"
		_update_dev_status_label()
	)

func return_arm_to_stationary() -> void:
	if _is_arm_tweening:
		return
	_is_arm_tweening = true
	_arm_status_text = "Folding arm to stationary..."
	_update_dev_status_label()
	SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)

	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(arm, "rotation:y", 0.0, 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", deg_to_rad(-25.0), 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", deg_to_rad(45.0), 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", deg_to_rad(-20.0), 0.35)

	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "[WASD] Drive | [E] Prep Arm"
		_update_dev_status_label()
	)

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
	var attach_target = cargo_tray if cargo_tray else self
	var tween: Tween = pod.lift_by_amr(attach_target)
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
