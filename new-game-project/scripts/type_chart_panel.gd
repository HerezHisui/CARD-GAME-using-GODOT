extends Panel
## A read-only reference to the combat engine's element relationships.
const BattleEngine = preload("res://scripts/battle_engine.gd")
const UI = preload("res://scripts/ui_theme.gd")
const ELEMENTS := ["evac", "clearance", "douse", "brace", "earthquake", "flood", "fire", "typhoon"]
const WIDTH := 260.0
const EXPANDED_HEIGHT := 348.0
const HEADER_HEIGHT := 34.0
const STRONG := Color("ed7770")
const WEAK := Color("72b9ef")

var body: Control
var ring: Control
var description: Label
var toggle: Button
var pills: Dictionary = {}
var hovered := ""
var pinned := ""
var collapsed := false
var forced_compact := false
var game: Node
var _last_layout := Vector3.ZERO

func _ready() -> void:
	theme = UI.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UI.panel(UI.INSET, UI.GOLD, 0))
	size = Vector2(WIDTH, EXPANDED_HEIGHT)
	var heading := _label(self, "TYPES", Vector2(12, 2), Vector2(190, 30), 23)
	heading.add_theme_color_override("font_color", UI.GOLD)
	toggle = Button.new()
	toggle.name = "CollapseButton"
	toggle.position = Vector2(220, 3)
	toggle.size = Vector2(32, 28)
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := UI.PANEL if state == "normal" else UI.RAISED
		toggle.add_theme_stylebox_override(state, UI.panel(fill, UI.GOLD, 0))
	toggle.pressed.connect(func(): set_collapsed(not collapsed))
	add_child(toggle)
	body = Control.new()
	body.name = "Body"
	body.position = Vector2(0, HEADER_HEIGHT)
	body.size = Vector2(WIDTH, EXPANDED_HEIGHT - HEADER_HEIGHT)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	ring = Control.new()
	ring.name = "Ring"
	ring.position = Vector2(0, 16)
	ring.size = Vector2(WIDTH, 194)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(_draw_ring)
	body.add_child(ring)
	_label(body, "RESPONSE", Vector2(8, -2), Vector2(110, 20), 13)
	var right := _label(body, "DISASTER", Vector2(142, -2), Vector2(110, 20), 13)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in ELEMENTS.size():
		_build_pill(ELEMENTS[i], i)
	description = _label(body, "Hover an element", Vector2(10, 212), Vector2(240, 76), 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	for i in 3:
		var key := _label(body, ["2x", "0.5x", "1x"][i], Vector2(38 + i * 79, 288), Vector2(55, 22), 15)
		key.add_theme_color_override("font_color", [STRONG, WEAK, UI.MUTED][i])
	set_collapsed(false)

func _label(parent: Node, text: String, at: Vector2, bounds: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = bounds
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI.font())
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _build_pill(element: String, index: int) -> void:
	var pill := Button.new()
	pill.name = element.capitalize()
	pill.text = element.capitalize()
	pill.focus_mode = Control.FOCUS_NONE
	var row := index % 4
	var x: float = [78.0, 51.0, 51.0, 78.0][row] if index < 4 else [182.0, 209.0, 209.0, 182.0][row]
	var width := 94.0 if element == "earthquake" else 76.0
	pill.position = Vector2(x - width / 2.0, 6 + row * 51)
	pill.size = Vector2(width, 28)
	pill.add_theme_font_override("font", UI.font())
	pill.add_theme_font_size_override("font_size", 16)
	var color := UI.affinity_color(element)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := UI.panel(color.darkened(0.12), color.lightened(0.3), 3)
		style.set_corner_radius_all(12)
		pill.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		pill.add_theme_color_override(state, UI.BACKGROUND)
	pill.mouse_entered.connect(func(): select_element(element))
	pill.mouse_exited.connect(func(): select_element(pinned))
	pill.pressed.connect(func():
		pinned = "" if pinned == element else element
		select_element(pinned))
	ring.add_child(pill)
	pills[element] = pill

func relations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attacker in ELEMENTS:
		for target in BattleEngine.TYPE_CHART.get(attacker, {}):
			result.append({"attacker": attacker, "target": target,
				"multiplier": float(BattleEngine.TYPE_CHART[attacker][target])})
	return result

func sentence(element: String) -> String:
	if element not in ELEMENTS: return "Hover an element"
	var incoming := {"strong": [], "weak": []}
	var outgoing := {"strong": [], "weak": []}
	for relation in relations():
		var category := "strong" if relation.multiplier > 1.0 else "weak"
		if relation.target == element: incoming[category].append(str(relation.attacker).capitalize())
		if relation.attacker == element: outgoing[category].append(str(relation.target).capitalize())
	return "%s takes 2x from %s, 0.5x from %s.\n%s deals 2x to %s, 0.5x to %s." % [
		element.capitalize(), ", ".join(incoming.strong), ", ".join(incoming.weak),
		element.capitalize(), ", ".join(outgoing.strong), ", ".join(outgoing.weak)]

func select_element(element: String) -> void:
	hovered = element if element in ELEMENTS else ""
	for key in pills:
		pills[key].modulate.a = 1.0 if hovered.is_empty() or key == hovered else 0.35
	description.text = sentence(hovered)
	ring.queue_redraw()

func set_collapsed(value: bool) -> void:
	collapsed = value
	if not is_instance_valid(body): return
	body.visible = not value
	size = Vector2(WIDTH, HEADER_HEIGHT if value else EXPANDED_HEIGHT)
	toggle.text = "+" if value else "-"
	toggle.tooltip_text = "Expand type chart" if value else "Collapse type chart"
	_place_view_buttons()

func _draw_ring() -> void:
	ring.draw_arc(Vector2(130, 96), 78, 0, TAU, 64, UI.BRONZE.darkened(0.55), 1, true)
	for relation in relations():
		var active: bool = relation.attacker == hovered or relation.target == hovered
		if relation.multiplier < 1.0 and not active: continue
		var color := STRONG if relation.multiplier > 1.0 else WEAK
		if not hovered.is_empty() and not active: color.a = 0.12
		_draw_arrow(pills[relation.attacker].get_rect(), pills[relation.target].get_rect(), color)

func _draw_arrow(source: Rect2, target: Rect2, color: Color) -> void:
	var a := source.get_center()
	var b := target.get_center()
	var delta := b - a
	var normal := delta.normalized().orthogonal()
	var bend := normal * 15.0
	var start := _edge(source, delta + bend)
	var finish := _edge(target, -delta + bend)
	var control := (start + finish) * 0.5 + bend
	var points := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		points.append(start.bezier_interpolate(control, control, finish, t))
	ring.draw_polyline(points, color, 1.8, true)
	var direction := (finish - points[-2]).normalized()
	ring.draw_colored_polygon(PackedVector2Array([
		finish, finish - direction * 7 + direction.orthogonal() * 3.5,
		finish - direction * 7 - direction.orthogonal() * 3.5]), color)

func _edge(rect: Rect2, direction: Vector2) -> Vector2:
	var extent := rect.size / 2.0 + Vector2(3, 3)
	var distance := minf(extent.x / maxf(absf(direction.x), 0.001),
		extent.y / maxf(absf(direction.y), 0.001))
	return rect.get_center() + direction * distance

func bind_hud(owner_game: Node) -> void:
	game = owner_game
	_last_layout = Vector3.ZERO
	_layout_hud()

func _process(_delta: float) -> void:
	if is_instance_valid(game): _layout_hud()

func _layout_hud() -> void:
	var top := 60.0
	var hud := game.get_node("HUD/Root")
	for plate: Control in [game._player_hp_ui, game._enemy_hp_ui,
			hud.get_node_or_null("VersusEnergy"), hud.get_node_or_null("VersusTension")]:
		if not is_instance_valid(plate) or not plate.is_visible_in_tree(): continue
		var rect := plate.get_global_rect()
		if rect.position.x < WIDTH + 16 and rect.end.x > 16:
			top = maxf(top, rect.end.y + 8)
	var view_height := get_viewport_rect().size.y
	var layout := Vector3(top, view_height, float(game.encounter_kind == "versus"))
	if layout != _last_layout:
		_last_layout = layout
		position = Vector2(16, top)
		var compact := top + EXPANDED_HEIGHT + 46 > view_height * 0.72
		if compact or forced_compact:
			set_collapsed(compact)
		forced_compact = compact
	_place_view_buttons()

func _place_view_buttons() -> void:
	if not is_instance_valid(game): return
	game._view_forward_btn.position = position + Vector2(0, size.y + 6)
	game._view_back_btn.position = position + Vector2(48, size.y + 6)
