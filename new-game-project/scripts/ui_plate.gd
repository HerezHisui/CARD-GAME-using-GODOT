@tool
extends Node2D
## Non-interactive trim drawn inside its owner's bounds.
var owner_control: Control
var brass: Color
var amber: Color
var hazard := false
## Dark game panels also get corner brackets and a faint diagonal hatch.
var chrome := false
const UI = preload("res://scripts/ui_theme.gd")

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
	draw_polyline(points, Color(UI.GOLD, 0.5) if chrome else Color(brass, 0.45), 1.0, true)
	if chrome: _draw_chrome(bounds, inset)
	if hazard:
		for x in range(16, int(bounds.x) - 20, 16):
			draw_line(Vector2(x, bounds.y - 12), Vector2(x + 6, bounds.y - 6), amber, 3.0, true)

## Faint diagonal hatch over the fill and small gold brackets in the four corners.
func _draw_chrome(bounds: Vector2, inset: float) -> void:
	var left := inset + 2
	var right := bounds.x - inset - 2
	var top := inset + 2
	var bottom := bounds.y - inset - 2
	var height := bottom - top
	var hatch := Color(UI.TEXT, 0.025)
	# 45 degree lines from bottom-left to top-right, cut to the inner rectangle.
	for x0 in range(int(left - height), int(right), 14):
		var a := Vector2(x0, bottom)
		var b := Vector2(x0 + height, top)
		if a.x < left: a = Vector2(left, bottom - (left - a.x))
		if b.x > right: b = Vector2(right, top + (b.x - right))
		if a.x < b.x: draw_line(a, b, hatch, 1.0)
	var arm := 14.0
	var edge := inset + 6
	var corners := [Vector2(edge, edge), Vector2(bounds.x - edge, edge),
		Vector2(edge, bounds.y - edge), Vector2(bounds.x - edge, bounds.y - edge)]
	for corner: Vector2 in corners:
		var sx := 1.0 if corner.x < bounds.x / 2 else -1.0
		var sy := 1.0 if corner.y < bounds.y / 2 else -1.0
		var bracket := PackedVector2Array([corner + Vector2(0, arm * sy), corner, corner + Vector2(arm * sx, 0)])
		draw_polyline(bracket, UI.GOLD, 2.0)
