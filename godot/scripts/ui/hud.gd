class_name WarehouseHUD
extends Control

## RAMemory Smart Warehouse Digital Twin — Mission Control WES HUD.
## Manages Inbound Manifest Queues, Outbound Picking Orders, Zoned Storage, and Hybrid AI Telemetry.

signal dispatch_inbound_requested
signal dispatch_outbound_requested
signal conflict_demo_requested
signal reset_requested
signal auto_fleet_toggled(enabled: bool)
signal camera_preset_requested(preset_idx: int)
signal fullscreen_toggled

@onready var lbl_pick_rate: Label = $TopBar/KPIContainer/CardPickRate/ValPickRate
@onready var lbl_active_fleet: Label = $TopBar/KPIContainer/CardFleet/ValFleet
@onready var lbl_deadlocks: Label = $TopBar/KPIContainer/CardDeadlocks/ValDeadlocks
@onready var lbl_deadheading: Label = $TopBar/KPIContainer/CardDeadheading/ValDeadheading
@onready var lbl_orders: Label = $TopBar/KPIContainer/CardOrders/ValOrders
@onready var lbl_status: Label = $TopBar/ConnectionBadge

@onready var radar_map: RadarMap = $RadarPanel/RadarMap

# Inbound & Outbound Queue Displays
@onready var lbl_inbound_item1: Label = $ManifestPanel/ManifestContent/InboundList/Item1
@onready var lbl_inbound_item2: Label = $ManifestPanel/ManifestContent/InboundList/Item2
@onready var lbl_inbound_item3: Label = $ManifestPanel/ManifestContent/InboundList/Item3

@onready var lbl_outbound_item1: Label = $ManifestPanel/ManifestContent/OutboundList/Item1
@onready var lbl_outbound_item2: Label = $ManifestPanel/ManifestContent/OutboundList/Item2
@onready var lbl_outbound_item3: Label = $ManifestPanel/ManifestContent/OutboundList/Item3

# Fleet Telemetry Labels
@onready var amr1_status: Label = $FleetPanel/FleetList/CardAMR1/Info
@onready var amr1_bar: ProgressBar = $FleetPanel/FleetList/CardAMR1/BatteryBar
@onready var amr2_status: Label = $FleetPanel/FleetList/CardAMR2/Info
@onready var amr2_bar: ProgressBar = $FleetPanel/FleetList/CardAMR2/BatteryBar
@onready var amr3_status: Label = $FleetPanel/FleetList/CardAMR3/Info
@onready var amr3_bar: ProgressBar = $FleetPanel/FleetList/CardAMR3/BatteryBar
@onready var amr4_status: Label = $FleetPanel/FleetList/CardAMR4/Info
@onready var amr4_bar: ProgressBar = $FleetPanel/FleetList/CardAMR4/BatteryBar

# AI Negotiation Inspector
@onready var ai_marl_status: Label = $AiInspectorPanel/Content/ValMarl
@onready var ai_guardrail_status: Label = $AiInspectorPanel/Content/ValGuardrail

# Controls
@onready var btn_inbound: Button = $BottomBar/Controls/BtnInbound
@onready var btn_outbound: Button = $BottomBar/Controls/BtnOutbound
@onready var btn_conflict: Button = $BottomBar/Controls/BtnConflict
@onready var btn_auto: Button = $BottomBar/Controls/BtnAuto
@onready var btn_reset: Button = $BottomBar/Controls/BtnReset
@onready var btn_fullscreen: Button = $BottomBar/Controls/BtnFullscreen
@onready var btn_cam1: Button = $BottomBar/Controls/BtnCam1
@onready var btn_cam2: Button = $BottomBar/Controls/BtnCam2
@onready var btn_cam3: Button = $BottomBar/Controls/BtnCam3
@onready var btn_cam4: Button = $BottomBar/Controls/BtnCam4
@onready var log_box: RichTextLabel = $LogPanel/LogBox

var is_auto_fleet: bool = false

func _ready() -> void:
	if btn_inbound:
		btn_inbound.pressed.connect(func(): dispatch_inbound_requested.emit())
	if btn_outbound:
		btn_outbound.pressed.connect(func(): dispatch_outbound_requested.emit())
	if btn_conflict:
		btn_conflict.pressed.connect(func(): conflict_demo_requested.emit())
	if btn_auto:
		btn_auto.pressed.connect(_on_auto_pressed)
	if btn_reset:
		btn_reset.pressed.connect(func(): reset_requested.emit())
	if btn_fullscreen:
		btn_fullscreen.pressed.connect(func(): fullscreen_toggled.emit())

	if btn_cam1:
		btn_cam1.pressed.connect(func(): camera_preset_requested.emit(1))
	if btn_cam2:
		btn_cam2.pressed.connect(func(): camera_preset_requested.emit(2))
	if btn_cam3:
		btn_cam3.pressed.connect(func(): camera_preset_requested.emit(3))
	if btn_cam4:
		btn_cam4.pressed.connect(func(): camera_preset_requested.emit(4))

	log_event("[color=green]RAMemory Mission Control WES Digital Twin v2.2 Online.[/color]")
	log_event("[color=cyan]Zoned Storage: Zone A (FMCG), Zone B (Tech), Zone C (Pharma), Zone D (Bulky).[/color]")
	log_event("[color=yellow]Inbound Receiving & Outbound Picking Manifest Engine Ready.[/color]")

func update_telemetry(pick_rate_pct: float, active_robots: int, deadlock_count: int, deadheading_pct: float, orders_count: int, is_connected: bool) -> void:
	if lbl_pick_rate:
		lbl_pick_rate.text = "%+.1f%%" % pick_rate_pct
	if lbl_active_fleet:
		lbl_active_fleet.text = "%d AMRs" % active_robots
	if lbl_deadlocks:
		lbl_deadlocks.text = "%d (100%% Anti-Deadlock)" % deadlock_count
	if lbl_deadheading:
		lbl_deadheading.text = "%.1f%%" % deadheading_pct
	if lbl_orders:
		lbl_orders.text = "%d Manifests" % orders_count

	if lbl_status:
		if is_connected:
			lbl_status.text = "● VDA 5050 ONLINE (WebSocket)"
			lbl_status.modulate = Color.GREEN
		else:
			lbl_status.text = "○ STANDALONE DIGITAL TWIN"
			lbl_status.modulate = Color.ORANGE

func update_manifest_inbound(item_idx: int, order_str: String, col: Color) -> void:
	var target_label: Label = null
	match item_idx:
		1: target_label = lbl_inbound_item1
		2: target_label = lbl_inbound_item2
		3: target_label = lbl_inbound_item3
	if target_label:
		target_label.text = order_str
		target_label.modulate = col

func update_manifest_outbound(item_idx: int, order_str: String, col: Color) -> void:
	var target_label: Label = null
	match item_idx:
		1: target_label = lbl_outbound_item1
		2: target_label = lbl_outbound_item2
		3: target_label = lbl_outbound_item3
	if target_label:
		target_label.text = order_str
		target_label.modulate = col

func update_amr_card(idx: int, id_str: String, state_str: String, battery_val: float, speed_val: float, color_tint: Color) -> void:
	var label_target: Label = null
	var bar_target: ProgressBar = null

	match idx:
		1:
			label_target = amr1_status
			bar_target = amr1_bar
		2:
			label_target = amr2_status
			bar_target = amr2_bar
		3:
			label_target = amr3_status
			bar_target = amr3_bar
		4:
			label_target = amr4_status
			bar_target = amr4_bar

	if label_target:
		label_target.text = "%s: %s | %.1f m/s" % [id_str, state_str, speed_val]
		label_target.modulate = color_tint
	if bar_target:
		bar_target.value = battery_val

func update_ai_inspector(marl_decision: String, guardrail_status: String) -> void:
	if ai_marl_status:
		ai_marl_status.text = marl_decision
	if ai_guardrail_status:
		ai_guardrail_status.text = guardrail_status

func log_event(msg: String) -> void:
	if log_box:
		var time_str: String = Time.get_time_string_from_system()
		log_box.append_text("[color=gray][%s][/color] %s\n" % [time_str, msg])

func _on_auto_pressed() -> void:
	is_auto_fleet = not is_auto_fleet
	if btn_auto:
		btn_auto.text = "Pause Cycle" if is_auto_fleet else "Auto In/Out"
	auto_fleet_toggled.emit(is_auto_fleet)
	log_event("[color=yellow]Continuous autonomous Inbound/Outbound cycle: %s[/color]" % str(is_auto_fleet))
