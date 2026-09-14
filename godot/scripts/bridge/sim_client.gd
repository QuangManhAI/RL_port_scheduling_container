class_name SimClient
extends Node

## SimClient manages the WebSocket connection between Godot and the Python RL backend.

signal connected_to_server
signal disconnected_from_server
signal state_received(state_dict: Dictionary)

@export var server_url: String = "ws://127.0.0.1:9090"
@export var reconnect_interval: float = 2.0

var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_connected: bool = false
var _reconnect_timer: float = 0.0

func _ready() -> void:
	connect_to_bridge()

func connect_to_bridge() -> void:
	var err: Error = _ws.connect_to_url(server_url)
	if err != OK:
		push_warning("SimClient: Unable to initiate connection to %s (Error %d)" % [server_url, err])

func _process(delta: float) -> void:
	_ws.poll()
	var state: WebSocketPeer.State = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_is_connected = true
			connected_to_server.emit()
		
		while _ws.get_available_packet_count() > 0:
			var packet: PackedByteArray = _ws.get_packet()
			var msg_str: String = packet.get_string_from_utf8()
			_handle_message(msg_str)

	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			disconnected_from_server.emit()

		_reconnect_timer += delta
		if _reconnect_timer >= reconnect_interval:
			_reconnect_timer = 0.0
			connect_to_bridge()

func _handle_message(json_str: String) -> void:
	var json: JSON = JSON.new()
	var err: Error = json.parse(json_str)
	if err == OK and json.data is Dictionary:
		state_received.emit(json.data)

func send_command(cmd: Dictionary) -> void:
	if _is_connected and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str: String = JSON.stringify(cmd)
		_ws.send_text(json_str)

func request_step() -> void:
	send_command({"command": "step"})

func request_reset() -> void:
	send_command({"command": "reset"})

func is_connected_to_server() -> bool:
	return _is_connected
