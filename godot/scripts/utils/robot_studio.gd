extends Node3D

## High-Quality Multi-Angle Product Render Studio for AMR Robot
## Automatically renders and saves 7 presentation-ready slide images in 1920x1080.

@onready var amr: AmrRobot = $AMR_Robot
@onready var camera: Camera3D = $CameraGimbal/Camera3D
@onready var gimbal: Node3D = $CameraGimbal
@onready var floor_mesh: MeshInstance3D = $StudioFloor
@onready var box_scene = preload("res://scenes/environment/tote_box.tscn")

var render_stages = [
	{
		"name": "01_hero_three_quarters",
		"title": "Front 3/4 Hero Isometric View",
		"cam_pos": Vector3(2.5, 1.7, -2.5),
		"look_at": Vector3(0.0, 0.7, -0.05),
		"arm_pose": "folded",
		"boxes": "none"
	},
	{
		"name": "02_front_elevation",
		"title": "Front Low-Angle Dynamic Elevation",
		"cam_pos": Vector3(0.0, 0.85, -2.8),
		"look_at": Vector3(0.0, 0.65, -0.15),
		"arm_pose": "folded",
		"boxes": "none"
	},
	{
		"name": "03_side_profile",
		"title": "Side Profile & Chassis Clearance",
		"cam_pos": Vector3(3.2, 0.75, 0.0),
		"look_at": Vector3(0.0, 0.65, 0.0),
		"arm_pose": "folded",
		"boxes": "none"
	},
	{
		"name": "04_top_plan_view",
		"title": "Top-Down Technical Plan View",
		"cam_pos": Vector3(0.0, 3.6, 0.001),
		"look_at": Vector3(0.0, 0.0, 0.0),
		"arm_pose": "folded",
		"boxes": "none"
	},
	{
		"name": "05_rear_three_quarters",
		"title": "Rear 3/4 Cargo Bed Perspective",
		"cam_pos": Vector3(-2.5, 1.7, 2.5),
		"look_at": Vector3(0.0, 0.7, 0.05),
		"arm_pose": "folded",
		"boxes": "none"
	},
	{
		"name": "06_action_arm_deployed",
		"title": "4-DOF Robotic Arm Deployed (Picking Tote)",
		"cam_pos": Vector3(2.4, 1.5, -2.4),
		"look_at": Vector3(0.0, 0.60, -0.35),
		"arm_pose": "deployed",
		"boxes": "floor_target"
	},
	{
		"name": "07_loaded_dual_cargo",
		"title": "Full Dual-Payload Transport Mode",
		"cam_pos": Vector3(2.5, 1.7, -2.2),
		"look_at": Vector3(0.0, 0.7, 0.05),
		"arm_pose": "folded",
		"boxes": "dual_loaded"
	}
]

var stage_idx: int = 0
var frame_counter: int = 0
var spawned_boxes: Array[Node3D] = []

func _ready() -> void:
	if amr:
		amr.set_physics_process(false)
		amr.set_process(false)
		amr.velocity = Vector3.ZERO
		amr.global_position = Vector3(0.0, 0.0, 0.0)
		amr.rotation = Vector3.ZERO

		# Hide dev badge for pristine product rendering
		if amr.label_status:
			amr.label_status.visible = false
		if amr.target_reticle:
			amr.target_reticle.visible = false

		# Set signature cyan LED glow
		amr.set_amr_state(AmrRobot.AmrState.MOVING)

	_setup_stage(0)

func _process(_delta: float) -> void:
	frame_counter += 1

	# Wait 6 frames per stage to ensure shaders, bloom, shadow maps, and transforms are fully settled
	if frame_counter == 6:
		_capture_and_save()
		stage_idx += 1
		if stage_idx < render_stages.size():
			frame_counter = 0
			_setup_stage(stage_idx)
		else:
			print("==================================================")
			print("All 7 robot presentation renders exported successfully!")
			print("==================================================")
			get_tree().quit(0)

func _setup_stage(idx: int) -> void:
	var cfg = render_stages[idx]
	print("[Studio] Setting up shot %d/7: %s (%s)..." % [idx + 1, cfg["name"], cfg["title"]])

	# 1. Position Camera
	camera.global_position = cfg["cam_pos"]
	camera.look_at(cfg["look_at"], Vector3.UP)

	# 2. Clear old spawned boxes
	for b in spawned_boxes:
		if is_instance_valid(b) and b.get_parent():
			b.get_parent().remove_child(b)
			b.queue_free()
	spawned_boxes.clear()

	# 3. Configure Arm Pose
	if cfg["arm_pose"] == "folded":
		if amr:
			amr._fold_arm_to_home_instant()

	# 4. Configure Boxes
	if cfg["boxes"] == "floor_target":
		var box = box_scene.instantiate() as ToteBox
		add_child(box)
		box.freeze = true
		box.global_position = Vector3(0.0, 0.16, -1.08)
		box.rotation = Vector3.ZERO
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.05, 1.0) # Safety Industrial Orange
		mat.roughness = 0.35
		mat.metallic = 0.1
		box.get_node("MeshInstance3D").material_override = mat
		spawned_boxes.append(box)

		var target_in_arm = amr.arm.to_local(box.global_position + Vector3(0.0, 0.08, 0.0))
		var ik: ArmIKSolver.IKResult = ArmIKSolver.solve_local(target_in_arm)
		if ik.success:
			amr.arm.rotation.y = ik.base_yaw
			amr.shoulder.rotation.x = ik.shoulder_pitch
			amr.elbow.rotation.x = ik.elbow_pitch
			amr.wrist.rotation.x = ik.wrist_pitch
			if amr.finger_left and amr.finger_right:
				amr.finger_left.position.x = -0.22
				amr.finger_right.position.x = 0.22
			print("  [Studio] Arm IK Solved: yaw=%.1f, sh=%.1f, elb=%.1f, wr=%.1f" % [
				rad_to_deg(ik.base_yaw), rad_to_deg(ik.shoulder_pitch), rad_to_deg(ik.elbow_pitch), rad_to_deg(ik.wrist_pitch)
			])
	elif cfg["boxes"] == "dual_loaded":
		# Add Slot 1 Box (Front Tray Slot)
		var b1 = box_scene.instantiate() as ToteBox
		add_child(b1)
		b1.freeze = true
		b1.global_position = Vector3(0.0, 0.46, 0.03)
		b1.rotation = Vector3.ZERO
		var mat1 = StandardMaterial3D.new()
		mat1.albedo_color = Color(1.0, 0.45, 0.05, 1.0) # Vibrant Orange
		mat1.roughness = 0.35
		b1.get_node("MeshInstance3D").material_override = mat1
		spawned_boxes.append(b1)

		# Add Slot 2 Box (Rear Tray Slot)
		var b2 = box_scene.instantiate() as ToteBox
		add_child(b2)
		b2.freeze = true
		b2.global_position = Vector3(0.0, 0.46, 0.47)
		b2.rotation = Vector3.ZERO
		var mat2 = StandardMaterial3D.new()
		mat2.albedo_color = Color(0.08, 0.62, 0.95, 1.0) # Electric Blue
		mat2.roughness = 0.35
		b2.get_node("MeshInstance3D").material_override = mat2
		spawned_boxes.append(b2)

func _capture_and_save() -> void:
	var cfg = render_stages[stage_idx]
	var img: Image = get_viewport().get_texture().get_image()

	var filename = cfg["name"] + ".png"
	var local_godot_path = "res://renders/" + filename
	var global_path = ProjectSettings.globalize_path(local_godot_path)

	var err = img.save_png(global_path)
	if err == OK:
		print("  ✔ Saved: %s" % global_path)
	else:
		push_error("Failed to save render %s, error code: %d" % [filename, err])
