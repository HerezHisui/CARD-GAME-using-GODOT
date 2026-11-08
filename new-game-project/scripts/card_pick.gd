extends RefCounted
## Card picker tiles: one click selects a card, a double click (or Enter on the focused card) chooses it.
## The tiles have no "Choose" button any more.
const UI = preload("res://scripts/ui_theme.gd")
const Sfx = preload("res://scripts/sfx_call.gd")
const HINT := "Double-click a card to choose"

## Makes a card tile pickable. A tile with meta "pick_disabled" ignores the double click and Enter.
static func make_pickable(tile: Control, card_name: String, action: Callable) -> void:
	tile.set_meta("pick_name", card_name)
	tile.focus_mode = Control.FOCUS_ALL
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Clicks on the card face pass through to the tile.
	for face in tile.find_children("*", "TextureRect", true, false):
		face.mouse_filter = Control.MOUSE_FILTER_PASS
	var mark := Control.new()
	mark.name = "SelectMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.hide()
	tile.add_child(mark)
	mark.draw.connect(func(): _draw_mark(mark))
	tile.focus_entered.connect(func(): select(tile))
	tile.gui_input.connect(func(event: InputEvent): _tile_input(event, tile, action))

static func _tile_input(event: InputEvent, tile: Control, action: Callable) -> void:
	var choose := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		select(tile)
		choose = event.double_click
	elif event.is_action_pressed("ui_accept"):
		choose = true
	if not choose: return
	tile.accept_event()
	if tile.get_meta("pick_disabled", false): return
	Sfx.play("choice_confirm")
	action.call()

## Shows the selected style on this tile and hides it on the other tiles in the same row.
static func select(tile: Control) -> void:
	if not is_instance_valid(tile) or tile.get_parent() == null: return
	for other in tile.get_parent().get_children():
		var other_mark := other.get_node_or_null("SelectMark") as Control
		if other_mark: other_mark.visible = other == tile
	var mark := tile.get_node_or_null("SelectMark") as Control
	if mark: mark.queue_redraw()

## Selected style: crimson line around the whole tile and gold corner brackets.
static func _draw_mark(mark: Control) -> void:
	var tile := mark.get_parent() as Control
	if tile == null: return
	# The mark sits inside the tile's margins, so move back to the tile's own corner.
	var area := Rect2(-mark.position, tile.size).grow(-1)
	var c := 10.0
	var a := area.position
	var b := area.end
	var line := PackedVector2Array([Vector2(a.x + c, a.y), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c),
		Vector2(b.x, b.y - c), Vector2(b.x - c, b.y), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c),
		Vector2(a.x, a.y + c), Vector2(a.x + c, a.y)])
	mark.draw_polyline(line, UI.ACTION, 3.0, true)
	# Gold brackets just inside the top-left and bottom-right corners.
	var inner := area.grow(-6)
	var arm := 16.0
	var p := inner.position
	var q := inner.end
	mark.draw_polyline(PackedVector2Array([Vector2(p.x, p.y + arm), p, Vector2(p.x + arm, p.y)]), UI.GOLD, 3.0)
	mark.draw_polyline(PackedVector2Array([Vector2(q.x, q.y - arm), q, Vector2(q.x - arm, q.y)]), UI.GOLD, 3.0)

## The line under the picker title: the caller's own text, plus the hint when both fit on one line.
static func subtitle(text: String, width: float) -> String:
	if text.is_empty(): return HINT
	var both := text + " · " + HINT
	if UI.font().get_string_size(both, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x <= width: return both
	return text
