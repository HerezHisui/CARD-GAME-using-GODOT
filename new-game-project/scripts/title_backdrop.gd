extends Control
## Temporary native scenery leaves room for the user's final title illustration.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var center := Vector2(size.x * 0.58, size.y * 0.25)
	for ring in range(12, 0, -1):
		draw_circle(center, 48 + ring * 8, Color(0.36, 0.58, 0.60, 0.016))
	draw_circle(center, 48, Color("a1c7be"))
	for i in range(36):
		var x := fmod(i * 97.0, maxf(1, size.x))
		var y := fmod(i * 43.0, maxf(1, size.y * 0.65))
		draw_circle(Vector2(x, y), 1.2, Color("829ba6"))
	var building := Rect2(size.x * 0.1, size.y * 0.5, size.x * 0.8, size.y * 0.4)
	draw_rect(building, Color("152430"))
	draw_rect(Rect2(building.position - Vector2(12, 9), Vector2(building.size.x + 24, 12)), Color("344550"))
	for row in range(3):
		for column in range(6):
			var window := Rect2(building.position + Vector2(22 + column * (building.size.x - 35) / 6, 22 + row * building.size.y / 3.5), Vector2(17, 27))
			draw_rect(window, Color("c9aa70") if (row + column) % 4 == 0 else Color("304956"))
	draw_rect(Rect2(size.x * 0.43, size.y * 0.75, size.x * 0.16, size.y * 0.15), Color("080f19"))
	draw_line(Vector2(0, size.y * 0.9), Vector2(size.x, size.y * 0.9), Color("344550"), 2)
