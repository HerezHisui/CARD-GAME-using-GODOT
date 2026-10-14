extends Control
## A board of connected school rooms. Coordinates scale with the available space.
var rooms: Array = []
var current := -1
var cleared: Array = []

func point(room: Dictionary) -> Vector2:
	return Vector2(100 + float(room.lane) * (size.x - 200) / 2.0, size.y - 100 - float(room.row) * (size.y - 210) / float(maxi(1, int(rooms.back().row))))

func _draw() -> void:
	for room in rooms:
		for next_id in room.links:
			var next: Dictionary = rooms[next_id]
			var visited: bool = room.id in cleared and (next_id in cleared or next_id == current)
			var start := point(room)
			var finish := point(next)
			var distance := start.distance_to(finish)
			for step in range(int(distance / 14)):
				var t := float(step * 14) / distance
				draw_line(start.lerp(finish, t), start.lerp(finish, minf(1, t + 7 / distance)), Color("c9aa70") if visited else Color("566572"), 3.0 if visited else 2.0, true)
	for room in rooms:
		var p := point(room)
		draw_circle(p, 47, Color("101e29"))
		draw_arc(p, 48, 0, TAU, 64, Color("c9aa70") if room.id == current else Color("344550"), 2, true)
		if room.id == current:
			draw_circle(p + Vector2(0, -59), 5, Color("75d6c6"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
