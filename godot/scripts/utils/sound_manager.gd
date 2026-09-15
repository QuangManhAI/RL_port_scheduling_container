class_name SoundManager
extends Node

## Centralized Audio & Sound Effects Dispatcher for WES Digital Twin.
## Manages 2D interface feedback and 3D spatial acoustics for AMRs.

static var sfx_click: AudioStream = preload("res://audio/ui/click.ogg")
static var sfx_cancel: AudioStream = preload("res://audio/ui/cancel.ogg")
static var sfx_hover: AudioStream = preload("res://audio/ui/hover.ogg")
static var sfx_toggle: AudioStream = preload("res://audio/ui/toggle.ogg")

static var sfx_arm_prepare: AudioStream = preload("res://audio/sfx/arm_prepare.ogg")
static var sfx_tier_select: AudioStream = preload("res://audio/sfx/tier_select.ogg")
static var sfx_box_pick: AudioStream = preload("res://audio/sfx/box_pick.ogg")
static var sfx_box_stow: AudioStream = preload("res://audio/sfx/box_stow.ogg")
static var sfx_brake: AudioStream = preload("res://audio/sfx/brake.wav")

static func play_ui(node: Node, stream: AudioStream, volume_db: float = -6.0) -> void:
	if not node or not stream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	node.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

static func play_spatial(node: Node3D, stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not node or not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.unit_size = 10.0
	player.max_distance = 45.0
	node.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
