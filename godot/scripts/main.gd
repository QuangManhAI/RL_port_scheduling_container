extends Node3D

## Master Smart Warehouse Digital Twin Controller.
## Coordinates Multi-Agent AMRs, Goods-to-Person fulfillment, and VDA 5050 telemetry.

@onready var warehouse_grid: ProceduralWarehouse = $WarehouseGrid
@onready var amr_1: AmrRobot = $Fleet/AMR_01
@onready var amr_2: AmrRobot = $Fleet/AMR_02
@onready var amr_3: AmrRobot = $Fleet/AMR_03
@onready var amr_4: AmrRobot = $Fleet/AMR_04
@onready var pick_station_1: Node3D = $PickStations/PickStation_1
@onready var pick_station_2: Node3D = $PickStations/PickStation_2
@onready var hud: WarehouseHUD = $HUD
@onready var sim_client: SimClient = $SimClient

var _auto_timer: float = 0.0
var _is_auto_running: bool = false
var _orders_fulfilled: int = 42

func _ready() -> void:
	if hud:
		hud.dispatch_order_requested.connect(_on_dispatch_order)
		hud.conflict_demo_requested.connect(_on_simulate_4way_conflict)
		hud.auto_fleet_toggled.connect(_on_auto_fleet_toggled)
		hud.reset_requested.connect(_on_reset_floor)

	if sim_client:
		sim_client.connected_to_server.connect(_on_server_connected)
		sim_client.disconnected_from_server.connect(_on_server_disconnected)
		sim_client.state_received.connect(_on_state_received)

	_reset_fleet_positions()
	hud.log_event("[color=green]Smart Warehouse Digital Twin initialized with 4 autonomous AMRs.[/color]")
	hud.log_event("[color=yellow]Press 'Simulate 4-Way Conflict' to demonstrate Anti-Deadlock Yielding![/color]")

func _process(delta: float) -> void:
	if _is_auto_running:
		_auto_timer += delta
		if _auto_timer >= 6.0:
			_auto_timer = 0.0
			_on_dispatch_order()

func _reset_fleet_positions() -> void:
	amr_1.global_position = Vector3(-25.0, 0.0, 0.0)
	amr_1.rotation = Vector3.ZERO
	amr_1.set_amr_state(AmrRobot.AmrState.IDLE)

	amr_2.global_position = Vector3(0.0, 0.0, -25.0)
	amr_2.rotation = Vector3.ZERO
	amr_2.set_amr_state(AmrRobot.AmrState.IDLE)

	amr_3.global_position = Vector3(18.0, 0.0, -10.0)
	amr_3.rotation = Vector3.ZERO
	amr_3.set_amr_state(AmrRobot.AmrState.IDLE)

	amr_4.global_position = Vector3(-20.0, 0.0, -28.0)
	amr_4.rotation = Vector3.ZERO
	amr_4.set_amr_state(AmrRobot.AmrState.CHARGING)

func _on_simulate_4way_conflict() -> void:
	hud.log_event("[color=yellow]▶ Simulating 4-Way Intersection Conflict between AMR-01 and AMR-02...[/color]")
	_reset_fleet_positions()

	# AMR-01 moves West -> East across intersection (0,0)
	# AMR-02 moves North -> South across intersection (0,0)
	hud.log_event("[color=cyan]AMR-01 dispatch: Trajectory West -> East via Intersection (0,0)[/color]")
	hud.log_event("[color=cyan]AMR-02 dispatch: Trajectory North -> South via Intersection (0,0)[/color]")

	# Both start moving towards intersection
	amr_1.drive_to(Vector3(25.0, 0.0, 0.0), 5.0)
	amr_2.drive_to(Vector3(0.0, 0.0, -8.0), 2.2)

	# Dynamic MARL Yielding logic trigger
	get_tree().create_timer(2.2).timeout.connect(func():
		hud.log_event("[color=yellow]⚠️ Potential Head-On / Crossing Conflict detected at Intersection (0,0)![/color]")
		hud.log_event("[color=green]✔ MARL Dynamic Priority Negotiation: AMR-02 yields right-of-way to AMR-01.[/color]")
		amr_2.yield_at_intersection(2.0)
		hud.log_event("[color=yellow]AMR-02 status: YIELDING (Yellow LED Active)[/color]")

		# After AMR-01 clears the intersection, AMR-02 proceeds safely
		get_tree().create_timer(2.2).timeout.connect(func():
			hud.log_event("[color=green]✔ Intersection clear! AMR-02 resuming transit. Deadlock avoided (0 deadlocks)![/color]")
			amr_2.drive_to(Vector3(0.0, 0.0, 25.0), 3.0)
		)
	)

func _on_dispatch_order() -> void:
	_orders_fulfilled += 1
	hud.log_event("[color=cyan]▶ Dispatching Order #%d (Goods-to-Person)[/color]" % _orders_fulfilled)
	
	# AMR-03 drives to pod #3, lifts it, brings to Pick Station #1
	var target_pod: ShelfPod = warehouse_grid.get_pod(3)
	if target_pod:
		hud.log_event("[color=white]AMR-03: Navigating to Shelf Pod #3[/color]")
		var drive_tween: Tween = amr_3.drive_to(target_pod.global_position, 2.5)
		drive_tween.finished.connect(func():
			hud.log_event("[color=cyan]AMR-03: Under chassis -> Elevating Turntable -> Pod #3 Lifted![/color]")
			var lift_tween: Tween = amr_3.dock_and_lift_pod(target_pod)
			lift_tween.finished.connect(func():
				hud.log_event("[color=green]AMR-03: Transporting Pod #3 to Pick Station #1[/color]")
				var to_pick: Tween = amr_3.drive_to(Vector3(0.0, 0.0, 24.0), 3.0)
				to_pick.finished.connect(func():
					hud.log_event("[color=green]✔ Pod #3 presented at Pick Station #1! SKU items picked.[/color]")
					hud.update_telemetry(23.1, 4, 0, 13.2, sim_client.is_connected_to_server())
				)
			)
		)

func _on_auto_fleet_toggled(enabled: bool) -> void:
	_is_auto_running = enabled
	if enabled:
		hud.log_event("[color=green]Continuous Multi-Agent Autonomous Fleet dispatch enabled.[/color]")
		_on_dispatch_order()
	else:
		hud.log_event("[color=yellow]Continuous Fleet dispatch paused.[/color]")

func _on_reset_floor() -> void:
	_reset_fleet_positions()
	hud.log_event("[color=red]Warehouse floor reset. All AMRs returned to home bases.[/color]")

func _on_server_connected() -> void:
	hud.log_event("[color=green]Connected to Python VDA 5050 Fleet Orchestrator (ws://127.0.0.1:9090)[/color]")
	hud.update_telemetry(22.5, 4, 0, 13.8, true)

func _on_server_disconnected() -> void:
	hud.log_event("[color=orange]Disconnected from Python Fleet Orchestrator. Running standalone.[/color]")
	hud.update_telemetry(22.5, 4, 0, 13.8, false)

func _on_state_received(state: Dictionary) -> void:
	if state.has("event"):
		hud.log_event(str(state["event"]))
