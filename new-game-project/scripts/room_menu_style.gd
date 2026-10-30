extends RefCounted
## Room services share a framed dossier while card previews retain their own styles.
const UI = preload("res://scripts/ui_theme.gd")
const Route = preload("res://scripts/route_style.gd")

## False when the screen changed before this deferred style call ran.
static func current(content: Control, kind: String) -> bool:
	return is_instance_valid(content) and content.get_meta("style_kind", "") == kind

static func apply(modal: Control, content: Control, kind: String) -> void:
	if not current(content, kind): return
	if content.has_node("Center/Box"):
		content = content.get_node("Center/Box")
		content.custom_minimum_size.x = minf(840, modal.size.x - 80)
	if content.has_node("RoomHeading"): return
	var heading := content.get_child(0) as Label
	if heading == null: return
	var icon_kind := "shop" if kind == "shop" else "rest" if heading.text == "THE INFIRMARY" else "event"
	var header := HBoxContainer.new()
	header.name = "RoomHeading"
	header.add_theme_constant_override("separation", 16)
	content.add_child(header)
	content.move_child(header, 0)
	var icon := TextureRect.new()
	icon.texture = Route.icon(icon_kind)
	icon.modulate = UI.GOLD
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	header.add_child(icon)
	heading.reparent(header)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.add_theme_font_size_override("font_size", 32)
	readable_notes(content)
	var rule := HSeparator.new()
	content.add_child(rule)
	content.move_child(rule, 1)
	var panel := Route.plate(Color("191714"), Color("a47937"))
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	modal.add_theme_stylebox_override("panel", panel)
	style_actions(content)

static func style_actions(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D or child is SubViewport: continue
		if child is Button:
			child.custom_minimum_size.y = 54
			child.add_theme_font_size_override("font_size", 21)
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var fill := Color("2c251d")
				if state == "hover": fill = Color("594124")
				if state in ["pressed", "hover_pressed"]: fill = Color("76552d")
				if state == "disabled": fill = Color("211e19")
				if state == "focus": fill = Color.TRANSPARENT
				child.add_theme_stylebox_override(state, Route.plate(fill,
					UI.TEXT if state == "focus" else Color("a47937")))
			child.add_theme_color_override("font_color", UI.TEXT)
			child.add_theme_color_override("font_hover_color", Color("ffe5ac"))
			child.add_theme_color_override("font_pressed_color", Color("ffe5ac"))
			child.add_theme_color_override("font_hover_pressed_color", Color("ffe5ac"))
			child.add_theme_color_override("font_focus_color", UI.TEXT)
			child.add_theme_color_override("font_disabled_color", Color("968b78"))
			if child.name == "LeaveButton":
				child.size_flags_horizontal = Control.SIZE_SHRINK_END
				child.custom_minimum_size.x = 200
		style_actions(child)

static func catalog(modal: Control, content: Control, kind: String) -> void:
	if not current(content, kind) or content.has_node("CatalogHeading"): return
	var titles := {"deck":"YOUR DECK", "graveyard":"RESPONSE GRAVEYARD",
		"upgrade":"THE WORKSHOP", "character_preview":"STARTER DECK", "remove":"CARD REMOVAL",
		"intel":"HAZARD FORECAST"}
	var heading := Label.new()
	heading.name = "CatalogHeading"
	heading.text = titles.get(kind, kind.to_upper())
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", UI.GOLD)
	if content.get_child_count() > 0 and content.get_child(0) is Label:
		var old: Label = content.get_child(0)
		heading.text = old.text.to_upper()
		content.remove_child(old)
		old.queue_free()
	content.add_child(heading)
	content.move_child(heading, 0)
	var panel := Route.plate(Color("191714"), Color("a47937"))
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	modal.add_theme_stylebox_override("panel", panel)
	for toolbar_name in ["Tabs", "SortRow"]:
		var toolbar := content.get_node_or_null(toolbar_name) as BoxContainer
		if toolbar: toolbar.add_theme_constant_override("separation", 12)
	readable_notes(content)
	style_actions(content)
	for footer in ["LeaveButton", "BackButton", "BeginButton"]:
		var action := content.get_node_or_null(footer) as Button
		if action:
			action.size_flags_horizontal = Control.SIZE_SHRINK_END
			action.custom_minimum_size.x = 220

static func identity(panel: PanelContainer, available: bool) -> void:
	var paper := Route.plate(Color("ead3a5") if available else Color("b3a58b"), Color("987046"))
	paper.content_margin_left = 20
	paper.content_margin_right = 20
	paper.content_margin_top = 18
	paper.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", paper)
	panel.custom_minimum_size.y = 220
	var description: Label = panel.get_node("Box/Details")
	description.add_theme_color_override("font_color", Color("332a21"))
	description.add_theme_font_size_override("font_size", 20)
	var pick: Button = panel.get_node("Box/PickButton")
	pick.add_theme_font_size_override("font_size", 24)
	pick.add_theme_color_override("font_disabled_color", Color("b7a68a"))

## The note right under a heading was 16 px gray; make it readable but still quieter than buttons.
static func readable_notes(content: Control) -> void:
	if content.get_child_count() < 2: return
	var note := content.get_child(1) as Label
	if note == null: return
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	note.add_theme_font_size_override("font_size", 19)
	note.add_theme_color_override("font_color", Color("b9ab92"))

## Confirmations, pickers and the battle log: the same bronze plate as the rooms, smaller.
static func compact(modal: Control, content: Control, kind: String) -> void:
	if not current(content, kind): return
	var panel := Route.plate(Color("191714"), Color("a47937"))
	panel.set_content_margin_all(22)
	modal.add_theme_stylebox_override("panel", panel)
	# Log lines are the content itself, not a note.
	if kind != "log": readable_notes(content)
	style_actions(content)
	# Keyboard and controller start on the safe answer of a confirmation.
	if kind == "confirm": focus_button(content, true)

## Gives focus to the first (or last) enabled button so keyboard and controller have a start point.
static func focus_button(content: Control, last: bool = false) -> void:
	var buttons := content.find_children("*", "Button", true, false).filter(
		func(b): return not b.disabled and b.is_visible_in_tree())
	if buttons.is_empty(): return
	(buttons.back() if last else buttons.front()).grab_focus()

## Victory and defeat: a centered cream noticeboard with an ink icon, title and stats.
static func result(modal: Control, content: Control, kind: String) -> void:
	if not current(content, kind) or content.has_node("ResultIcon"): return
	var heading := content.get_child(0) as Label
	if heading == null: return
	var ink := Color("2b241f")
	var icon := TextureRect.new()
	icon.name = "ResultIcon"
	icon.texture = Route.icon("boss" if kind == "victory" else "battle")
	icon.modulate = ink
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_child(icon)
	content.move_child(icon, 0)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 46)
	heading.add_theme_color_override("font_color", ink)
	for child in content.get_children():
		if child is Label and child != heading:
			child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			child.add_theme_font_size_override("font_size", 22)
			child.add_theme_color_override("font_color", Color("5a4632"))
	if content is BoxContainer: content.alignment = BoxContainer.ALIGNMENT_CENTER
	var paper := Route.plate(Color("ead3a5"), Color("987046"))
	paper.set_border_width_all(6)
	paper.set_content_margin_all(40)
	paper.shadow_color = Color(0, 0, 0, 0.6)
	paper.shadow_size = 10
	modal.add_theme_stylebox_override("panel", paper)
	style_actions(content)
	for child in content.get_children():
		if child is Button:
			child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			child.custom_minimum_size.x = 380
	focus_button(content)
