@tool
extends Node2D
## Non-interactive trim drawn inside its owner's bounds.
var owner_control: Control
var brass: Color
var amber: Color
var hazard := false

func setup(control: Control, edge: Color, warning: Color, striped: bool) -> void:
	owner_control = control
	brass = edge
	amber = warning
	hazard = striped
	control.resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(owner_control): return
	var bounds := owner_control.size
	if bounds.x < 24 or bounds.y < 24: return
	var inset := 5.0
	var cut := 7.0
	var end := bounds - Vector2.ONE * inset
	var points := PackedVector2Array([Vector2(inset + cut, inset), Vector2(end.x - cut, inset), Vector2(end.x, inset + cut), Vector2(end.x, end.y - cut), Vector2(end.x - cut, end.y), Vector2(inset + cut, end.y), Vector2(inset, end.y - cut), Vector2(inset, inset + cut), Vector2(inset + cut, inset)])
	draw_polyline(points, Color(brass, 0.45), 1.0, true)
	if hazard:
		for x in range(16, int(bounds.x) - 20, 16):
			draw_line(Vector2(x, bounds.y - 12), Vector2(x + 6, bounds.y - 6), amber, 3.0, true)
