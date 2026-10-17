extends Control
## Static route drawing. Only resize and route changes require a redraw.
const UI = preload("res://scripts/ui_theme.gd")
var rooms: Array = []
var current := -1
var cleared: Array = []

func point(room: Dictionary) -> Vector2:
	var spread := minf(560, size.x - 190)
	return Vector2(size.x / 2 + (float(room.lane) - 1) * spread / 2, size.y - 100 - float(room.row) * (size.y - 210) / float(maxi(1, int(rooms.back().row))))

func _draw() -> void:
	if rooms.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO, size), UI.INSET)
	for y in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(UI.BRONZE, 0.035), 1)
	for room in rooms:
		if int(room.lane) == 0:
			var p := point(room)
			draw_string(UI.font(true), Vector2(12, p.y + 7), "%02d" % (int(room.row) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.BRONZE)
		for next_id in room.links:
			var next: Dictionary = rooms[next_id]
			var visited: bool = room.id in cleared and (next_id in cleared or next_id == current)
			var start := point(room)
			var finish := point(next)
			draw_line(start, finish, UI.RAISED, 7, true)
			draw_line(start, finish, UI.GOLD if visited else UI.BRONZE.darkened(0.35), 2, true)
			draw_circle(start.lerp(finish, 0.5), 3, UI.GOLD if visited else UI.BRONZE)
	if current >= 0:
		var p := point(rooms[current])
		draw_string(UI.font(true), p + Vector2(-62, -48), "CURRENT ROOM", HORIZONTAL_ALIGNMENT_CENTER, 124, 13, UI.GOLD)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
