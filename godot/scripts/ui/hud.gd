class_name WarehouseHUD
extends Control

## Smart Warehouse Digital Twin HUD.
## Displays real-time KPIs codified in docs/PURPOSE.md and interactive fleet dispatch controls.

signal dispatch_order_requested
signal conflict_demo_requested
signal reset_requested
signal auto_fleet_toggled(enabled: bool)

@onready var lbl_pick_rate: Label = $TopBar/KPIContainer/CardPickRate/ValPickRate
@onready var lbl_active_fleet: Label = $TopBar/KPIContainer/CardFleet/ValFleet
@onready var lbl_deadlocks: Label = $TopBar/KPIContainer/CardDeadlocks/ValDeadlocks
@onready var lbl_deadheading: Label = $TopBar/KPIContainer/CardDeadheading/ValDeadheading
@onready var lbl_status: Label = $TopBar/ConnectionBadge
@onready var btn_dispatch: Button = $BottomBar/Controls/BtnDispatch
@onready var btn_conflict: Button = $BottomBar/Controls/BtnConflict
@onready var btn_auto: Button = $BottomBar/Controls/BtnAuto
@onready var btn_reset: Button = $BottomBar/Controls/BtnReset
@onready var log_box: RichTextLabel = $LogPanel/LogBox

var is_auto_fleet: bool = false

func _ready() -> void:
	if btn_dispatch:
		btn_dispatch.pressed.connect(func(): dispatch_order_requested.emit())
	if btn_conflict:
		btn_conflict.pressed.connect(func(): conflict_demo_requested.emit())
	if btn_auto:
		btn_auto.pressed.connect(_on_auto_pressed)
	if btn_reset:
		btn_reset.pressed.connect(func(): reset_requested.emit())
	log_event("[color=green]RAMemory Smart Warehouse Digital Twin HUD Active.[/color]")
	log_event("[color=cyan]VDA 5050 Fleet Orchestrator & OR Guardrails Ready.[/color]")

func update_telemetry(pick_rate_pct: float, active_robots: int, deadlock_count: int, deadheading_pct: float, is_connected: bool) -> void:
	if lbl_pick_rate:
		lbl_pick_rate.text = "%+.1f%%" % pick_rate_pct
	if lbl_active_fleet:
		lbl_active_fleet.text = "%d AMRs" % active_robots
	if lbl_deadlocks:
		lbl_deadlocks.text = "%d (100%% Anti-Deadlock)" % deadlock_count
	if lbl_deadheading:
		lbl_deadheading.text = "%.1f%%" % deadheading_pct

	if lbl_status:
		if is_connected:
			lbl_status.text = "● VDA 5050 ONLINE (WebSocket)"
			lbl_status.modulate = Color.GREEN
		else:
			lbl_status.text = "○ STANDALONE DIGITAL TWIN"
			lbl_status.modulate = Color.ORANGE

func log_event(msg: String) -> void:
	if log_box:
		log_box.append_text(msg + "\n")

func _on_auto_pressed() -> void:
	is_auto_fleet = not is_auto_fleet
	if btn_auto:
		btn_auto.text = "Pause Fleet" if is_auto_fleet else "Auto Fleet Run"
	auto_fleet_toggled.emit(is_auto_fleet)
	log_event("[color=yellow]Autonomous fleet continuous dispatch: %s[/color]" % str(is_auto_fleet))
