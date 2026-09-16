class_name NeuralPolicy
extends RefCounted

## Zero-latency, native in-engine neural inference evaluator for Godot 4.
## Executes trained PyTorch/SB3 MLP policies directly in GDScript without Python or TCP sockets.

var w0: Array = []
var b0: Array = []
var w1: Array = []
var b1: Array = []
var w2: Array = []
var b2: Array = []
var is_loaded: bool = false

func load_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("[NeuralPolicy] Policy file not found: " + path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		push_error("[NeuralPolicy] Failed to parse JSON policy: " + json.get_error_message())
		return false

	var data = json.data
	var layers = data.get("layers", [])
	if layers.size() < 3:
		push_error("[NeuralPolicy] Invalid layer count in policy")
		return false

	w0 = layers[0]["weight"]
	b0 = layers[0]["bias"]
	w1 = layers[1]["weight"]
	b1 = layers[1]["bias"]
	w2 = layers[2]["weight"]
	b2 = layers[2]["bias"]
	is_loaded = true
	print("[NeuralPolicy] Loaded native policy from: %s" % path)
	return true

## High-speed forward pass: Linear(in_dim->64) -> Tanh -> Linear(64->64) -> Tanh -> Linear(64->3)
func predict(obs: Array) -> Array:
	if not is_loaded or obs.is_empty():
		return [0.0, 0.0, 0.0]

	var in_dim: int = w0[0].size() if w0.size() > 0 else 13
	if obs.size() < in_dim:
		return [0.0, 0.0, 0.0]

	# Hidden Layer 1 (64 neurons)
	var h1: Array = []
	for i in range(64):
		var sum_val: float = float(b0[i])
		var row: Array = w0[i]
		for j in range(in_dim):
			sum_val += float(row[j]) * float(obs[j])
		h1.append(tanh(sum_val))

	# Hidden Layer 2 (64 neurons)
	var h2: Array = []
	for i in range(64):
		var sum_val: float = float(b1[i])
		var row: Array = w1[i]
		for j in range(64):
			sum_val += float(row[j]) * float(h1[j])
		h2.append(tanh(sum_val))

	# Output Layer (3 actions: v_lin, v_ang, trigger), clipped to [-1.0, 1.0]
	var action: Array = []
	for i in range(3):
		var sum_val: float = float(b2[i])
		var row: Array = w2[i]
		for j in range(64):
			sum_val += float(row[j]) * float(h2[j])
		action.append(clampf(sum_val, -1.0, 1.0))

	return action
