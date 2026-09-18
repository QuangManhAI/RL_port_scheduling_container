class_name HumanControlAMR
extends AmrRobot

## Fully Controllable Human-Piloted AMR Entity for Environment & Physics Testing.
## Incorporates all Phase 07 / Phase 08 features:
##   - Dual-Slot Cargo Tray with active dynamic inertial sway
##   - 4-DOF 2.15m Reach Manipulator with Closed-Form IK and CCD swept collision avoidance
##   - Automated Shelf Extraction (Tiers 1-4) & Conveyor Deck Motorized Transport
##   - Multi-Perspective Chase Camera (3rd-Person, Overhead, Arm Close-up)
##   - Real-Time Interactive HUD with inventory, reachability telemetry, and control guide

@export var camera_distance: float = 4.2
@export var camera_height: float = 2.4
@export var sprint_multiplier: float = 1.6

var spring_arm: SpringArm3D
var chase_camera: Camera3D
var hud_canvas: CanvasLayer
var hud_label_info: Label
var hud_label_controls: Label
var camera_mode: int = 0 # 0 = Chase 3rd-Person, 1 = Top-down Tactical, 2 = Arm Close-up

func _ready() -> void:
	add_to_group("human_amr")
	is_manual_control = true
	is_rl_control = false
	robot_id = "HUMAN-PILOT-01"
	# Unpause physics so user can immediately drive and test
	get_tree().paused = false

	max_speed = 3.2
	linear_acceleration = 20.0
	linear_deceleration = 28.0
	turn_speed = 2.8

	super._ready()

	_setup_camera_rig()
	_setup_human_hud()

func _setup_camera_rig() -> void:
	spring_arm = SpringArm3D.new()
	spring_arm.name = "HumanSpringArm"
	spring_arm.spring_length = camera_distance
	spring_arm.margin = 0.2
	spring_arm.position = Vector3(0.0, camera_height, 0.0)
	spring_arm.rotation = Vector3(deg_to_rad(-18.0), 0.0, 0.0)

	chase_camera = Camera3D.new()
	chase_camera.name = "HumanChaseCamera"
	chase_camera.current = true
	chase_camera.fov = 72.0
	chase_camera.near = 0.05
	chase_camera.far = 100.0

	spring_arm.add_child(chase_camera)
	add_child(spring_arm)

func _setup_human_hud() -> void:
	hud_canvas = CanvasLayer.new()
	hud_canvas.name = "HumanControlHUD"

	# 1. Telemetry Card (Top-Right)
	var panel_info = PanelContainer.new()
	panel_info.position = Vector2(16, 16)
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.08, 0.10, 0.14, 0.88)
	style_box.border_color = Color(0.0, 0.85, 1.0, 0.8)
	style_box.set_border_width_all(2)
	style_box.set_corner_radius_all(6)
	style_box.content_margin_left = 14
	style_box.content_margin_right = 14
	style_box.content_margin_top = 10
	style_box.content_margin_bottom = 10
	panel_info.add_theme_stylebox_override("panel", style_box)

	hud_label_info = Label.new()
	hud_label_info.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	hud_label_info.text = "HUMAN PILOT MODE INITIALIZING..."
	panel_info.add_child(hud_label_info)
	hud_canvas.add_child(panel_info)

	# 2. Controls Legend (Bottom-Left)
	var panel_ctrl = PanelContainer.new()
	panel_ctrl.position = Vector2(16, 180)
	var style_ctrl = StyleBoxFlat.new()
	style_ctrl.bg_color = Color(0.05, 0.06, 0.09, 0.75)
	style_ctrl.border_color = Color(0.3, 0.4, 0.5, 0.5)
	style_ctrl.set_border_width_all(1)
	style_ctrl.set_corner_radius_all(6)
	style_ctrl.content_margin_left = 12
	style_ctrl.content_margin_right = 12
	style_ctrl.content_margin_top = 8
	style_ctrl.content_margin_bottom = 8
	panel_ctrl.add_theme_stylebox_override("panel", style_ctrl)

	hud_label_controls = Label.new()
	hud_label_controls.add_theme_color_override("font_color", Color(0.75, 0.82, 0.90))
	hud_label_controls.text = (
		"🎮 HUMAN AMR CONTROLS:\n" +
		"  [WASD] : Drive Forward / Reverse / Steer\n" +
		"  [Shift]: Turbo Sprint (4.8 m/s)\n" +
		"  [Space]: Hydraulic Active Brake\n" +
		"  [Click / E]: Target & Pick Box (IK Auto-Solve)\n" +
		"  [E]    : Stow Held Box into Dual Cargo Tray\n" +
		"  [G]    : Smart Unstow & Place (Conveyor / Floor)\n" +
		"  [1 - 4]: Auto-Select Rack Shelf Tier 1 to 4\n" +
		"  [C]    : Toggle Camera Mode (Chase / Orbit / Arm)\n" +
		"  [Esc]  : Deselect / Fold Arm to Rest Pose"
	)
	panel_ctrl.add_child(hud_label_controls)
	hud_canvas.add_child(panel_ctrl)

	add_child(hud_canvas)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_human_hud()

func _process_manual_driving(delta: float) -> void:
	var move_input: float = 0.0
	var turn_input: float = 0.0
	var is_braking: bool = Input.is_key_pressed(KEY_SPACE)
	var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT)

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

	# Apply linear acceleration / braking
	if is_braking:
		if not _was_braking:
			SoundManager.play_spatial(self, SoundManager.sfx_brake, -4.0)
		_was_braking = true
		_manual_linear_vel = move_toward(_manual_linear_vel, 0.0, linear_deceleration * 2.2 * delta)
		set_amr_state(AmrState.BLOCKED_SAFETY)
	else:
		_was_braking = false
		var target_top_speed = max_speed * (sprint_multiplier if is_sprinting else 1.0)
		var target_v = move_input * target_top_speed
		var accel = linear_acceleration if abs(target_v) > abs(_manual_linear_vel) else linear_deceleration
		_manual_linear_vel = move_toward(_manual_linear_vel, target_v, accel * delta)

		if abs(_manual_linear_vel) > 0.08:
			set_amr_state(AmrState.MOVING)
		else:
			set_amr_state(AmrState.IDLE)

	current_speed = abs(_manual_linear_vel)
	var forward: Vector3 = -global_transform.basis.z
	velocity.x = forward.x * _manual_linear_vel
	velocity.z = forward.z * _manual_linear_vel

	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# Dynamic impact physics with RigidBody3D obstacles (ShelfPod toppling, ToteBox scattering)
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is RigidBody3D:
			var impact_speed: float = abs(_manual_linear_vel)
			var impulse_dir: Vector3 = -col.get_normal()
			impulse_dir.y = 0.0
			impulse_dir = impulse_dir.normalized()
			var contact_offset: Vector3 = col.get_position() - collider.global_position

			# Wake up sleeping bodies
			collider.sleeping = false

			if collider is ToteBox:
				var impulse_mag: float = impact_speed * 18.0 + 8.0
				collider.apply_impulse(impulse_dir * impulse_mag, contact_offset)
			elif collider is ShelfPod:
				# High speed ramming transfers momentum to rack frame, tipping it over!
				var impulse_mag: float = impact_speed * 80.0 + (100.0 if impact_speed > 2.2 else 25.0)
				collider.apply_impulse(impulse_dir * impulse_mag, contact_offset)
				if impact_speed > 1.8:
					var tip_dir: Vector3 = forward.cross(Vector3.UP).normalized()
					collider.apply_torque_impulse(tip_dir * impact_speed * 160.0)

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
			_handle_smart_e_action()
			get_viewport().set_input_as_handled()

		elif key.keycode == KEY_G and not _is_arm_tweening:
			_handle_smart_g_action()
			get_viewport().set_input_as_handled()

		elif key.keycode == KEY_C:
			_cycle_camera_view()
			get_viewport().set_input_as_handled()

		elif key.keycode in [KEY_1, KEY_2, KEY_3, KEY_4] and not _is_arm_tweening:
			var target_tier_num = key.keycode - KEY_0
			_target_rack_tier(target_tier_num)
			get_viewport().set_input_as_handled()

## Smart contextual [E] action: Target -> Pick -> Stow
func _handle_smart_e_action() -> void:
	if _is_arm_tweening:
		return

	# If holding a box, stow it into next empty tray slot
	if held_box != null or arm_motion_state == ArmMotionState.HELD_READY:
		execute_dynamic_stow()
		return

	# If active box is targeted, pick it
	if active_target_box and is_instance_valid(active_target_box) and active_target_box.visible:
		var local_target: Vector3 = arm.to_local(active_target_box.global_position)
		var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_target)
		if ik.success:
			execute_dynamic_pick(active_target_box)
		else:
			SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
			_arm_status_text = "⚠️ Out of Reach (%.2fm > 2.15m) — Drive closer!" % ik.target_distance
		return

	# If no box targeted, auto-find nearest box
	var nearest: ToteBox = _find_nearest_tote_box()
	if nearest:
		select_target_box(nearest)
		var local_t: Vector3 = arm.to_local(nearest.global_position)
		var ik_res: ArmIKSolver.IKResult = ArmIKSolver.solve_local(local_t)
		if ik_res.success:
			execute_dynamic_pick(nearest)
		else:
			SoundManager.play_spatial(self, SoundManager.sfx_click, 0.0)
			_arm_status_text = "🎯 Targeted %s (%.2fm) — Drive slightly closer to pick" % [nearest.name, ik_res.target_distance]
	else:
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -3.0)
		_arm_status_text = "⚠️ No ToteBox found nearby within 5m."

## Smart contextual [G] action: Unstow & Place (Conveyor Belt if near, else Floor)
func _handle_smart_g_action() -> void:
	if _is_arm_tweening:
		return

	var has_payload = (held_box != null) or (get_stowed_box_count() > 0)
	if not has_payload:
		SoundManager.play_spatial(self, SoundManager.sfx_cancel, -3.0)
		_arm_status_text = "⚠️ No box to place! Pick or stow a box first."
		return

	# 1. Check for nearby conveyor table
	var tables = get_tree().get_nodes_in_group("conveyor_belts")
	var nearest_table: Node3D = null
	var min_table_dist: float = 4.0
	for t in tables:
		if is_instance_valid(t):
			var d = global_position.distance_to(t.global_position)
			if d < min_table_dist:
				min_table_dist = d
				nearest_table = t

	if nearest_table:
		# Calculate the closest reachable point along the 3.6m conveyor deck track
		var local_arm_pos = nearest_table.to_local(shoulder.global_position if shoulder else global_position)
		var clamped_deck_x = clampf(local_arm_pos.x, -1.2, 1.6)
		# Deck top surface is at y = 0.77m, centered laterally at z = 0.0m
		var deck_target_world = nearest_table.to_global(Vector3(clamped_deck_x, 0.77, 0.0))

		var ik_check = ArmIKSolver.solve_local(arm.to_local(deck_target_world))
		if ik_check.success:
			if execute_dynamic_unstow_and_place(deck_target_world):
				_arm_status_text = "Unstowing & placing onto Motorized Conveyor..."
				return
		else:
			SoundManager.play_spatial(self, SoundManager.sfx_cancel, -2.0)
			_arm_status_text = "⚠️ Out of Reach to Conveyor (%.2fm > 2.15m) — Drive closer to the deck!" % ik_check.target_distance
			return

	# 2. Floor Placement (Only if intentionally away from conveyor)
	if held_box != null:
		execute_dynamic_place()
		_arm_status_text = "Placing gripped box onto floor..."
	else:
		# Unstow to floor in front of chassis
		var floor_target = global_position + (-global_transform.basis.z * 1.1) + Vector3(0.0, 0.16, 0.0)
		execute_dynamic_unstow_and_place(floor_target)
		_arm_status_text = "Unstowing box onto floor..."


## Auto-target specific tier on closest rack
func _target_rack_tier(tier_num: int) -> void:
	var racks = get_tree().get_nodes_in_group("shelf_pods")
	var closest_rack: ShelfPod = null
	var min_d: float = 8.0
	for r in racks:
		if r is ShelfPod and is_instance_valid(r):
			var d = global_position.distance_to(r.global_position)
			if d < min_d:
				min_d = d
				closest_rack = r

	if not closest_rack:
		# Search by class name
		for node in get_tree().get_nodes_in_group("tote_boxes"):
			if node is ToteBox and node.tier == tier_num and node.visible:
				select_target_box(node)
				SoundManager.play_spatial(self, SoundManager.sfx_tier_select, 0.0)
				return
		return

	# Search boxes on this rack matching tier
	var totes = get_tree().get_nodes_in_group("tote_boxes")
	var candidate: ToteBox = null
	var min_box_d: float = 999.0
	for b in totes:
		if b is ToteBox and is_instance_valid(b) and b.tier == tier_num and b.visible and b.get_parent() != cargo_tray and b != held_box:
			var d = shoulder.global_position.distance_to(b.global_position)
			if d < min_box_d:
				min_box_d = d
				candidate = b

	if candidate:
		select_target_box(candidate)
		SoundManager.play_spatial(self, SoundManager.sfx_tier_select, 0.0)
		_arm_status_text = "🎯 Tier %d Selected (%s) | [E] Pick" % [tier_num, candidate.name]

func _cycle_camera_view() -> void:
	camera_mode = (camera_mode + 1) % 3
	if not spring_arm or not chase_camera:
		return

	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	match camera_mode:
		0: # 3rd-Person Chase
			tween.tween_property(spring_arm, "spring_length", camera_distance, 0.35)
			tween.parallel().tween_property(spring_arm, "position", Vector3(0.0, camera_height, 0.0), 0.35)
			tween.parallel().tween_property(spring_arm, "rotation:x", deg_to_rad(-18.0), 0.35)
			_arm_status_text = "Camera: 3rd-Person Chase"
		1: # Tactical Top-Down Overhead
			tween.tween_property(spring_arm, "spring_length", 8.5, 0.35)
			tween.parallel().tween_property(spring_arm, "position", Vector3(0.0, 3.5, 0.0), 0.35)
			tween.parallel().tween_property(spring_arm, "rotation:x", deg_to_rad(-65.0), 0.35)
			_arm_status_text = "Camera: Tactical Overhead"
		2: # Arm / Gripper Close-Up
			tween.tween_property(spring_arm, "spring_length", 1.8, 0.35)
			tween.parallel().tween_property(spring_arm, "position", Vector3(0.0, 1.2, -0.4), 0.35)
			tween.parallel().tween_property(spring_arm, "rotation:x", deg_to_rad(-5.0), 0.35)
			_arm_status_text = "Camera: Arm Inspection"

	SoundManager.play_spatial(self, SoundManager.sfx_click, -2.0)

func _update_human_hud() -> void:
	if not hud_label_info:
		return

	var s1_status = "EMPTY"
	var s2_status = "EMPTY"
	var b1 = get_slot_box(0)
	var b2 = get_slot_box(1)
	if b1 and is_instance_valid(b1): s1_status = b1.name
	if b2 and is_instance_valid(b2): s2_status = b2.name

	var hand_status = "FREE"
	if held_box and is_instance_valid(held_box):
		hand_status = held_box.name

	var target_str = "None"
	var ik_status_str = "N/A"
	if active_target_box and is_instance_valid(active_target_box):
		target_str = "%s (Tier %d)" % [active_target_box.name, active_target_box.tier]
		var local_t = arm.to_local(active_target_box.global_position)
		var ik = ArmIKSolver.solve_local(local_t)
		ik_status_str = "%.2fm %s" % [ik.target_distance, "[REACHABLE]" if ik.success else "[OUT OF REACH]"]

	hud_label_info.text = (
		"🤖 HUMAN AMR PILOT | %s\n" % robot_id +
		"────────────────────────────────────────\n" +
		"⚡ Speed: %4.2f m/s | State: %s\n" % [current_speed, AmrState.keys()[current_state]] +
		"🦾 Arm Motion: %s\n" % ArmMotionState.keys()[arm_motion_state] +
		"🤲 Gripper: [%s]\n" % hand_status +
		"📦 Cargo Tray: Slot 1: [%s] | Slot 2: [%s]\n" % [s1_status, s2_status] +
		"🎯 Target: %s | IK Reach: %s\n" % [target_str, ik_status_str] +
		"💬 Status: %s" % _arm_status_text
	)
