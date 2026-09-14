extends Node3D

## Master Digital Twin Controller. Connects SimClient, ProceduralYard, and HUD.

@onready var yard_grid: ProceduralYard = $YardGrid
@onready var quay_crane: QuayCraneEntity = $QuayCrane
@onready var agv: AgvEntity = $AGV
@onready var ship: ShipEntity = $Ship
@onready var sim_client: SimClient = $SimClient
@onready var hud: DigitalTwinHUD = $HUD

var _sim_step: int = 0
var _sim_time: float = 0.0
var _total_reward: float = 0.0

func _ready() -> void:
	if sim_client:
		sim_client.connected_to_server.connect(_on_connected)
		sim_client.disconnected_from_server.connect(_on_disconnected)
		sim_client.state_received.connect(_on_state_received)

	if hud:
		hud.step_requested.connect(_on_hud_step)
		hud.reset_requested.connect(_on_hud_reset)
		hud.auto_run_toggled.connect(_on_hud_auto_run)

	# Initial offline demo populate if not connected immediately
	_spawn_initial_demo_layout()

func _spawn_initial_demo_layout() -> void:
	# Populate a couple demo containers so the yard is not empty on boot
	yard_grid.spawn_container(0, 0, 0, 0, 101, ContainerEntity.ContainerType.IMPORT)
	yard_grid.spawn_container(0, 0, 0, 1, 102, ContainerEntity.ContainerType.EXPORT)
	yard_grid.spawn_container(0, 0, 1, 0, 103, ContainerEntity.ContainerType.TRANSSHIPMENT)
	yard_grid.spawn_container(0, 1, 0, 0, 104, ContainerEntity.ContainerType.IMPORT)
	yard_grid.spawn_container(1, 0, 0, 0, 201, ContainerEntity.ContainerType.EXPORT)

func _on_connected() -> void:
	hud.log_event("[color=green]Connected to Python Simulation Server (ws://127.0.0.1:9090)![/color]")
	hud.update_telemetry(_sim_step, _sim_time, _total_reward, true)

func _on_disconnected() -> void:
	hud.log_event("[color=orange]Disconnected from Python Simulation Server. Reconnecting...[/color]")
	hud.update_telemetry(_sim_step, _sim_time, _total_reward, false)

func _on_state_received(state: Dictionary) -> void:
	if state.has("step"):
		_sim_step = int(state["step"])
	if state.has("sim_time"):
		_sim_time = float(state["sim_time"])
	if state.has("reward"):
		_total_reward += float(state["reward"])

	hud.update_telemetry(_sim_step, _sim_time, _total_reward, true)

	if state.has("yard_grid") and state["yard_grid"] is Array:
		yard_grid.sync_yard_state(state["yard_grid"])

	if state.has("event") and state["event"] is String:
		hud.log_event("[color=white]%s[/color]" % state["event"])

func _on_hud_step() -> void:
	if sim_client.is_connected_to_server():
		sim_client.request_step()
	else:
		# Local fallback demonstration
		_sim_step += 1
		_sim_time += 1.0
		_total_reward += 10.0
		hud.update_telemetry(_sim_step, _sim_time, _total_reward, false)
		hud.log_event("[color=cyan]Offline Step %d executed.[/color]" % _sim_step)

func _on_hud_reset() -> void:
	if sim_client.is_connected_to_server():
		sim_client.request_reset()
	else:
		_sim_step = 0
		_sim_time = 0.0
		_total_reward = 0.0
		yard_grid.clear_all()
		_spawn_initial_demo_layout()
		hud.update_telemetry(0, 0.0, 0.0, false)
		hud.log_event("[color=red]Offline Environment Reset.[/color]")

func _on_hud_auto_run(enabled: bool) -> void:
	if sim_client.is_connected_to_server():
		sim_client.send_command({"command": "auto_run", "enabled": enabled})
