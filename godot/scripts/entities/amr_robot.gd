class_name AmrRobot
extends CharacterBody3D

## Autonomous Mobile Robot (AMR) designed for smart warehouse Goods-to-Person logistics.
## Features elevating turntable, multi-color state LED ring, rotating LiDAR, and VDA 5050 state reporting.
## Equipped with 4-DOF Articulated Robotic Arm with analytical 3D IK, parallel two-finger clamping gripper,
## and dual-slot physical cargo tray with retention guardrails and Area3D payload presence sensors.

enum AmrState {
	IDLE = 0,
	MOVING = 1,
	YIELDING = 2,
	BLOCKED_SAFETY = 3,
	LIFTING = 4,
	CHARGING = 5
}

enum ArmMotionState {
	STATIONARY,
	TARGETING,
	PRE_GRASP,
	INSERTING,
	CLAMPING,
	RETRACTING,
	HELD_READY,
	STOWING,
	PLACING
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
@export var linear_acceleration: float = 24.0
@export var linear_deceleration: float = 32.0
@export var turn_speed: float = 3.2

@onready var arm: Node3D = $RoboticArm
@onready var shoulder: Node3D = $RoboticArm/ShoulderJoint
@onready var elbow: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint
@onready var wrist: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint
@onready var finger_left: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/FingerLeft
@onready var finger_right: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/FingerRight
@onready var gripped_socket: Node3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/GrippedBoxSocket

@onready var arm_base_body: AnimatableBody3D = $RoboticArm/ArmBaseBody
@onready var boom_body: AnimatableBody3D = $RoboticArm/ShoulderJoint/BoomBody
@onready var forearm_body: AnimatableBody3D = $RoboticArm/ShoulderJoint/ElbowJoint/ForearmBody
@onready var gripper_body: AnimatableBody3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/GripperBody
@onready var finger_left_body: AnimatableBody3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/FingerLeft/FingerLeftBody
@onready var finger_right_body: AnimatableBody3D = $RoboticArm/ShoulderJoint/ElbowJoint/WristJoint/FingerRight/FingerRightBody

@onready var cargo_tray: Node3D = $Chassis/CargoTray
@onready var tray_body: AnimatableBody3D = $Chassis/CargoTray/TrayBody
@onready var slot_1_marker: Marker3D = $Chassis/CargoTray/Slot1Marker
@onready var slot_2_marker: Marker3D = $Chassis/CargoTray/Slot2Marker
@onready var slot_1_sensor: Area3D = $Chassis/CargoTray/Slot1Sensor
@onready var slot_2_sensor: Area3D = $Chassis/CargoTray/Slot2Sensor

@onready var side_strip_left: MeshInstance3D = $Chassis/SideLedStripLeft
@onready var side_strip_right: MeshInstance3D = $Chassis/SideLedStripRight
@onready var target_reticle: Node3D = $TargetReticle
@onready var reticle_ring: MeshInstance3D = $TargetReticle/ReticleRing
@onready var label_status: Label3D = $StatusBadge

# Compact Folded Rest Pose Constants
const REST_ARM_YAW: float = 0.0
const REST_SHOULDER_PITCH: float = 0.0  # Upright mast safely behind front bumper (z = -0.42m)
const REST_ELBOW_PITCH: float = 0.0     # Aligned mast
const REST_WRIST_PITCH: float = 0.0     # Level gripper
const REST_FINGER_SPAN: float = 0.16    # Neatly closed parking width

var current_state: AmrState = AmrState.IDLE
var arm_motion_state: ArmMotionState = ArmMotionState.STATIONARY
var carried_pod: ShelfPod = null
var current_speed: float = 0.0
var _manual_linear_vel: float = 0.0
var _prev_linear_vel: float = 0.0
var _chassis_accel: float = 0.0
var _arm_idle_time: float = 0.0
var _drive_vib_time: float = 0.0
var _led_material: StandardMaterial3D
var _reticle_material: StandardMaterial3D

var active_target_box: ToteBox = null
var held_box: ToteBox = null
var _is_arm_tweening: bool = false
var _was_braking: bool = false
var _arm_status_text: String = "[WASD] Drive | Click/E: Target Box"
var is_rl_control: bool = false
var _rl_target_v_lin: float = 0.0
var _rl_target_v_ang: float = 0.0
var _manual_angular_vel: float = 0.0
var last_arm_hit: String = ""
var arm_tween_speed_scale: float = 1.0
var _current_arm_tween: Tween = null

func _ready() -> void:
	_led_material = StandardMaterial3D.new()
	_led_material.roughness = 0.2
	_led_material.emission_enabled = true
	if side_strip_left:
		side_strip_left.set_surface_override_material(0, _led_material)
	if side_strip_right:
		side_strip_right.set_surface_override_material(0, _led_material)

	_reticle_material = StandardMaterial3D.new()
	_reticle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reticle_material.albedo_color = Color(0.0, 0.9, 1.0, 0.9)
	if reticle_ring:
		reticle_ring.set_surface_override_material(0, _reticle_material)

	if target_reticle:
		target_reticle.visible = false

	# Initial folded resting pose
	_fold_arm_to_home_instant()

	set_amr_state(AmrState.IDLE)
	_update_dev_status_label()

func _process(_delta: float) -> void:
	if is_manual_control:
		_update_targeting_reticle()

## Physical Sensor & Scene Queries for Payload Presence in Cargo Tray
func get_slot_box(slot_idx: int) -> ToteBox:
	var marker: Marker3D = slot_1_marker if slot_idx == 0 else slot_2_marker
	if cargo_tray:
		for child in cargo_tray.get_children():
			if child is ToteBox and is_instance_valid(child) and child != held_box and child.visible:
				if marker:
					if child.position.distance_to(marker.position) < 0.35:
						return child
				else:
					return child
	var sensor: Area3D = slot_1_sensor if slot_idx == 0 else slot_2_sensor
	if sensor:
		for body in sensor.get_overlapping_bodies():
			if body is ToteBox and is_instance_valid(body) and body != held_box and body.visible:
				return body
	return null

func is_slot_occupied(slot_idx: int) -> bool:
	return get_slot_box(slot_idx) != null

func get_stowed_box_count() -> int:
	var count: int = 0
	if is_slot_occupied(0): count += 1
	if is_slot_occupied(1): count += 1
	return count

func get_first_empty_slot() -> int:
	if not is_slot_occupied(0):
		return 0
	if not is_slot_occupied(1):
		return 1
	return -1

func _update_targeting_reticle() -> void:
	if not target_reticle:
		return

	if active_target_box == null or not is_instance_valid(active_target_box) or not active_target_box.visible:
		target_reticle.visible = false
		return

	target_reticle.visible = true
	target_reticle.global_position = active_target_box.global_position + Vector3(0.0, 0.02, 0.0)

	# Calculate distance strictly from the arm's shoulder pivot joint
	var dist_to_shoulder: float = shoulder.global_position.distance_to(active_target_box.global_position)
	var local_target: Vector3 = arm.to_local(active_target_box.global_position)
	var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)

	if ik.success:
		if _reticle_material:
			_reticle_material.albedo_color = Color(0.0, 0.95, 1.0, 0.95)
		if arm_motion_state in [ArmMotionState.STATIONARY, ArmMotionState.TARGETING]:
			_arm_status_text = "🎯 Ready (%.2fm to arm) | [E] Pick | [Esc] Cancel" % dist_to_shoulder
	else:
		if _reticle_material:
			_reticle_material.albedo_color = Color(1.0, 0.2, 0.2, 0.95)
		if arm_motion_state in [ArmMotionState.STATIONARY, ArmMotionState.TARGETING]:
			_arm_status_text = "⚠️ Out of Reach (%.1fm > 2.15m) | [Esc] Cancel" % dist_to_shoulder

	_update_dev_status_label()

func _unhandled_input(event: InputEvent) -> void:
	if not is_manual_control:
		return

	# 1. 3D Viewport Mouse Click on ToteBox
	if event is InputEventMouseButton and event.pressed and not event.is_echo():
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not _is_arm_tweening:
			_handle_mouse_pick_raycast()

	# 2. Keyboard Control Keys
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey

		if key.keycode == KEY_ESCAPE and not _is_arm_tweening:
			cancel_arm_to_stationary()
			get_viewport().set_input_as_handled()

		elif key.keycode == KEY_E and not _is_arm_tweening:
			match arm_motion_state:
				ArmMotionState.STATIONARY, ArmMotionState.TARGETING:
					_handle_pick_command()
					get_viewport().set_input_as_handled()
				ArmMotionState.HELD_READY:
					execute_dynamic_stow()
					get_viewport().set_input_as_handled()

		elif key.keycode == KEY_G and not _is_arm_tweening:
			if arm_motion_state == ArmMotionState.HELD_READY:
				execute_dynamic_place()
				get_viewport().set_input_as_handled()

func cancel_arm_to_stationary() -> void:
	active_target_box = null
	if target_reticle:
		target_reticle.visible = false

	if held_box == null:
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		_is_arm_tweening = true
		var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(arm, "rotation:y", REST_ARM_YAW, 0.35)
		tween.parallel().tween_property(shoulder, "rotation:x", REST_SHOULDER_PITCH, 0.35)
		tween.parallel().tween_property(elbow, "rotation:x", REST_ELBOW_PITCH, 0.35)
		tween.parallel().tween_property(wrist, "rotation:x", REST_WRIST_PITCH, 0.35)
		if finger_left: tween.parallel().tween_property(finger_left, "position:x", -REST_FINGER_SPAN, 0.30)
		if finger_right: tween.parallel().tween_property(finger_right, "position:x", REST_FINGER_SPAN, 0.30)
		tween.finished.connect(func():
			_is_arm_tweening = false
			arm_motion_state = ArmMotionState.STATIONARY
			set_amr_state(AmrState.IDLE)
			_arm_status_text = "[WASD] Drive | Click/E: Target Box"
			_update_dev_status_label()
		)
	else:
		_arm_status_text = "📦 Box Gripped! [E] Stow in Tray | [G] Place on Floor"
		_update_dev_status_label()

func _handle_mouse_pick_raycast() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if not cam:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)
	var ray_length: float = 250.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * ray_length)
	query.collision_mask = 8 # Layer 4 = ToteBox (collision_layer 8)
	query.collide_with_bodies = true

	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	if result and result.has("collider"):
		var collider = result["collider"]
		if collider is ToteBox and is_instance_valid(collider) and collider.visible and collider.get_parent() != cargo_tray:
			select_target_box(collider)
			SoundManager.play_spatial(self, SoundManager.sfx_click, -1.0)

func select_target_box(box: ToteBox) -> void:
	active_target_box = box
	arm_motion_state = ArmMotionState.TARGETING
	_update_targeting_reticle()

func _find_nearest_tote_box() -> ToteBox:
	var nodes = get_tree().get_nodes_in_group("tote_boxes")
	var nearest: ToteBox = null
	var min_dist: float = 4.5
	for node in nodes:
		if node is ToteBox and is_instance_valid(node) and node.visible and node != held_box and node.get_parent() != cargo_tray:
			# Distance strictly from shoulder pivot
			var d: float = shoulder.global_position.distance_to(node.global_position)
			if d < min_dist:
				min_dist = d
				nearest = node
	return nearest

func _handle_pick_command() -> void:
	if active_target_box == null or not is_instance_valid(active_target_box):
		var nearest: ToteBox = _find_nearest_tote_box()
		if nearest:
			select_target_box(nearest)
		else:
			_arm_status_text = "⚠️ No ToteBox in range. Drive closer or click one."
			SoundManager.play_spatial(self, SoundManager.sfx_cancel, -3.0)
			_update_dev_status_label()
			return

	var local_target: Vector3 = arm.to_local(active_target_box.global_position)
	var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)

	if ik.success:
		execute_dynamic_pick(active_target_box)
	else:
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		_arm_status_text = "⚠️ Out of Reach (%.1fm > 2.15m) — Drive Closer" % ik.target_distance
		_update_dev_status_label()

func _get_world_root() -> Node:
	if get_tree().current_scene:
		return get_tree().current_scene
	var totes = get_tree().get_nodes_in_group("tote_boxes")
	if totes.size() > 0 and is_instance_valid(totes[0]):
		return totes[0].get_parent()
	return get_parent()

func execute_dynamic_pick(target_box: ToteBox) -> void:
	if _is_arm_tweening or not is_instance_valid(target_box):
		return
	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.PRE_GRASP
	set_amr_state(AmrState.LIFTING)
	SoundManager.play_spatial(self, SoundManager.sfx_arm_prepare, -1.0)

	var box_pos: Vector3 = target_box.global_position
	var is_on_shelf: bool = box_pos.y > 0.45

	# 1. Calculate staging and grasp waypoints with full collision clearance outside bay
	var staging_pos: Vector3
	if is_on_shelf:
		var dir_to_amr: Vector3 = (global_position - box_pos)
		dir_to_amr.y = 0.0
		if dir_to_amr.length_squared() > 0.01:
			dir_to_amr = dir_to_amr.normalized()
		else:
			dir_to_amr = -global_transform.basis.z
		# Pull back 0.48m so 26cm fingers are completely outside the front face of the 38cm box with 5cm margin
		# Plus +0.07m vertical clearance to guarantee the box base never drags across shelf plates during extraction
		var local_dist: float = arm.to_local(box_pos).length()
		var pullback: float = clampf(local_dist - 0.45, 0.42, 0.52)
		staging_pos = box_pos + dir_to_amr * pullback + Vector3(0.0, 0.07, 0.0)
	else:
		staging_pos = box_pos + Vector3(0.0, 0.35, 0.0)

	var ik_grasp = ArmIKSolver.solve_local(arm.to_local(box_pos))
	if not ik_grasp.success:
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		_arm_status_text = "⚠️ Kinematic Envelope Exception: Re-align AMR"
		_update_dev_status_label()
		return

	var ik_staging = ArmIKSolver.solve_local(arm.to_local(staging_pos))
	if not ik_staging.success:
		# Fallback: elevate staging slightly above grasp pose
		staging_pos = box_pos + Vector3(0.0, 0.16, 0.0)
		ik_staging = ArmIKSolver.solve_local(arm.to_local(staging_pos))
		if not ik_staging.success:
			ik_staging = ik_grasp

	_arm_status_text = "Stage 1: Pre-Grasp Staging outside bay..."
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_current_arm_tween = tween
	if arm_tween_speed_scale != 1.0:
		tween.set_speed_scale(arm_tween_speed_scale)

	# --- STAGE 1: Pre-Grasp Staging & Gripper Opening in Aisle ---
	# Open fingers wide to 68cm span WHILE OUTSIDE IN AISLE before any insertion into the bay
	tween.tween_property(arm, "rotation:y", ik_staging.base_yaw, 0.45)
	tween.parallel().tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.45)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.45)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.45)
	if finger_left: tween.parallel().tween_property(finger_left, "position:x", -0.34, 0.35)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.34, 0.35)

	# --- STAGE 2: Linear Horizontal Insertion into Bay ---
	# Open fingers slide cleanly along sides of box without touching or phasing through front face
	tween.tween_callback(func():
		arm_motion_state = ArmMotionState.INSERTING
		_arm_status_text = "Stage 2: Linear Insertion into bay..."
		_update_dev_status_label()
	)
	tween.tween_property(shoulder, "rotation:x", ik_grasp.shoulder_pitch, 0.38)
	tween.parallel().tween_property(elbow, "rotation:x", ik_grasp.elbow_pitch, 0.38)
	tween.parallel().tween_property(wrist, "rotation:x", ik_grasp.wrist_pitch, 0.38)

	# --- STAGE 3: Bilateral Clamping onto Box ---
	tween.tween_callback(func():
		arm_motion_state = ArmMotionState.CLAMPING
		_arm_status_text = "Stage 3: Clamping mechanical fingers..."
		_update_dev_status_label()
	)
	if finger_left: tween.tween_property(finger_left, "position:x", -0.29, 0.22)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.29, 0.22)

	# Grip lock assist: Socket the rigid body to end-effector
	tween.tween_callback(func():
		if is_instance_valid(target_box):
			held_box = target_box
			held_box.freeze = true
			held_box.linear_velocity = Vector3.ZERO
			held_box.angular_velocity = Vector3.ZERO

			# Reparent to socket to guarantee zero transit drift
			held_box.get_parent().remove_child(held_box)
			gripped_socket.add_child(held_box)
			held_box.transform = Transform3D.IDENTITY

			# Temporarily isolate collision with shelf during extraction so held box never levers against rack
			held_box.set_collision_mask_value(2, false)

			SoundManager.play_spatial(self, SoundManager.sfx_box_pick, +2.0)
	)

	# --- STAGE 3.5: Vertical Pre-Lift inside bay (+6cm) ---
	# Unseats box cleanly from shelf plate before horizontal retraction begins
	if is_on_shelf:
		var lift_target = box_pos + Vector3(0.0, 0.06, 0.0)
		var ik_lift = ArmIKSolver.solve_local(arm.to_local(lift_target))
		if ik_lift.success:
			tween.tween_interval(0.05)
			tween.tween_property(shoulder, "rotation:x", ik_lift.shoulder_pitch, 0.18)
			tween.parallel().tween_property(elbow, "rotation:x", ik_lift.elbow_pitch, 0.18)
			tween.parallel().tween_property(wrist, "rotation:x", ik_lift.wrist_pitch, 0.18)

	# --- STAGE 4: Linear Retraction with Box back into Aisle ---
	# Pull box straight back along horizontal elevated staging axis into open aisle before folding
	tween.tween_interval(0.06)
	tween.tween_callback(func():
		arm_motion_state = ArmMotionState.RETRACTING
		_arm_status_text = "Stage 4: Retracting into aisle..."
		_update_dev_status_label()
	)
	tween.tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.40)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.40)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.40)

	# --- STAGE 5: Held Ready in Aisle ---
	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.HELD_READY
		active_target_box = null
		if target_reticle:
			target_reticle.visible = false
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "📦 Box Gripped! [E] Stow in Tray | [G] Place | [Esc] Reset"
		_update_dev_status_label()
	)

func execute_dynamic_stow() -> void:
	if _is_arm_tweening or held_box == null:
		return

	# Query physical Area3D sensors for first available slot
	var target_slot_idx: int = get_first_empty_slot()
	if target_slot_idx == -1:
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		_arm_status_text = "⚠️ Cargo Tray Full (2/2) — Press [G] to Place"
		_update_dev_status_label()
		return

	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.STOWING
	set_amr_state(AmrState.LIFTING)

	var slot_marker: Marker3D = slot_1_marker if target_slot_idx == 0 else slot_2_marker
	var slot_world: Vector3 = slot_marker.global_position
	# High-clearance waypoint (+0.52m) so bottom of carried box (height 0.32m) clears tray rails (0.12m) by 20cm
	var slot_staging_world: Vector3 = slot_world + Vector3(0.0, 0.52, 0.0)

	var ik_staging = ArmIKSolver.solve_local(arm.to_local(slot_staging_world))
	var ik_place = ArmIKSolver.solve_local(arm.to_local(slot_world))

	_arm_status_text = "Stowing into Tray Slot %d..." % (target_slot_idx + 1)
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_current_arm_tween = tween
	if arm_tween_speed_scale != 1.0:
		tween.set_speed_scale(arm_tween_speed_scale)

	# 1. Swivel 180 degrees backwards over active slot at high altitude (above tray rails)
	tween.tween_property(arm, "rotation:y", ik_staging.base_yaw, 0.45)
	tween.parallel().tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.45)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.45)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.45)

	# 2. Lower cleanly straight down into slot bed (box bottom sits flush on tray floor)
	tween.tween_property(shoulder, "rotation:x", ik_place.shoulder_pitch, 0.30)
	tween.parallel().tween_property(elbow, "rotation:x", ik_place.elbow_pitch, 0.30)
	tween.parallel().tween_property(wrist, "rotation:x", ik_place.wrist_pitch, 0.30)

	# 3. Open fingers and release payload cleanly into tray bed
	if finger_left: tween.tween_property(finger_left, "position:x", -0.34, 0.18)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.34, 0.18)

	tween.tween_callback(func():
		if is_instance_valid(held_box):
			# Parent to cargo_tray so it moves with the vehicle with 0% floating or jitter
			held_box.get_parent().remove_child(held_box)
			cargo_tray.add_child(held_box)
			held_box.position = slot_marker.position
			held_box.rotation = Vector3.ZERO
			held_box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			held_box.freeze = true
			held_box.sleeping = false
			held_box.set_collision_mask_value(2, true)
			add_collision_exception_with(held_box)
			held_box.add_collision_exception_with(self)
			held_box = null

			SoundManager.play_spatial(self, SoundManager.sfx_box_stow, +1.0)
	)

	# 4. Lift vertically straight UP back to high clearance before swiveling!
	# Prevents the gripper and fingers from dragging horizontally through the tray walls or divider!
	tween.tween_interval(0.08)
	tween.tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.28)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.28)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.28)

	# 5. Now safely high above the tray, swivel arm back to front and fold to rest pose
	tween.tween_property(arm, "rotation:y", REST_ARM_YAW, 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", REST_SHOULDER_PITCH, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", REST_ELBOW_PITCH, 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", REST_WRIST_PITCH, 0.35)
	if finger_left: tween.parallel().tween_property(finger_left, "position:x", -REST_FINGER_SPAN, 0.30)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", REST_FINGER_SPAN, 0.30)

	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "📦 Box Stowed (%d/2)! [WASD] Drive | Click/E: Pick" % get_stowed_box_count()
		_update_dev_status_label()
	)

func execute_dynamic_place() -> void:
	if _is_arm_tweening or held_box == null:
		return
	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.PLACING
	set_amr_state(AmrState.LIFTING)

	# Place directly onto floor in front of chassis
	var forward_dir: Vector3 = -global_transform.basis.z
	var place_floor_world: Vector3 = global_position + forward_dir * 0.95 + Vector3(0.0, 0.16, 0.0)
	var staging_world: Vector3 = place_floor_world + Vector3(0.0, 0.35, 0.0)

	var ik_staging = ArmIKSolver.solve_local(arm.to_local(staging_world))
	var ik_place = ArmIKSolver.solve_local(arm.to_local(place_floor_world))

	_arm_status_text = "Placing box onto floor..."
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 1. Move to staging above floor spot
	tween.tween_property(arm, "rotation:y", ik_staging.base_yaw, 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.35)

	# 2. Lower to floor
	tween.tween_property(shoulder, "rotation:x", ik_place.shoulder_pitch, 0.25)
	tween.parallel().tween_property(elbow, "rotation:x", ik_place.elbow_pitch, 0.25)
	tween.parallel().tween_property(wrist, "rotation:x", ik_place.wrist_pitch, 0.25)

	# 3. Open fingers & release
	if finger_left: tween.tween_property(finger_left, "position:x", -0.34, 0.18)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.34, 0.18)

	tween.tween_callback(func():
		if is_instance_valid(held_box):
			var final_world_tform: Transform3D = held_box.global_transform
			held_box.get_parent().remove_child(held_box)
			_get_world_root().add_child(held_box)
			held_box.global_transform = final_world_tform
			held_box.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			held_box.freeze = false
			held_box.sleeping = false
			PhysicsServer3D.body_set_state(held_box.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
			held_box.linear_velocity = Vector3(0.0, -0.35, 0.0)
			held_box.angular_velocity = Vector3.ZERO
			held_box = null

			SoundManager.play_spatial(self, SoundManager.sfx_box_stow, 0.0)
	)

	# 4. Lift vertically back up above placed box before folding!
	tween.tween_interval(0.08)
	tween.tween_property(shoulder, "rotation:x", ik_staging.shoulder_pitch, 0.28)
	tween.parallel().tween_property(elbow, "rotation:x", ik_staging.elbow_pitch, 0.28)
	tween.parallel().tween_property(wrist, "rotation:x", ik_staging.wrist_pitch, 0.28)

	# 5. Fold home to compact rest pose
	tween.tween_property(arm, "rotation:y", REST_ARM_YAW, 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", REST_SHOULDER_PITCH, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", REST_ELBOW_PITCH, 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", REST_WRIST_PITCH, 0.35)
	if finger_left: tween.parallel().tween_property(finger_left, "position:x", -REST_FINGER_SPAN, 0.30)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", REST_FINGER_SPAN, 0.30)

	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "Box Placed! [WASD] Drive | Click/E: Pick"
		_update_dev_status_label()
	)

func execute_dynamic_unstow_and_place(target_deck_world: Vector3) -> bool:
	if _is_arm_tweening:
		return false

	# Locate box in cargo tray or in gripped socket
	var box_to_place: ToteBox = null
	if held_box != null:
		box_to_place = held_box
	elif cargo_tray:
		for child in cargo_tray.get_children():
			if child is ToteBox:
				box_to_place = child
				break

	if not box_to_place or not is_instance_valid(box_to_place):
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		return false

	_is_arm_tweening = true
	arm_motion_state = ArmMotionState.PLACING
	set_amr_state(AmrState.LIFTING)

	# High clearance staging waypoint above conveyor deck (+0.28m)
	var deck_staging_world = target_deck_world + Vector3(0.0, 0.28, 0.0)
	var ik_deck_staging = ArmIKSolver.solve_local(arm.to_local(deck_staging_world))
	var ik_deck_place = ArmIKSolver.solve_local(arm.to_local(target_deck_world))

	if not ik_deck_place.success or not ik_deck_staging.success:
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
		_arm_status_text = "⚠️ Kinematic Reach Exception at Conveyor"
		_update_dev_status_label()
		return false

	_arm_status_text = "Unstowing & Placing box on conveyor..."
	_update_dev_status_label()

	var tween: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_current_arm_tween = tween
	if arm_tween_speed_scale != 1.0:
		tween.set_speed_scale(arm_tween_speed_scale)

	# If box is already held in socket, skip tray re-grasp and proceed directly to deck placement
	if held_box == null:
		var slot_world = box_to_place.global_position
		var slot_staging_world = slot_world + Vector3(0.0, 0.52, 0.0)
		var ik_tray_staging = ArmIKSolver.solve_local(arm.to_local(slot_staging_world))
		var ik_tray_grip = ArmIKSolver.solve_local(arm.to_local(slot_world))

		# 1. Open fingers & swivel 180 degrees backward over tray slot
		tween.tween_property(arm, "rotation:y", ik_tray_staging.base_yaw, 0.40)
		tween.parallel().tween_property(shoulder, "rotation:x", ik_tray_staging.shoulder_pitch, 0.40)
		tween.parallel().tween_property(elbow, "rotation:x", ik_tray_staging.elbow_pitch, 0.40)
		tween.parallel().tween_property(wrist, "rotation:x", ik_tray_staging.wrist_pitch, 0.40)
		if finger_left: tween.parallel().tween_property(finger_left, "position:x", -0.34, 0.30)
		if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.34, 0.30)

		# 2. Lower fingers onto box in tray
		tween.tween_property(shoulder, "rotation:x", ik_tray_grip.shoulder_pitch, 0.25)
		tween.parallel().tween_property(elbow, "rotation:x", ik_tray_grip.elbow_pitch, 0.25)
		tween.parallel().tween_property(wrist, "rotation:x", ik_tray_grip.wrist_pitch, 0.25)

		# 3. Clamp fingers & socket box
		if finger_left: tween.tween_property(finger_left, "position:x", -0.29, 0.18)
		if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.29, 0.18)

		tween.tween_callback(func():
			if is_instance_valid(box_to_place):
				held_box = box_to_place
				held_box.freeze = true
				if held_box.get_parent():
					held_box.get_parent().remove_child(held_box)
				gripped_socket.add_child(held_box)
				held_box.transform = Transform3D.IDENTITY
				held_box.set_collision_mask_value(2, false)
				SoundManager.play_spatial(self, SoundManager.sfx_box_pick, +1.0)
		)

		# 4. Lift vertically back up above tray rails
		tween.tween_interval(0.05)
		tween.tween_property(shoulder, "rotation:x", ik_tray_staging.shoulder_pitch, 0.25)
		tween.parallel().tween_property(elbow, "rotation:x", ik_tray_staging.elbow_pitch, 0.25)
		tween.parallel().tween_property(wrist, "rotation:x", ik_tray_staging.wrist_pitch, 0.25)

	# 5. Swivel forward 180 degrees to conveyor deck staging waypoint
	tween.tween_property(arm, "rotation:y", ik_deck_staging.base_yaw, 0.45)
	tween.parallel().tween_property(shoulder, "rotation:x", ik_deck_staging.shoulder_pitch, 0.45)
	tween.parallel().tween_property(elbow, "rotation:x", ik_deck_staging.elbow_pitch, 0.45)
	tween.parallel().tween_property(wrist, "rotation:x", ik_deck_staging.wrist_pitch, 0.45)

	# 6. Lower cleanly flush onto conveyor deck
	tween.tween_property(shoulder, "rotation:x", ik_deck_place.shoulder_pitch, 0.28)
	tween.parallel().tween_property(elbow, "rotation:x", ik_deck_place.elbow_pitch, 0.28)
	tween.parallel().tween_property(wrist, "rotation:x", ik_deck_place.wrist_pitch, 0.28)

	# 7. Open fingers & release payload onto conveyor table
	if finger_left: tween.tween_property(finger_left, "position:x", -0.34, 0.18)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", 0.34, 0.18)

	tween.tween_callback(func():
		if is_instance_valid(held_box):
			var final_world_tform: Transform3D = held_box.global_transform
			held_box.get_parent().remove_child(held_box)
			_get_world_root().add_child(held_box)
			held_box.global_transform = final_world_tform
			held_box.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			held_box.freeze = false
			held_box.sleeping = false
			held_box.set_collision_mask_value(2, true)
			PhysicsServer3D.body_set_state(held_box.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
			held_box.linear_velocity = Vector3(0.0, -0.15, 0.0)
			held_box.angular_velocity = Vector3.ZERO
			remove_collision_exception_with(held_box)
			held_box.remove_collision_exception_with(self)
			held_box = null
			SoundManager.play_spatial(self, SoundManager.sfx_box_stow, +1.0)
	)

	# 8. Lift vertically back up above placed box
	tween.tween_interval(0.06)
	tween.tween_property(shoulder, "rotation:x", ik_deck_staging.shoulder_pitch, 0.25)
	tween.parallel().tween_property(elbow, "rotation:x", ik_deck_staging.elbow_pitch, 0.25)
	tween.parallel().tween_property(wrist, "rotation:x", ik_deck_staging.wrist_pitch, 0.25)

	# 9. Fold arm home to compact rest pose
	tween.tween_property(arm, "rotation:y", REST_ARM_YAW, 0.35)
	tween.parallel().tween_property(shoulder, "rotation:x", REST_SHOULDER_PITCH, 0.35)
	tween.parallel().tween_property(elbow, "rotation:x", REST_ELBOW_PITCH, 0.35)
	tween.parallel().tween_property(wrist, "rotation:x", REST_WRIST_PITCH, 0.35)
	if finger_left: tween.parallel().tween_property(finger_left, "position:x", -REST_FINGER_SPAN, 0.30)
	if finger_right: tween.parallel().tween_property(finger_right, "position:x", REST_FINGER_SPAN, 0.30)

	tween.finished.connect(func():
		_is_arm_tweening = false
		arm_motion_state = ArmMotionState.STATIONARY
		set_amr_state(AmrState.IDLE)
		_arm_status_text = "📦 Box Placed on Conveyor! Mission Complete"
		_update_dev_status_label()
	)
	return true

func _fold_arm_to_home_instant() -> void:
	if arm: arm.rotation.y = REST_ARM_YAW
	if shoulder: shoulder.rotation.x = REST_SHOULDER_PITCH
	if elbow: elbow.rotation.x = REST_ELBOW_PITCH
	if wrist: wrist.rotation.x = REST_WRIST_PITCH
	if finger_left: finger_left.position.x = -REST_FINGER_SPAN
	if finger_right: finger_right.position.x = REST_FINGER_SPAN

func _physics_process(delta: float) -> void:
	if is_manual_control:
		_process_manual_driving(delta)
	elif is_rl_control:
		_process_rl_driving(delta)
	else:
		if not is_on_floor():
			velocity.y -= 9.81 * delta
			move_and_slide()

	_check_and_resolve_arm_collisions(delta)
	_update_inactive_arm_animation(delta)
	_update_stowed_cargo_dynamics(delta)

## Direct velocity and rotation control for Reinforcement Learning
func set_rl_control(v_lin: float, v_ang: float) -> void:
	is_rl_control = true
	is_manual_control = false
	_rl_target_v_lin = v_lin
	_rl_target_v_ang = v_ang

## Trigger pick or stow action dynamically via RL policy
func trigger_rl_action(target_box: ToteBox = null) -> bool:
	if _is_arm_tweening:
		return false
	if held_box == null:
		if target_box != null:
			active_target_box = target_box
		elif active_target_box == null:
			var boxes = get_tree().get_nodes_in_group("tote_boxes")
			var closest: ToteBox = null
			var min_dist: float = 999.0
			for b in boxes:
				if b is ToteBox and b.visible and b != held_box:
					var d = shoulder.global_position.distance_to(b.global_position)
					if d < min_dist:
						min_dist = d
						closest = b
			if closest and min_dist <= 2.2:
				active_target_box = closest
		if active_target_box:
			_handle_pick_command()
			return true
	elif arm_motion_state == ArmMotionState.HELD_READY:
		execute_dynamic_stow()
		return true
	return false

func _process_rl_driving(delta: float) -> void:
	if _is_arm_tweening:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_manual_angular_vel = _rl_target_v_ang
	rotate_y(_rl_target_v_ang * delta)

	# Active physical braking when decelerating, reversing, or stopping
	var accel_rate: float = linear_acceleration
	if abs(_rl_target_v_lin) < 0.05 or (_manual_linear_vel * _rl_target_v_lin < 0.0) or (abs(_rl_target_v_lin) < abs(_manual_linear_vel)):
		accel_rate = linear_deceleration * 1.5

	_manual_linear_vel = move_toward(_manual_linear_vel, _rl_target_v_lin, accel_rate * delta)
	if abs(_manual_linear_vel) < 0.03 and abs(_rl_target_v_lin) < 0.05:
		_manual_linear_vel = 0.0

	current_speed = abs(_manual_linear_vel)

	var forward: Vector3 = -global_transform.basis.z
	velocity.x = forward.x * _manual_linear_vel
	velocity.z = forward.z * _manual_linear_vel
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# Dynamic impact physics with RigidBody3D obstacles in RL mode
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is RigidBody3D:
			var impact_speed: float = abs(_manual_linear_vel)
			var impulse_dir: Vector3 = -col.get_normal()
			var contact_offset: Vector3 = col.get_position() - collider.global_position

			if collider is ToteBox:
				var impulse_mag: float = impact_speed * 140.0 + 40.0
				collider.apply_impulse(impulse_dir * impulse_mag * delta, contact_offset)
			elif collider is ShelfPod:
				var impulse_mag: float = impact_speed * 2000.0 + 400.0
				collider.apply_impulse(impulse_dir * impulse_mag * delta, contact_offset)

## Active Continuous Collision Detection & Contact Resolution for Robotic Arm
func _check_and_resolve_arm_collisions(_delta: float) -> void:
	if not is_inside_tree():
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space_state:
		return

	var arm_parts: Array[Dictionary] = [
		{"node": shoulder, "body": boom_body, "size": Vector3(0.14, 1.02, 0.16), "offset": Vector3(0, 0.51, 0)},
		{"node": elbow, "body": forearm_body, "size": Vector3(0.12, 0.86, 0.14), "offset": Vector3(0, 0.43, 0)},
		{"node": wrist, "body": gripper_body, "size": Vector3(0.28, 0.08, 0.14), "offset": Vector3(0, 0.04, 0)},
		{"node": finger_left, "body": finger_left_body, "size": Vector3(0.04, 0.26, 0.14), "offset": Vector3(0, 0.13, 0)},
		{"node": finger_right, "body": finger_right_body, "size": Vector3(0.04, 0.26, 0.14), "offset": Vector3(0, 0.13, 0)}
	]

	var self_rids: Array[RID] = [get_rid()]
	if tray_body: self_rids.append(tray_body.get_rid())
	if arm_base_body: self_rids.append(arm_base_body.get_rid())
	for part in arm_parts:
		if part["body"]:
			self_rids.append(part["body"].get_rid())
	if held_box and is_instance_valid(held_box):
		self_rids.append(held_box.get_rid())
	if cargo_tray:
		for child in cargo_tray.get_children():
			if child is CollisionObject3D:
				self_rids.append(child.get_rid())

	var forward_dir: Vector3 = -global_transform.basis.z

	for part in arm_parts:
		var joint_node: Node3D = part["node"]
		var body_node: AnimatableBody3D = part["body"]
		if not joint_node:
			continue

		var query_tf = joint_node.global_transform.translated_local(part["offset"])
		if body_node:
			body_node.global_transform = joint_node.global_transform

		var shape = BoxShape3D.new()
		shape.size = part["size"]

		var query = PhysicsShapeQueryParameters3D.new()
		query.shape_rid = shape.get_rid()
		# Collides with: ShelfPod (2), ToteBoxes (8), CargoTray (32)
		query.collision_mask = 2 | 8 | 32
		query.exclude = self_rids
		query.transform = query_tf

		var hits = space_state.intersect_shape(query, 6)
		for hit in hits:
			var collider = hit.collider
			if not is_instance_valid(collider) or collider == self or collider in self_rids:
				continue
			if collider.name == "ArenaFloor":
				continue

			var shape_idx = hit.get("shape", -1)
			last_arm_hit = "%s (shape %d) on %s at %s" % [collider.name, shape_idx, body_node.name if body_node else "arm", str(query_tf.origin)]

			# 1. Physics impulse transfer if hitting dynamic RigidBody3D (ToteBox or ShelfPod)
			if collider is RigidBody3D:
				var impact_speed: float = maxf(abs(_manual_linear_vel), 0.75)
				var contact_dir: Vector3 = (collider.global_position - query_tf.origin).normalized()
				if contact_dir.length_squared() < 0.01:
					contact_dir = forward_dir

				if collider is ToteBox and collider != held_box:
					var push_impulse: Vector3 = contact_dir * (collider.mass * (impact_speed * 1.5 + 0.4))
					collider.apply_central_impulse(push_impulse)
					collider.sleeping = false
				elif collider is ShelfPod:
					var push_impulse: Vector3 = contact_dir * (collider.mass * 0.06 * impact_speed)
					collider.apply_central_impulse(push_impulse)
					collider.sleeping = false

			# 2. Block AMR forward driving if arm is contacting obstacle ahead
			var arm_rel_fwd = forward_dir.dot(query_tf.origin - global_position)
			if arm_rel_fwd > 0.1:
				if _manual_linear_vel > 0.0:
					_manual_linear_vel = 0.0
					velocity.x = 0.0
					velocity.z = 0.0

## Dynamic Idle Breathing and Suspension Compliance for Inactive Resting Arm
func _update_inactive_arm_animation(delta: float) -> void:
	if arm_motion_state != ArmMotionState.STATIONARY or _is_arm_tweening:
		return

	_arm_idle_time += delta
	# Gentle mechanical breathing oscillation (0.24 Hz)
	var idle_sway: float = sin(_arm_idle_time * 1.5) * deg_to_rad(0.55)
	# Subtle inertial pitch reacting to chassis acceleration/braking
	var inertial_pitch: float = clampf(-_chassis_accel * 0.002, -deg_to_rad(1.8), deg_to_rad(1.8))

	if shoulder:
		shoulder.rotation.x = move_toward(shoulder.rotation.x, REST_SHOULDER_PITCH + idle_sway + inertial_pitch, 1.2 * delta)
	if elbow:
		elbow.rotation.x = move_toward(elbow.rotation.x, REST_ELBOW_PITCH - idle_sway * 0.5, 1.2 * delta)
	if wrist:
		wrist.rotation.x = move_toward(wrist.rotation.x, REST_WRIST_PITCH, 1.2 * delta)
	if arm:
		arm.rotation.y = move_toward(arm.rotation.y, REST_ARM_YAW, 2.0 * delta)
	if finger_left:
		finger_left.position.x = move_toward(finger_left.position.x, -REST_FINGER_SPAN, 0.8 * delta)
	if finger_right:
		finger_right.position.x = move_toward(finger_right.position.x, REST_FINGER_SPAN, 0.8 * delta)

## Natural Physical Micro-Inertia & Compliance for Stowed Cargo in Tray
func _update_stowed_cargo_dynamics(delta: float) -> void:
	_chassis_accel = (_manual_linear_vel - _prev_linear_vel) / maxf(delta, 0.001)
	_prev_linear_vel = _manual_linear_vel

	if abs(_manual_linear_vel) > 0.05:
		_drive_vib_time += delta * (14.0 + abs(_manual_linear_vel) * 2.0)
	else:
		_drive_vib_time = 0.0

	# Road/floor travel micro-vibration
	var vib_y: float = sin(_drive_vib_time) * 0.0012 * clampf(abs(_manual_linear_vel) / max_speed, 0.0, 1.0)
	# Inertial forward/backward shift inside the tray bed (-1.8cm to +1.8cm)
	var inertial_z: float = clampf(-_chassis_accel * 0.0014, -0.018, 0.018)
	# Subtle pitch compliance on acceleration and braking
	var inertial_pitch: float = clampf(-_chassis_accel * 0.0035, -deg_to_rad(2.0), deg_to_rad(2.0))
	# Subtle roll compliance on turns
	var turn_rate: float = Input.get_axis("ui_right", "ui_left") if is_manual_control else 0.0
	var roll_angle: float = clampf(turn_rate * deg_to_rad(1.4), -deg_to_rad(1.4), deg_to_rad(1.4))

	for slot_idx in [0, 1]:
		var marker: Marker3D = slot_1_marker if slot_idx == 0 else slot_2_marker
		if not marker: continue
		var box: ToteBox = get_slot_box(slot_idx)
		if box and is_instance_valid(box) and box.get_parent() == cargo_tray:
			var target_pos: Vector3 = marker.position + Vector3(0.0, vib_y, inertial_z)
			var target_rot: Vector3 = Vector3(inertial_pitch, 0.0, roll_angle)
			box.position = box.position.lerp(target_pos, 10.0 * delta)
			box.rotation = box.rotation.lerp(target_rot, 10.0 * delta)

func _process_manual_driving(delta: float) -> void:
	var move_input: float = 0.0
	var turn_input: float = 0.0
	var is_braking: bool = Input.is_key_pressed(KEY_SPACE)

	# Only allow driving when arm is not in picking or stowing sequence
	if not _is_arm_tweening:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move_input += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move_input -= 0.65

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
				if not _is_arm_tweening and arm_motion_state in [ArmMotionState.STATIONARY, ArmMotionState.TARGETING, ArmMotionState.HELD_READY]:
					set_amr_state(AmrState.IDLE)

	# Gravity
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	# Directional velocity in horizontal XZ plane (-transform.basis.z is forward in Godot 3D)
	var forward_vec: Vector3 = -global_transform.basis.z
	velocity.x = forward_vec.x * _manual_linear_vel
	velocity.z = forward_vec.z * _manual_linear_vel

	# Execute kinematic physics motion
	move_and_slide()

	# Dynamic impact physics with RigidBody3D obstacles
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is RigidBody3D:
			var impact_speed: float = abs(_manual_linear_vel)
			var impulse_dir: Vector3 = -col.get_normal()
			var contact_offset: Vector3 = col.get_position() - collider.global_position

			if collider is ToteBox:
				var impulse_mag: float = impact_speed * 140.0 + 40.0
				collider.apply_impulse(impulse_dir * impulse_mag * delta, contact_offset)
			elif collider is ShelfPod:
				var impulse_mag: float = impact_speed * 2000.0 + 400.0
				collider.apply_impulse(impulse_dir * impulse_mag * delta, contact_offset)

			# Severe crash: boxes realistically tumble forward out of the tray onto floor
			if impact_speed > 1.9:
				_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, 12.0 * delta)

				for slot_idx in [0, 1]:
					var s_box = get_slot_box(slot_idx)
					if s_box and is_instance_valid(s_box) and s_box.get_parent() == cargo_tray:
						var s_world_tform: Transform3D = s_box.global_transform
						cargo_tray.remove_child(s_box)
						_get_world_root().add_child(s_box)
						s_box.global_transform = s_world_tform
						s_box.freeze = false
						s_box.sleeping = false
						PhysicsServer3D.body_set_state(s_box.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)

						# Forward momentum transfer: carries vehicle speed over the tray lip
						var spill_vel: Vector3 = forward_vec * (impact_speed * 0.85) + Vector3(0.0, 0.35, 0.0) + impulse_dir * 0.2
						s_box.linear_velocity = spill_vel
						s_box.angular_velocity = Vector3(randf_range(1.5, 3.0), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))

	global_position.x = clamp(global_position.x, -40.0, 40.0)
	global_position.z = clamp(global_position.z, -40.0, 40.0)

	current_speed = abs(_manual_linear_vel)
	_update_dev_status_label()

func _update_dev_status_label() -> void:
	if label_status:
		if is_rl_control or not is_manual_control:
			label_status.visible = false
			return
		label_status.visible = true
		label_status.text = "%s [DEV BOT]\n⚡ %.0f%% | %.1f m/s\n%s\nTray: %d/2" % [
			robot_id,
			battery_level,
			current_speed,
			_arm_status_text,
			get_stowed_box_count()
		]

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
			state_text = "ARM MANIPULATION"
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

func reset_robot(spawn_pos: Vector3, spawn_rot_y: float = 0.0) -> void:
	global_position = spawn_pos
	rotation = Vector3(0.0, spawn_rot_y, 0.0)
	velocity = Vector3.ZERO
	_manual_linear_vel = 0.0
	_manual_angular_vel = 0.0
	current_speed = 0.0
	_was_braking = false
	_is_arm_tweening = false
	_rl_target_v_lin = 0.0
	_rl_target_v_ang = 0.0
	is_manual_control = false
	is_rl_control = true
	last_arm_hit = ""

	# Kill any running arm tween
	if _current_arm_tween and _current_arm_tween.is_valid():
		_current_arm_tween.kill()
		_current_arm_tween = null

	# Clear collision exceptions with all tote boxes
	var all_boxes = get_tree().get_nodes_in_group("tote_boxes")
	for b in all_boxes:
		if b is CollisionObject3D:
			remove_collision_exception_with(b)
			b.remove_collision_exception_with(self)

	# Release any gripped box
	if held_box and is_instance_valid(held_box):
		if held_box.get_parent() == gripped_socket:
			gripped_socket.remove_child(held_box)
			_get_world_root().add_child(held_box)
		held_box.freeze = false
	held_box = null

	# Unparent all stowed boxes in cargo tray back to world root
	if cargo_tray:
		for child in cargo_tray.get_children():
			if child is Node3D:
				cargo_tray.remove_child(child)
				_get_world_root().add_child(child)
				if child is RigidBody3D:
					child.freeze = false

	active_target_box = null

	if target_reticle:
		target_reticle.visible = false

	_fold_arm_to_home_instant()

	arm_motion_state = ArmMotionState.STATIONARY
	set_amr_state(AmrState.IDLE)
	_arm_status_text = "[WASD] Drive | Click/E: Target Box"
	_update_dev_status_label()
