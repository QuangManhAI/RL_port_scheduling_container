class_name TrainingHUD
extends CanvasLayer

## Live On-Screen HUD Overlay for RL Training Scenes.
## Runs with process_mode = PROCESS_MODE_ALWAYS so UI and telemetry update
## continuously even when physics frames are paused during lockstep stepping.

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var telemetry_label: Label = $Margin/VBox/TelemetryLabel
@onready var controls_label: Label = $Margin/VBox/ControlsLabel
@onready var banner_label: Label = $BannerLabel

var env_node: TrainingEnvBase = null
var episode_count: int = 0
var last_dist: float = 0.0
var banner_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var p = get_parent()
	if p is TrainingEnvBase:
		env_node = p
	banner_label.visible = false

func _process(delta: float) -> void:
	if not env_node:
		return

	# Status line
	if env_node.is_client_connected:
		status_label.text = "● RL Client Connected (Port %d) | Deterministic Lockstep Active" % env_node.active_port
		status_label.modulate = Color(0.2, 0.9, 0.3, 1.0)
	else:
		status_label.text = "○ TCP Server Listening on 127.0.0.1:%d | Waiting for Python..." % env_node.active_port
		status_label.modulate = Color(0.9, 0.7, 0.2, 1.0)

	# Telemetry
	var dist_text = ""
	var amr = env_node.amr
	if amr:
		var spd = amr._manual_linear_vel
		var pos = amr.global_position
		if env_node.has_method("_get_current_distance_to_box"):
			last_dist = env_node._get_current_distance_to_box()
			dist_text = " | Dist to Target: %.2fm" % last_dist
		telemetry_label.text = "AMR Pose: (%.1f, %.1f) | Yaw: %.1f° | Lin Vel: %.2f m/s%s | Step: %d" % [
			pos.x, pos.z, rad_to_deg(amr.rotation.y), spd, dist_text, env_node.step_count
		]

	# Banner decay
	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			banner_label.visible = false

func show_banner(text: String, color: Color, duration: float = 2.0) -> void:
	banner_label.text = text
	banner_label.modulate = color
	banner_label.visible = true
	banner_timer = duration
