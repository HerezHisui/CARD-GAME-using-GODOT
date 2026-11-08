extends StyleBox
## Focus mark of the shared button: a second gold line around the button
## and a small gold triangle on its left, so keyboard and controller focus is easy to see.
var color := Color.WHITE
## Size of the 45 degree corner cut, the same as the button's own corners.
var cut := 8.0

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	# The second line sits 4 px outside the button's own outline.
	var outer := rect.grow(4)
	var c := cut + 2.0
	var end := outer.end
	var start := outer.position
	var points := PackedVector2Array([
		Vector2(start.x + c, start.y), Vector2(end.x - c, start.y), Vector2(end.x, start.y + c),
		Vector2(end.x, end.y - c), Vector2(end.x - c, end.y), Vector2(start.x + c, end.y),
		Vector2(start.x, end.y - c), Vector2(start.x, start.y + c), Vector2(start.x + c, start.y)])
	RenderingServer.canvas_item_add_polyline(to_canvas_item, points, PackedColorArray([color]), 2.0, true)
	# Small triangle inside the left padding, pointing at the text.
	var mid_y := rect.position.y + rect.size.y / 2
	var x := rect.position.x + 7
	var marker := PackedVector2Array([Vector2(x, mid_y - 6), Vector2(x + 7, mid_y), Vector2(x, mid_y + 6)])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, marker, PackedColorArray([color]))
