extends Control
## Edge mist keeps nodes and route connections readable, with the boss region emphasized.
var phase := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	phase = fmod(phase + delta * 0.16, TAU)
	queue_redraw()

func _draw() -> void:
	# Transparent bands stay on the outskirts of the canvas, away from button labels.
	for index in 7:
		var width := 16.0 + index * 15.0
		var opacity := 0.035 * (1.0 - float(index) / 9.0)
		var drift := sin(phase + index * 0.5) * 9
		draw_rect(Rect2(drift, 0, width, size.y), Color(0.7, 0.73, 0.77, opacity))
		draw_rect(Rect2(size.x - width + drift, 0, width, size.y), Color(0.7, 0.73, 0.77, opacity))
		draw_rect(Rect2(0, -drift, size.x, width), Color(0.7, 0.73, 0.77, opacity))
