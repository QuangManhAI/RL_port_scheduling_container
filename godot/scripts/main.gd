extends Node3D

## Master Smart Warehouse Digital Twin Controller.
## Coordinates Multi-Agent AMRs, Zoned Storage, Inbound Receiving & Outbound Picking Manifests.

@onready var warehouse_grid: ProceduralWarehouse = $WarehouseGrid
@onready var amr_1: AmrRobot = $Fleet/AMR_01
@onready var amr_2: AmrRobot = $Fleet/AMR_02
@onready var amr_3: AmrRobot = $Fleet/AMR_03
@onready var amr_4: AmrRobot = $Fleet/AMR_04
@onready var pick_station_1: Node3D = $PickStations/PickStation_1
@onready var pick_station_2: Node3D = $PickStations/PickStation_2
@onready var camera_rig: CameraRig = $CameraController
@onready var hud: WarehouseHUD = $HUD
@onready var sim_client: SimClient = $SimClient

var _auto_timer: float = 0.0
var _is_auto_running: bool = false
var _auto_turn: int = 0
var _total_manifests: int = 42
var _last_fullscreen_toggle_time: int = 0

var inbound_orders: Array[Dictionary] = [
	{"id": "PO-101", "sku": "FMCG Beverage", "zone": "Zone A", "pod_id": 1, "tier": 2, "state": "PENDING"},
	{"id": "PO-102", "sku": "Tech GPUs", "zone": "Zone B", "pod_id": 9, "tier": 1, "state": "PENDING"},
	{"id": "PO-103", "sku": "Pharma Vaccines", "zone": "Zone C", "pod_id": 17, "tier": 3, "state": "PENDING"},
]

var outbound_orders: Array[Dictionary] = [
	{"id": "SO-501", "sku": "FMCG Beverage", "zone": "Zone A", "pod_id": 3, "tier": 2, "station": 1, "state": "PENDING"},
	{"id": "SO-502", "sku": "Tech Hardware", "zone": "Zone B", "pod_id": 11, "tier": 1, "station": 2, "state": "PENDING"},
	{"id": "SO-503", "sku": "Heavy Machinery", "zone": "Zone D", "pod_id": 25, "tier": 4, "station": 1, "state": "PENDING"},
]

var _cur_inbound_idx: int = 0
var _cur_outbound_idx: int = 0

func _ready() -> void:
	if hud:
		hud.dispatch_inbound_requested.connect(_on_dispatch_inbound)
		hud.dispatch_outbound_requested.connect(_on_dispatch_outbound)
		hud.reset_requested.connect(_on_reset_floor)
		hud.camera_preset_requested.connect(_on_camera_preset_requested)
		hud.fullscreen_toggled.connect(toggle_fullscreen)
		hud.chase_cam_toggled.connect(_on_toggle_chase_cam)
		hud.spawn_dev_bot_requested.connect(_on_spawn_dev_bot)

	if sim_client:
		sim_client.connected_to_server.connect(_on_server_connected)
		sim_client.disconnected_from_server.connect(_on_server_disconnected)
		sim_client.state_received.connect(_on_state_received)

	_reset_entire_environment()
	_refresh_manifest_ui()

	if camera_rig and amr_1:
		camera_rig.toggle_follow_target(amr_1)

	hud.log_event("[color=green]🎮 ENVIRONMENT BUILDING SECTOR ACTIVE[/color]")
	hud.log_event("[color=cyan]DEV MANUAL BOT [DEV-01] initialized at intersection (0,0). Drive freely to inspect warehouse floor![/color]")
	hud.log_event("[color=yellow]Controls: WASD: Drive | Space: Brake | E: Arm (1-4 Tier, F Pick) | R: Reset Env | C: Chase Cam[/color]")

func _process(delta: float) -> void:
	_update_fleet_telemetry_and_radar()

func _update_fleet_telemetry_and_radar() -> void:
	var fleet: Array[AmrRobot] = [amr_1, amr_2, amr_3, amr_4]
	var colors: Array[Color] = [
		Color(0.0, 0.9, 1.0),
		Color(0.2, 1.0, 0.4),
		Color(1.0, 0.75, 0.1),
		Color(1.0, 0.4, 0.1)
	]

	for i in range(fleet.size()):
		var amr: AmrRobot = fleet[i]
		if not amr:
			continue

		if hud and hud.radar_map:
			hud.radar_map.update_robot(
				amr.robot_id,
				amr.global_position,
				amr.rotation.y,
				amr.current_task_str,
				colors[i]
			)

		if hud:
			hud.update_amr_card(
				i + 1,
				amr.robot_id,
				amr.current_task_str,
				amr.battery_level,
				amr.current_speed,
				colors[i]
			)

	if hud and amr_1:
		hud.update_ai_inspector(
			"🎮 [DEV-01] PILOT: Pos (X: %.1f, Z: %.1f) | Spd: %.1f m/s | Hdg: %.0f°" % [amr_1.global_position.x, amr_1.global_position.z, amr_1.current_speed, rad_to_deg(amr_1.rotation.y)],
			"WASD / Arrows: Drive | Space: Brake | C: Chase Cam | 1-4: Overhead Views"
		)

func _refresh_manifest_ui() -> void:
	if not hud:
		return
	for i in range(inbound_orders.size()):
		var ord: Dictionary = inbound_orders[i]
		var col: Color = Color(0.2, 0.9, 0.4) if ord["state"] == "STORED" else (Color(1.0, 0.8, 0.1) if ord["state"] == "IN_TRANSIT" else Color(0.8, 0.9, 1.0))
		hud.update_manifest_inbound(i + 1, "%s: %s -> %s [T%d] (%s)" % [ord["id"], ord["sku"], ord["zone"], ord["tier"], ord["state"]], col)

	for i in range(outbound_orders.size()):
		var ord: Dictionary = outbound_orders[i]
		var col: Color = Color(0.2, 0.9, 0.4) if ord["state"] == "SHIPPED" else (Color(1.0, 0.8, 0.1) if ord["state"] == "PICKING" else Color(0.8, 1.0, 0.85))
		hud.update_manifest_outbound(i + 1, "%s: %s [%s:T%d] -> Stn %d (%s)" % [ord["id"], ord["sku"], ord["zone"], ord["tier"], ord["station"], ord["state"]], col)

func _reset_entire_environment() -> void:
	# 1. Reset all ShelfPods (32 dynamic racks)
	var pods = get_tree().get_nodes_in_group("shelf_pods")
	for pod in pods:
		if pod is ShelfPod:
			pod.reset_rack()

	# 2. Reset all ToteBoxes (256 physical boxes)
	var boxes = get_tree().get_nodes_in_group("tote_boxes")
	for b in boxes:
		if b is ToteBox:
			b.reset_box()

	# 3. Reset all AMRs and folded arms
	if amr_1:
		amr_1.robot_id = "DEV-01"
		amr_1.is_manual_control = true
		amr_1.reset_robot(Vector3(0.0, 0.0, 0.0), 0.0)
	if amr_2:
		amr_2.reset_robot(Vector3(18.0, 0.0, -10.0), 0.0)
	if amr_3:
		amr_3.reset_robot(Vector3(-18.0, 0.0, 10.0), 0.0)
	if amr_4:
		amr_4.reset_robot(Vector3(0.0, 0.0, -32.0), deg_to_rad(180.0))

	if hud:
		hud.update_ai_inspector(
			"🎮 [DEV-01] PILOT: Ready at Center (0,0)",
			"WASD: Drive | Space: Brake | E: Arm | R: Reset Env | C: Cam"
		)

func _on_toggle_chase_cam() -> void:
	if camera_rig and amr_1:
		var is_chasing = camera_rig.toggle_follow_target(amr_1)
		if hud:
			hud.log_event("[color=cyan]🎥 Camera mode: %s[/color]" % ("CHASE FOLLOW [DEV-01]" if is_chasing else "FREE RTS OVERVIEW"))

func _on_spawn_dev_bot(location: String) -> void:
	if not amr_1:
		return
	match location:
		"CENTER":
			amr_1.global_position = Vector3(0.0, 0.0, 0.0)
			amr_1.rotation = Vector3.ZERO
			hud.log_event("[color=yellow]📍 DEV-01 spawned at Center 4-Way Intersection (0,0).[/color]")
		"DOCK":
			amr_1.global_position = Vector3(0.0, 0.0, -28.0)
			amr_1.rotation = Vector3(0, deg_to_rad(180), 0)
			hud.log_event("[color=yellow]📍 DEV-01 spawned at Inbound Receiving Dock (0, -28).[/color]")
		"PICK":
			amr_1.global_position = Vector3(0.0, 0.0, 24.0)
			amr_1.rotation = Vector3.ZERO
			hud.log_event("[color=yellow]📍 DEV-01 spawned at Outbound Pick Station (0, 24).[/color]")

func _on_dispatch_inbound() -> void:
	var order_idx: int = _cur_inbound_idx % inbound_orders.size()
	_cur_inbound_idx += 1
	var ord: Dictionary = inbound_orders[order_idx]
	ord["state"] = "IN_TRANSIT"
	_total_manifests += 1
	_refresh_manifest_ui()

	hud.log_event("[color=cyan]📥 [INBOUND] Processing Order %s: %s received at Receiving Dock.[/color]" % [ord["id"], ord["sku"]])
	hud.log_event("[color=white]AMR-04: Assigned inbound task -> Routing to Receiving Dock (0, -32)[/color]")

	# AMR-04 drives to Inbound Receiving Dock
	var inbound_dock_pos: Vector3 = Vector3(0.0, 0.0, -32.0)
	var tween_to_dock: Tween = amr_4.drive_to(inbound_dock_pos, 1.8)
	tween_to_dock.finished.connect(func():
		hud.log_event("[color=cyan]AMR-04: At Inbound Dock -> Loading %s (Tier %d Stacked)[/color]" % [ord["sku"], ord["tier"]])
		
		# Target storage location in designated Zone
		var target_pod: ShelfPod = warehouse_grid.get_pod(ord["pod_id"])
		var target_pos: Vector3 = target_pod.global_position if target_pod else Vector3(-24.0, 0.0, 0.0)

		get_tree().create_timer(1.0).timeout.connect(func():
			hud.log_event("[color=green]AMR-04: Transiting to %s -> Storing to Tier %d[/color]" % [ord["zone"], ord["tier"]])
			var tween_to_zone: Tween = amr_4.drive_to(target_pos + Vector3(0, 0, -2.0), 3.0)
			tween_to_zone.finished.connect(func():
				ord["state"] = "STORED"
				_refresh_manifest_ui()
				if hud:
					hud.update_telemetry(22.5, 4, 0, 13.8, _total_manifests, sim_client.is_connected_to_server() if sim_client else false)
				hud.log_event("[color=green]✔ Order %s STORED in %s (Tier %d)! Barcode indexed in WES database.[/color]" % [ord["id"], ord["zone"], ord["tier"]])
			)
		)
	)

	if sim_client and sim_client.is_connected_to_server():
		sim_client.send_command({"command": "dispatch", "type": "inbound", "order_id": ord["id"]})

func _on_dispatch_outbound() -> void:
	var order_idx: int = _cur_outbound_idx % outbound_orders.size()
	_cur_outbound_idx += 1
	var ord: Dictionary = outbound_orders[order_idx]
	ord["state"] = "PICKING"
	_total_manifests += 1
	_refresh_manifest_ui()

	hud.log_event("[color=cyan]📤 [OUTBOUND] Processing Order %s: Picking %s from %s (Tier %d)[/color]" % [ord["id"], ord["sku"], ord["zone"], ord["tier"]])
	
	var target_pod: ShelfPod = warehouse_grid.get_pod(ord["pod_id"])
	var target_pos: Vector3 = target_pod.global_position if target_pod else Vector3(18.0, 0.0, -10.0)
	var station_target: Node3D = pick_station_1 if ord["station"] == 1 else pick_station_2

	hud.log_event("[color=white]AMR-03: Navigating to %s (Pod #%d) for Goods-to-Person picking[/color]" % [ord["zone"], ord["pod_id"]])
	var drive_tween: Tween = amr_3.drive_to(target_pos, 2.4)
	drive_tween.finished.connect(func():
		hud.log_event("[color=cyan]AMR-03: Under chassis -> Elevating Turntable -> Pod #%d Lifted![/color]" % ord["pod_id"])
		var lift_tween: Tween = amr_3.dock_and_lift_pod(target_pod) if target_pod else null
		var on_lifted = func():
			hud.log_event("[color=green]AMR-03: Transporting Pod #%d to Pick Station %d[/color]" % [ord["pod_id"], ord["station"]])
			var transit_tween: Tween = amr_3.drive_to(station_target.global_position + Vector3(0, 0, -2.5), 3.0)
			transit_tween.finished.connect(func():
				hud.log_event("[color=green]✔ Pod #%d arrived at Pick Station %d! Item picked from Tier %d.[/color]" % [ord["pod_id"], ord["station"], ord["tier"]])
				get_tree().create_timer(1.2).timeout.connect(func():
					hud.log_event("[color=yellow]AMR-03: Returning Pod #%d to %s aisle...[/color]" % [ord["pod_id"], ord["zone"]])
					var return_tween: Tween = amr_3.drive_to(target_pos, 2.8)
					return_tween.finished.connect(func():
						if target_pod:
							amr_3.dock_and_drop_pod(warehouse_grid, target_pos)
						ord["state"] = "SHIPPED"
						_refresh_manifest_ui()
						if hud:
							hud.update_telemetry(22.5, 4, 0, 13.8, _total_manifests, sim_client.is_connected_to_server() if sim_client else false)
						hud.log_event("[color=green]✔ Outbound Order %s SHIPPED! G2P Pick Rate optimized +22.5%%.[/color]" % ord["id"])
					)
				)
			)
		if lift_tween:
			lift_tween.finished.connect(on_lifted)
		else:
			on_lifted.call()
	)

	if sim_client and sim_client.is_connected_to_server():
		sim_client.send_command({"command": "dispatch", "type": "outbound", "order_id": ord["id"]})

func _on_simulate_4way_conflict() -> void:
	hud.log_event("[color=yellow]▶ Simulating 4-Way Intersection Conflict at Node (0,0)...[/color]")
	_reset_entire_environment()

	hud.log_event("[color=cyan]AMR-01: Dispatched West -> East via Intersection (0,0)[/color]")
	hud.log_event("[color=cyan]AMR-02: Dispatched North -> South via Intersection (0,0)[/color]")

	if hud:
		hud.update_ai_inspector(
			"MARL Traffic Engine: Converging trajectories at (0,0)",
			"OR Safety Guardrail: Monitoring safety distance (>1.8m)"
		)

	amr_1.drive_to(Vector3(25.0, 0.0, 0.0), 5.0)
	amr_2.drive_to(Vector3(0.0, 0.0, -8.0), 2.2)

	get_tree().create_timer(2.2).timeout.connect(func():
		hud.log_event("[color=yellow]⚠️ Intersection Hazard: Head-on crossing conflict detected![/color]")
		hud.log_event("[color=green]✔ MARL Dynamic Priority Negotiation: AMR-02 yields right-of-way to AMR-01.[/color]")
		amr_2.yield_at_intersection(2.2)

		if hud:
			hud.update_ai_inspector(
				"MARL Priority: AMR-01 [Rank 1] > AMR-02 [Rank 2] -> AMR-02 Yielding",
				"OR Safety Guardrail: Interlock Active. Minimum separation: 3.4m > 1.8m"
			)

		get_tree().create_timer(2.4).timeout.connect(func():
			hud.log_event("[color=green]✔ Node (0,0) clear! AMR-02 resuming transit. Deadlock avoided (0 deadlocks)![/color]")
			amr_2.drive_to(Vector3(0.0, 0.0, 25.0), 3.0)

			if hud:
				hud.update_ai_inspector(
					"MARL Dynamic Flow: Intersection Cleared successfully",
					"OR Safety Guardrail: All vehicles nominal. 100% Anti-Deadlock confirmed."
				)
		)
	)

func _on_auto_fleet_toggled(enabled: bool) -> void:
	_is_auto_running = enabled
	_auto_timer = 0.0

func _on_reset_floor() -> void:
	_reset_entire_environment()
	_cur_inbound_idx = 0
	_cur_outbound_idx = 0
	for ord in inbound_orders:
		ord["state"] = "PENDING"
	for ord in outbound_orders:
		ord["state"] = "PENDING"
	_refresh_manifest_ui()
	hud.log_event("[color=yellow]🔄 Entire warehouse floor, 32 dynamic racks, 256 physical boxes & fleet reset![/color]")

func _on_camera_preset_requested(preset_idx: int) -> void:
	if not camera_rig:
		return
	match preset_idx:
		1:
			camera_rig.set_view_overview()
		2:
			camera_rig.set_view_topdown()
		3:
			camera_rig.set_view_pick_station()
		4:
			camera_rig.set_view_inbound_dock()

func _on_server_connected() -> void:
	if hud:
		hud.update_telemetry(22.5, 4, 0, 13.8, _total_manifests, true)
	hud.log_event("[color=green]✔ Connected to Python VDA 5050 WebSocket Bridge![/color]")

func _on_server_disconnected() -> void:
	if hud:
		hud.update_telemetry(22.5, 4, 0, 13.8, _total_manifests, false)
	hud.log_event("[color=orange]⚠ Disconnected from Python Bridge. Operating in Standalone Twin mode.[/color]")

func _on_state_received(state_dict: Dictionary) -> void:
	var pick_boost: float = float(state_dict.get("pick_rate_boost", 22.5))
	var fleet_count: int = int(state_dict.get("active_fleet_count", 4))
	var deadlocks: int = int(state_dict.get("deadlocks", 0))
	var deadheading: float = float(state_dict.get("deadheading_ratio", 13.8))
	var event_msg: String = str(state_dict.get("event", ""))

	if hud:
		hud.update_telemetry(pick_boost, fleet_count, deadlocks, deadheading, _total_manifests, true)
		if event_msg != "":
			hud.log_event("[color=cyan][VDA 5050] %s[/color]" % event_msg)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed):
			get_viewport().set_input_as_handled()
			toggle_fullscreen()
		elif key.keycode == KEY_R:
			get_viewport().set_input_as_handled()
			_on_reset_floor()

func toggle_fullscreen() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_fullscreen_toggle_time < 400:
		return
	_last_fullscreen_toggle_time = now

	var win: Window = get_window()
	var is_fullscreen_now: bool = (win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN)

	if is_fullscreen_now:
		win.mode = Window.MODE_WINDOWED
		var screen_size: Vector2i = DisplayServer.screen_get_size()
		var target_w: int = int(min(1600, screen_size.x * 0.85))
		var target_h: int = int(min(900, screen_size.y * 0.85))
		win.size = Vector2i(target_w, target_h)
		win.position = Vector2i(
			max(0, (screen_size.x - target_w) / 2),
			max(0, (screen_size.y - target_h) / 2)
		)
		if hud and hud.btn_fullscreen:
			hud.btn_fullscreen.text = "⛶ Full [F11]"
		if hud:
			hud.log_event("[color=yellow]Window display switched to Windowed (%dx%d).[/color]" % [target_w, target_h])
	else:
		win.mode = Window.MODE_FULLSCREEN
		if hud and hud.btn_fullscreen:
			hud.btn_fullscreen.text = "🗗 Window [F11]"
		if hud:
			hud.log_event("[color=cyan]Window display switched to Fullscreen (Press F11 to exit).[/color]")
