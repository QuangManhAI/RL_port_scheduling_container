class_name DigitalTwinHUD
extends Control

## Digital Twin HUD overlay displaying KPIs, telemetry, and simulation controls.

signal step_requested
signal reset_requested
signal auto_run_toggled(enabled: bool)
signal speed_changed(speed: float)

@onready var lbl_step: Label = $TopBar/KPIContainer/CardStep/ValStep
@onready var lbl_time: Label = $TopBar/KPIContainer/CardTime/ValTime
@onready var lbl_reward: Label = $TopBar/KPIContainer/CardReward/ValReward
@onready var lbl_status: Label = $TopBar/ConnectionBadge
@onready var btn_step: Button = $BottomBar/Controls/BtnStep
@onready var btn_auto: Button = $BottomBar/Controls/BtnAuto
@onready var btn_reset: Button = $BottomBar/Controls/BtnReset
@onready var log_box: RichTextLabel = $LogPanel/LogBox

var is_auto_running: bool = false

func _ready() -> void:
	if btn_step:
		btn_step.pressed.connect(_on_step_pressed)
	if btn_auto:
		btn_auto.pressed.connect(_on_auto_pressed)
	if btn_reset:
		btn_reset.pressed.connect(_on_reset_pressed)
	log_event("[color=green]Digital Twin HUD Initialized.[/color]")

func update_telemetry(step: int, sim_time: float, reward: float, is_connected: bool) -> void:
	if lbl_step:
		lbl_step.text = str(step)
	if lbl_time:
		lbl_time.text = "%.1fs" % sim_time
	if lbl_reward:
		lbl_reward.text = "%+.1f" % reward
	if lbl_status:
		if is_connected:
			lbl_status.text = "● ONLINE (WebSocket)"
			lbl_status.modulate = Color.GREEN
		else:
			lbl_status.text = "○ OFFLINE (Simulating Locally)"
			lbl_status.modulate = Color.ORANGE

func log_event(msg: String) -> void:
	if log_box:
		log_box.append_text(msg + "\n")

func _on_step_pressed() -> void:
	step_requested.emit()
	log_event("[color=cyan]Manual step dispatched.[/color]")

func _on_auto_pressed() -> void:
	is_auto_running = not is_auto_running
	if btn_auto:
		btn_auto.text = "Pause" if is_auto_running else "Auto Run"
	auto_run_toggled.emit(is_auto_running)
	log_event("[color=yellow]Auto-run toggled: %s[/color]" % str(is_auto_running))

func _on_reset_pressed() -> void:
	reset_requested.emit()
	log_event("[color=red]Environment reset requested.[/color]")
