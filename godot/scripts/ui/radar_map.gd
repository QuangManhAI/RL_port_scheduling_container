class_name RadarMap
extends Control

## Real-Time 2D Warehouse Radar / Minimap for AMR Fleet Tracking.
## Renders 4 Zoned Inventory Areas (A, B, C, D), Inbound/Outbound Docks, and AMR blips.

const WORLD_WIDTH: float = 100.0
const WORLD_HEIGHT: float = 70.0

var amr_positions: Dictionary = {
	"AMR-01": {"pos": Vector2(-25, 0), "rot": 0.0, "state": "CRUISING", "color": Color(0.0, 0.9, 1.0)},
	"AMR-02": {"pos": Vector2(0, -25), "rot": 1.57, "state": "CRUISING", "color": Color(0.2, 1.0, 0.4)},
	"AMR-03": {"pos": Vector2(18, -10), "rot": 0.0, "state": "STANDBY", "color": Color(1.0, 0.75, 0.1)},
	"AMR-04": {"pos": Vector2(-20, -28), "rot": 0.0, "state": "CHARGING", "color": Color(1.0, 0.4, 0.1)},
}

var _pulse_phase: float = 0.0

func _process(delta: float) -> void:
	_pulse_phase += delta * 2.5
	queue_redraw()

func update_robot(robot_id: String, world_pos_3d: Vector3, rotation_y: float, state_str: String, col: Color) -> void:
	amr_positions[robot_id] = {
		"pos": Vector2(world_pos_3d.x, world_pos_3d.z),
		"rot": rotation_y,
		"state": state_str,
		"color": col
	}

func _draw() -> void:
	var rect_size: Vector2 = size
	# Background panel
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.04, 0.07, 0.12, 0.92), true)
	draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0.18, 0.4, 0.65, 0.8), false, 1.5)

	# Title
	draw_string(ThemeDB.fallback_font, Vector2(8, 15), "2D ZONED FLEET RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.85, 1.0, 0.95))

	var pad: float = 16.0
	var radar_rect: Rect2 = Rect2(pad, pad + 6, rect_size.x - pad * 2.0, rect_size.y - pad * 2.0 - 6)

	var to_radar = func(w_x: float, w_z: float) -> Vector2:
		var norm_x: float = (w_x + WORLD_WIDTH * 0.5) / WORLD_WIDTH
		var norm_y: float = (w_z + WORLD_HEIGHT * 0.5) / WORLD_HEIGHT
		return Vector2(
			radar_rect.position.x + norm_x * radar_rect.size.x,
			radar_rect.position.y + norm_y * radar_rect.size.y
		)

	# Draw 4 Colored Inventory Zones: A, B, C, D
	var zones_draw = [
		{"name": "ZONE A (FMCG)", "x": -24.0, "col": Color(0.0, 0.85, 1.0, 0.18), "border": Color(0.0, 0.85, 1.0, 0.6)},
		{"name": "ZONE B (TECH)", "x": -8.0, "col": Color(0.1, 0.95, 0.45, 0.18), "border": Color(0.1, 0.95, 0.45, 0.6)},
		{"name": "ZONE C (PHARMA)", "x": 8.0, "col": Color(0.75, 0.25, 1.0, 0.18), "border": Color(0.75, 0.25, 1.0, 0.6)},
		{"name": "ZONE D (BULK)", "x": 24.0, "col": Color(1.0, 0.65, 0.1, 0.18), "border": Color(1.0, 0.65, 0.1, 0.6)},
	]

	for z in zones_draw:
		var tl = to_radar.call(z["x"] - 5.5, -16.0)
		var br = to_radar.call(z["x"] + 5.5, 16.0)
		draw_rect(Rect2(tl, br - tl), z["col"], true)
		draw_rect(Rect2(tl, br - tl), z["border"], false, 1.0)
		draw_string(ThemeDB.fallback_font, tl + Vector2(2, 9), z["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, z["border"])

	# Inbound Dock (Top)
	var in_tl = to_radar.call(-20.0, -33.0)
	var in_br = to_radar.call(20.0, -28.0)
	draw_rect(Rect2(in_tl, in_br - in_tl), Color(0.1, 0.6, 0.9, 0.35), true)
	draw_rect(Rect2(in_tl, in_br - in_tl), Color(0.2, 0.8, 1.0, 0.8), false, 1.0)
	draw_string(ThemeDB.fallback_font, in_tl + Vector2(4, 8), "📥 INBOUND DOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.9, 1.0))

	# Outbound Pick Stations (Bottom)
	var out_tl = to_radar.call(-16.0, 24.0)
	var out_br = to_radar.call(16.0, 30.0)
	draw_rect(Rect2(out_tl, out_br - out_tl), Color(0.1, 0.8, 0.4, 0.35), true)
	draw_rect(Rect2(out_tl, out_br - out_tl), Color(0.2, 0.95, 0.5, 0.8), false, 1.0)
	draw_string(ThemeDB.fallback_font, out_tl + Vector2(4, 8), "📤 OUTBOUND PICK & PACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 1.0, 0.6))

	# 4-Way Intersection Zone
	var int_tl = to_radar.call(-5.0, -5.0)
	var int_br = to_radar.call(5.0, 5.0)
	draw_rect(Rect2(int_tl, int_br - int_tl), Color(1.0, 0.6, 0.0, 0.25), true)
	draw_rect(Rect2(int_tl, int_br - int_tl), Color(1.0, 0.7, 0.0, 0.8), false, 1.2)

	# AMR Fleet Blips
	var pulse_radius: float = 3.5 + sin(_pulse_phase) * 1.5
	for id in amr_positions.keys():
		var data = amr_positions[id]
		var screen_pt: Vector2 = to_radar.call(data["pos"].x, data["pos"].y)
		var c: Color = data["color"]

		draw_arc(screen_pt, pulse_radius + 2.0, 0, TAU, 16, Color(c.r, c.g, c.b, 0.4), 1.0)
		draw_circle(screen_pt, 3.5, c)

		var rot: float = data["rot"]
		var forward: Vector2 = Vector2(-sin(rot), -cos(rot)).normalized() * 6.5
		draw_line(screen_pt, screen_pt + forward, Color(1, 1, 1, 0.9), 1.5)

		draw_string(ThemeDB.fallback_font, screen_pt + Vector2(5, 3), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.95, 1.0, 0.9))
