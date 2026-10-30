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
	draw_rect(Rect2(Vector2.ZERO, size), Color("14110d"))
	# Quiet contour bands suggest terrain without competing with the route graph.
	for band in range(18):
		var contour := PackedVector2Array()
		for step in range(33):
			var x := float(step) * size.x / 32
			var y := band * 100.0 + sin(x * .012 + band * .7) * 28 + sin(x * .025 + band) * 12
			contour.append(Vector2(x, y))
		draw_polyline(contour, Color(.64, .36, .12, .13), 1.0, true)
	for room in rooms:
		if int(room.lane) == 0:
			var p := point(room)
			draw_string(UI.font(true), Vector2(12, p.y + 7), "%02d" % (int(room.row) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UI.BRONZE)
		for next_id in room.links:
			var next: Dictionary = rooms[next_id]
			var visited: bool = room.id in cleared and (next_id in cleared or next_id == current)
			var start := point(room)
			var finish := point(next)
			var available: bool = int(room.id) == current and current in cleared
			var color := Color("6b4825")
			if visited: color = Color("bd9654")
			if available: color = Color("ffae42")
			draw_line(start, finish, Color(.65, .34, .08, .12), 12, true)
			draw_line(start, finish, color, 4 if available else 2, true)
			var middle := start.lerp(finish, .5)
			var direction := (finish - start).normalized()
			var side := direction.orthogonal()
			# Arrows communicate bottom-to-top travel, including diagonal branches.
			draw_polyline(PackedVector2Array([middle - direction * 7 + side * 5,
				middle, middle - direction * 7 - side * 5]), color, 2, true)
	if current >= 0:
		var p := point(rooms[current])
		draw_string(UI.font(true), p + Vector2(-62, -48), "CURRENT ROOM", HORIZONTAL_ALIGNMENT_CENTER, 124, 13, UI.GOLD)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
