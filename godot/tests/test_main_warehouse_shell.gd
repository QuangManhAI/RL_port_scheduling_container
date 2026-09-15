extends SceneTree

func _init() -> void:
	print("[TEST] Loading res://scenes/main.tscn...")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if not main_scene:
		push_error("[TEST FAIL] Could not load main.tscn")
		quit(1)
		return

	var main_node = main_scene.instantiate()
	root.add_child(main_node)

	await process_frame
	await process_frame

	print("[TEST] main.tscn instantiated successfully.")

	var warehouse_shell = main_node.get_node_or_null("WarehouseShell")
	if not warehouse_shell:
		push_error("[TEST FAIL] WarehouseShell not found in main.tscn")
		quit(1)
		return
	print("[TEST PASS] WarehouseShell node found in Main.")

	var cam_rig = main_node.get_node_or_null("CameraController")
	if not cam_rig:
		push_error("[TEST FAIL] CameraController not found in main.tscn")
		quit(1)
		return
	print("[TEST PASS] CameraController node found in Main.")

	# Test presets 1-5
	for p in range(1, 6):
		main_node._on_camera_preset_requested(p)
		await process_frame
		print("[TEST PASS] Camera Preset %d executed cleanly." % p)

	# Test Cutaway Toggle
	var initial_cutaway = warehouse_shell.is_cutaway_mode
	var toggled_cutaway = warehouse_shell.toggle_cutaway_mode()
	assert(toggled_cutaway != initial_cutaway, "Cutaway mode toggle failed to invert state")
	print("[TEST PASS] Cutaway mode toggle verified: %s -> %s" % [initial_cutaway, toggled_cutaway])

	# Test Reset Entire Environment
	main_node._on_reset_floor()
	await process_frame
	print("[TEST PASS] Environment full reset (R key) completed cleanly.")

	print("[ALL TESTS PASSED] Warehouse realism environment and shell fully operational!")
	quit(0)
