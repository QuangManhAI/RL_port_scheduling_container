class_name TrainingEnvBase
extends Node3D

## Base class for Godot 4 Headless RL Training Environments.
## Communicates with Python via synchronous TCP StreamPeer with 4-byte length-prefixed JSON.
## Enforces deterministic lockstep physics simulation: unpauses tree for exactly `ticks_per_step`
## physics frames per RL step, ensuring zero simulation drift between Python policy updates.

signal episode_ended(terminated: bool, truncated: bool)

@export var ticks_per_step: int = 4
@export var max_episode_steps: int = 600
@export var default_port: int = 11000

var tcp_server: TCPServer
var client: StreamPeerTCP
var active_port: int = 11000
var step_count: int = 0
var current_difficulty: float = 0.0
var is_client_connected: bool = false
var _is_processing_step: bool = false

@onready var amr: AmrRobot = $AMR_Robot

func _ready() -> void:
	# Ensure this environment controller continues running even when the rest of the scene is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_parse_cmdline_args()
	_start_tcp_server()

	# Pause scene physics initially until Python connects and issues reset()
	get_tree().paused = true

func _parse_cmdline_args() -> void:
	active_port = default_port
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			active_port = int(arg.replace("--port=", ""))
		elif arg.begins_with("--ticks="):
			ticks_per_step = int(arg.replace("--ticks=", ""))
		elif arg.begins_with("--max_steps="):
			max_episode_steps = int(arg.replace("--max_steps=", ""))

func _start_tcp_server() -> void:
	tcp_server = TCPServer.new()
	var err = tcp_server.listen(active_port, "127.0.0.1")
	if err == OK:
		print("[TrainingEnvBase] Listening on 127.0.0.1:%d (ticks_per_step=%d)" % [active_port, ticks_per_step])
	else:
		push_error("[TrainingEnvBase] Failed to bind 127.0.0.1:%d, error: %d" % [active_port, err])

func _process(_delta: float) -> void:
	# Check for incoming client connection
	if not is_client_connected:
		if tcp_server and tcp_server.is_connection_available():
			client = tcp_server.take_connection()
			if client:
				client.big_endian = true
				is_client_connected = true
				print("[TrainingEnvBase] Python RL client connected on port %d" % active_port)
		return

	# Maintain active client connection
	client.poll()
	var status = client.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			print("[TrainingEnvBase] Python client disconnected from port %d" % active_port)
			is_client_connected = false
			client = null
			get_tree().paused = true
		return

	if _is_processing_step:
		return

	# Check if length header is available (4 bytes uint32)
	var available_bytes = client.get_available_bytes()
	if available_bytes < 4:
		return

	# Peek or read length
	var payload_len: int = client.get_u32()
	if payload_len <= 0 or payload_len > 1000000:
		push_error("[TrainingEnvBase] Invalid payload length: %d" % payload_len)
		return

	# Wait until entire payload is received
	var received_data: PackedByteArray = PackedByteArray()
	while received_data.size() < payload_len:
		client.poll()
		var chunk_size = min(payload_len - received_data.size(), client.get_available_bytes())
		if chunk_size > 0:
			var res = client.get_data(chunk_size)
			if res[0] == OK:
				received_data.append_array(res[1])
		else:
			OS.delay_usec(100)

	var json_str: String = received_data.get_string_from_utf8()
	var json = JSON.new()
	var parse_err = json.parse(json_str)
	if parse_err != OK:
		push_error("[TrainingEnvBase] JSON parse error: %s" % json.get_error_message())
		return

	var msg = json.data
	if msg is Dictionary:
		_handle_client_message(msg)

func _handle_client_message(msg: Dictionary) -> void:
	var cmd = msg.get("command", "")
	match cmd:
		"reset":
			_is_processing_step = true
			var seed_val: int = int(msg.get("seed", 0))
			current_difficulty = float(msg.get("difficulty", 0.0))
			step_count = 0

			# Execute reset
			_on_arena_reset(seed_val, current_difficulty)

			# Run 1 tick unpaused to settle initial physics positions
			get_tree().paused = false
			await get_tree().physics_frame
			get_tree().paused = true

			var obs: Array = _compute_observation()
			var info: Dictionary = _get_info()
			_send_response({
				"type": "reset_result",
				"observation": obs,
				"info": info
			})
			_is_processing_step = false

		"step":
			_is_processing_step = true
			var action: Array = msg.get("action", [0.0, 0.0, 0.0])
			step_count += 1

			# 1. Apply action
			_apply_action(action)

			# 2. Advance physics for exactly ticks_per_step frames
			get_tree().paused = false
			for i in range(ticks_per_step):
				await get_tree().physics_frame
			get_tree().paused = true

			# 3. Evaluate results
			var obs: Array = _compute_observation()
			var rew: float = _compute_reward(action)
			var terminated: bool = _is_terminated()
			var truncated: bool = (step_count >= max_episode_steps) or _is_truncated()
			var info: Dictionary = _get_info()

			_send_response({
				"type": "step_result",
				"observation": obs,
				"reward": rew,
				"terminated": terminated,
				"truncated": truncated,
				"info": info
			})
			_is_processing_step = false

		"close":
			print("[TrainingEnvBase] Close command received. Quitting...")
			get_tree().quit(0)

func _send_response(dict: Dictionary) -> void:
	if not client or client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var json_str: String = JSON.stringify(dict)
	var bytes: PackedByteArray = json_str.to_utf8_buffer()
	client.put_u32(bytes.size())
	client.put_data(bytes)

# --- Virtual Methods to be overridden by Stage Implementations ---

func _on_arena_reset(_seed_val: int, _difficulty: float) -> void:
	pass

func _apply_action(action: Array) -> void:
	if not amr:
		return
	var v_lin: float = float(action[0]) if action.size() > 0 else 0.0
	var v_ang: float = float(action[1]) if action.size() > 1 else 0.0
	var trigger: float = float(action[2]) if action.size() > 2 else 0.0

	# Map normalized inputs to physical robot velocity
	var lin_vel = v_lin * amr.max_speed
	var ang_vel = v_ang * amr.turn_speed

	if amr.has_method("set_rl_control"):
		amr.set_rl_control(lin_vel, ang_vel)

	# Trigger grasp / stow / place if above threshold
	if trigger > 0.5:
		if amr.has_method("trigger_rl_action"):
			amr.trigger_rl_action()

func _compute_observation() -> Array:
	# Default 13-dimensional zero vector
	var obs: Array = []
	for i in range(13):
		obs.append(0.0)
	return obs

func _compute_reward(_action: Array) -> float:
	return 0.0

func _is_terminated() -> bool:
	return false

func _is_truncated() -> bool:
	return false

func _get_info() -> Dictionary:
	return {"step": step_count, "difficulty": current_difficulty}
