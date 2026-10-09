extends Control
## A board of connected school rooms. Coordinates scale with the available space.
var rooms: Array = []
var current := -1
var cleared: Array = []

func point(room: Dictionary) -> Vector2:
	return Vector2(85 + float(room.row) * (size.x - 170) / float(maxi(1, int(rooms.back().row))), 80 + float(room.lane) * (size.y - 160) / 2.0)

func _draw() -> void:
	for room in rooms:
		for next_id in room.links:
			var next: Dictionary = rooms[next_id]
			var visited: bool = room.id in cleared and (next_id in cleared or next_id == current)
			draw_line(point(room), point(next), Color("c9aa70") if visited else Color("344550"), 4.0 if visited else 2.0, true)
	for room in rooms:
		var p := point(room)
		draw_circle(p, 47, Color("101e29"))
		draw_arc(p, 48, 0, TAU, 64, Color("c9aa70") if room.id == current else Color("344550"), 2, true)
		if room.id == current:
			draw_circle(p + Vector2(0, -59), 5, Color("75d6c6"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
