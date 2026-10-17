extends Control
const UI = preload("res://scripts/ui_theme.gd")
## Temporary native scenery leaves room for the user's final title illustration.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	# Static instrument-panel framing; redraw only when the viewport changes.
	var frame := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	draw_rect(frame, UI.INSET)
	draw_rect(frame, UI.BRONZE, false, 3)
	draw_rect(frame.grow(-9), UI.GOLD, false, 1)
	for y in range(20, int(size.y) - 20, 5):
		draw_line(Vector2(16, y), Vector2(size.x - 16, y), Color(UI.GOLD, 0.035), 1)
	for corner in [Vector2(20, 20), Vector2(size.x - 20, 20), Vector2(20, size.y - 20), size - Vector2(20, 20)]:
		draw_circle(corner, 5, UI.BRONZE)
		draw_line(corner - Vector2(3, 0), corner + Vector2(3, 0), UI.INSET, 2)
	for x in range(35, int(size.x) - 50, 24):
		draw_line(Vector2(x, size.y - 25), Vector2(x + 12, size.y - 13), UI.BRONZE, 5)
	var center := Vector2(size.x * 0.58, size.y * 0.25)
	for ring in range(12, 0, -1):
		draw_circle(center, 48 + ring * 8, Color(UI.GOLD, 0.016))
	draw_circle(center, 48, UI.TEXT)
	for i in range(36):
		var x := fmod(i * 97.0, maxf(1, size.x))
		var y := fmod(i * 43.0, maxf(1, size.y * 0.65))
		draw_circle(Vector2(x, y), 1.2, UI.MUTED)
	var building := Rect2(size.x * 0.1, size.y * 0.5, size.x * 0.8, size.y * 0.4)
	draw_rect(building, UI.PANEL)
	draw_rect(Rect2(building.position - Vector2(12, 9), Vector2(building.size.x + 24, 12)), UI.BRONZE)
	for row in range(3):
		for column in range(6):
			var window := Rect2(building.position + Vector2(22 + column * (building.size.x - 35) / 6, 22 + row * building.size.y / 3.5), Vector2(17, 27))
			draw_rect(window, UI.GOLD if (row + column) % 4 == 0 else UI.RAISED)
	draw_rect(Rect2(size.x * 0.43, size.y * 0.75, size.x * 0.16, size.y * 0.15), UI.INSET)
	draw_line(Vector2(0, size.y * 0.9), Vector2(size.x, size.y * 0.9), UI.BRONZE, 2)
