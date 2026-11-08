extends RefCounted
## Room services share a framed dossier while card previews retain their own styles.
const UI = preload("res://scripts/ui_theme.gd")
const Route = preload("res://scripts/route_style.gd")

## False when the screen changed before this deferred style call ran.
static func current(content, kind: String) -> bool:
	return is_instance_valid(content) and content.get_meta("style_kind", "") == kind

## Dark panels that end under their last row (rule 2). Deck, workshop and graveyard stay full screen.
const FIT_KINDS := ["event", "shop", "confirm", "choice", "remove_confirm", "log"]

## Makes a dark panel as tall as its content, centred and under the top bar.
## It runs again one frame later, when wrapped labels know their real width.
## A signal, not await: a waiting function would leak when the game quits.
static func fit_height(modal: Control, content_node, kind: String) -> void:
	_fit_once(modal, content_node, kind)
	if not modal.is_inside_tree(): return
	var again := _fit_again.bind(modal, content_node, kind)
	var frame := modal.get_tree().process_frame
	if not frame.is_connected(again): frame.connect(again, CONNECT_ONE_SHOT)

static func _fit_once(modal: Control, content_node, kind: String) -> void:
	if not current(content_node, kind): return
	var content: Control = content_node
	var view := modal.get_viewport_rect().size
	var plate := modal.get_theme_stylebox("panel").get_minimum_size().y
	var height := minf(plate + content.get_combined_minimum_size().y + 2, view.y - 90)
	modal.offset_top = maxf(66, (view.y - height) / 2)
	modal.offset_bottom = -(view.y - modal.offset_top - height)

## Untyped: the modal can be freed (return to title) before the next frame.
static func _fit_again(modal, content_node, kind: String) -> void:
	if not is_instance_valid(modal) or not modal.is_inside_tree(): return
	_fit_once(modal, content_node, kind)
	# The battle log grows with its text, so open it at the newest line.
	if kind != "log" or not current(content_node, kind): return
	var scroll := (content_node as Control).get_parent() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

## Thin gold line under a dark panel title. It ends in a small diamond on the right.
static func title_rule(content: Control, heading_index: int) -> void:
	if content.has_node("TitleRule"): return
	var rule := HSeparator.new()
	rule.name = "TitleRule"
	rule.add_theme_constant_override("separation", 12)
	var line = load("res://scripts/ui_title_rule.gd").new()
	line.color = UI.GOLD
	rule.add_theme_stylebox_override("separator", line)
	content.add_child(rule)
	content.move_child(rule, heading_index + 1)

## Gold title of a dark panel: one size everywhere (rule 4).
static func title_size(heading: Label) -> void:
	heading.add_theme_font_size_override("font_size", UI.HEADING_SIZE)

static func apply(modal: Control, content_node, kind: String) -> void:
	if not current(content_node, kind): return
	fit_height(modal, content_node, kind)
	var content: Control = content_node
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
	title_size(heading)
	readable_notes(content)
	title_rule(content, 0)
	var panel := dark_plate()
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	modal.add_theme_stylebox_override("panel", panel)
	style_actions(content)

static func style_actions(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D or child is SubViewport: continue
		if child is Button: style_button(child)
		style_actions(child)

## The one dark-family button style. Exit buttons (Leave, Close, Cancel, Back) get their size
## and place in their .tscn.
static func style_button(button: Button) -> void:
	button.custom_minimum_size.y = 54
	button.add_theme_font_size_override("font_size", 21)
	# The look itself comes from the shared builder in ui_theme.gd (charcoal, gold line, cut corners).
	var danger := button.text.begins_with("Abandon") or button.text.begins_with("Destroy")
	UI.style_button(button, danger)

## Dark family colours, all made from the ui_theme palette (rule 3).
## Neutral charcoal, no warm brown.
static func dark_fill() -> Color:
	return UI.PANEL.darkened(0.15)

static func dark_rim() -> Color:
	return UI.GOLD

## The dark panel plate: charcoal, crisp gold line, cut corners.
static func dark_plate() -> StyleBoxFlat:
	return UI.sharp_panel(dark_fill(), dark_rim(), 14)

static func catalog(modal: Control, content_node, kind: String) -> void:
	if not current(content_node, kind): return
	var content: Control = content_node
	if content.has_node("CatalogHeading"): return
	var titles := {"deck":"YOUR DECK", "graveyard":"RESPONSE GRAVEYARD",
		"upgrade":"THE WORKSHOP", "character_preview":"STARTER DECK", "remove":"CARD REMOVAL",
		"intel":"HAZARD FORECAST"}
	var heading := Label.new()
	heading.name = "CatalogHeading"
	heading.text = titles.get(kind, kind.to_upper())
	title_size(heading)
	heading.add_theme_color_override("font_color", UI.GOLD)
	if content.get_child_count() > 0 and content.get_child(0) is Label:
		var old: Label = content.get_child(0)
		heading.text = old.text.to_upper()
		content.remove_child(old)
		old.queue_free()
	content.add_child(heading)
	content.move_child(heading, 0)
	var panel := dark_plate()
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	# Same margins as the room panels, so the titles sit in the same place.
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	modal.add_theme_stylebox_override("panel", panel)
	for toolbar_name in ["Tabs", "SortRow"]:
		var toolbar := content.get_node_or_null(toolbar_name) as BoxContainer
		if toolbar: toolbar.add_theme_constant_override("separation", 12)
	readable_notes(content)
	title_rule(content, 0)
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
	# The card picker hint stays small and muted.
	if note.has_meta("pick_hint"): return
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	note.add_theme_font_size_override("font_size", 19)
	note.add_theme_color_override("font_color", UI.TEXT.darkened(0.2))

## Confirmations, pickers and the battle log: the same charcoal plate as the rooms, smaller.
static func compact(modal: Control, content_node, kind: String) -> void:
	if not current(content_node, kind): return
	var content: Control = content_node
	var panel := dark_plate()
	panel.set_content_margin_all(22)
	modal.add_theme_stylebox_override("panel", panel)
	# The gold title made by reset_panel() is the first child.
	var heading: Label = null
	if content.get_child_count() > 0: heading = content.get_child(0) as Label
	if heading and heading.get_theme_color("font_color") == UI.GOLD: title_size(heading)
	# Log lines are the content itself, not a note.
	if kind != "log": readable_notes(content)
	if heading and heading.get_theme_color("font_color") == UI.GOLD: title_rule(content, 0)
	style_actions(content)
	fit_height(modal, content_node, kind)
	# Keyboard and controller start on the safe answer of a confirmation.
	if kind == "confirm": focus_button(content, true)

## Gives focus to the first (or last) enabled button so keyboard and controller have a start point.
static func focus_button(content: Control, last: bool = false) -> void:
	var buttons := content.find_children("*", "Button", true, false).filter(
		func(b): return not b.disabled and b.is_visible_in_tree())
	if buttons.is_empty(): return
	(buttons.back() if last else buttons.front()).grab_focus()

## Victory and defeat: a centered cream noticeboard with an ink icon, title and stats.
static func result(modal: Control, content_node, kind: String) -> void:
	if not current(content_node, kind): return
	var content: Control = content_node
	if content.has_node("ResultIcon"): return
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
