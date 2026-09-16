extends SceneTree

func _init() -> void:
	print("[TEST] Verifying all 5 Phase 06 training scenes...")

	var scenes = [
		"res://scenes/training/training_navigate_to_item.tscn",
		"res://scenes/training/training_pickup.tscn",
		"res://scenes/training/training_navigate_carrying.tscn",
		"res://scenes/training/training_dropoff.tscn",
		"res://scenes/training/training_chained_cycle.tscn"
	]

	for path in scenes:
		print("  Loading %s..." % path)
		var pscene = load(path)
		if not pscene:
			push_error("[TEST FAIL] Could not load %s" % path)
			quit(1)
			return

		var inst = pscene.instantiate()
		root.add_child(inst)
		await process_frame
		await process_frame

		assert(inst != null, "Instance is null")
		assert(inst.has_method("_compute_observation"), "Missing _compute_observation")
		var obs = inst._compute_observation()
		assert(obs.size() == 13, "Observation size must be 13, got %d" % obs.size())
		print("  ✔ %s instantiated, 13-dim observation verified." % path.get_file())
		inst.queue_free()
		await process_frame

	print("[ALL SCENES VERIFIED] 100% clean instantiation and observation contracts!")
	quit(0)
