extends StyleBox
## The line under a dark panel title: a thin gold line that ends in a small diamond on the right.
var color := Color.WHITE

func _get_minimum_size() -> Vector2:
	return Vector2(0, 10)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var mid_y := rect.position.y + rect.size.y / 2
	var tip := rect.end.x - 1
	# Diamond: 5 px from its centre to each point.
	var centre := Vector2(tip - 5, mid_y)
	RenderingServer.canvas_item_add_line(to_canvas_item, Vector2(rect.position.x, mid_y),
		Vector2(centre.x - 7, mid_y), color, 1.0, true)
	var diamond := PackedVector2Array([centre + Vector2(0, -5), centre + Vector2(5, 0),
		centre + Vector2(0, 5), centre + Vector2(-5, 0)])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, diamond, PackedColorArray([color]))
