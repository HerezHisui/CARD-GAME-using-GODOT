extends RefCounted
## One visual language for route nodes, their legend and the navigation dossier.
const UI = preload("res://scripts/ui_theme.gd")
const KINDS := ["battle", "elite", "boss", "rest", "shop", "event", "upgrade"]
const PURPOSE := {
	"battle": "Build your deck", "elite": "Unlock a tactic", "boss": "Clear this floor",
	"rest": "Heal or train", "shop": "Spend supplies", "event": "Risk and reward",
	"upgrade": "Improve a card"
}

static func plate(fill: Color, rim: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = rim
	result.set_border_width_all(2)
	result.set_corner_radius_all(12)
	result.corner_detail = 1
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result

static func icon(kind: String) -> Texture2D:
	return load("res://assets/ui/map/%s.svg" % kind) as Texture2D

static func node(button: Button, kind: String, current: bool, cleared: bool) -> void:
	button.custom_minimum_size = Vector2(112, 78)
	button.size = button.custom_minimum_size
	button.text = kind.to_upper()
	button.icon = icon(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("icon_normal_color", UI.GOLD)
	button.add_theme_color_override("icon_disabled_color", UI.GOLD if cleared or current else Color("665744"))
	button.add_theme_color_override("font_disabled_color", UI.TEXT if cleared or current else Color("8c8170"))
	button.add_theme_stylebox_override("normal", plate(Color("302416"), Color("e7a63c")))
	button.add_theme_stylebox_override("hover", plate(Color("52371d"), Color("ffd27b")))
	button.add_theme_stylebox_override("pressed", plate(Color("71502a"), UI.TEXT))
	button.add_theme_stylebox_override("focus", plate(Color(0, 0, 0, 0), UI.TEXT))
	var edge := Color("655039")
	if cleared: edge = Color("a58348")
	if current: edge = Color("f5d88b")
	if kind == "boss" and not cleared: edge = Color("ba5238")
	button.add_theme_stylebox_override("disabled", plate(Color("1c1915"), edge))
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.tooltip_text += "\n" + str(PURPOSE[kind])
	button.tooltip_text += "\n" + ("Current room" if current else "Cleared" if cleared
		else "Locked" if button.disabled else "Available")

static func screen(content: Control, floor_number: int) -> void:
	var row: HBoxContainer = content.get_node("RouteRow")
	row.add_theme_constant_override("separation", 18)
	var dossier: PanelContainer = row.get_node("Dossier")
	dossier.custom_minimum_size.x = 230
	dossier.add_theme_stylebox_override("panel", plate(Color("191714"), Color("a47937")))
	var text: VBoxContainer = dossier.get_node("DossierText")
	text.add_theme_constant_override("separation", 14)
	text.get_node("FloorLabel").text = "FLOOR %d" % floor_number
	var legend := VBoxContainer.new()
	legend.name = "RoomLegend"
	legend.add_theme_constant_override("separation", 8)
	text.add_child(legend)
	for kind in KINDS:
		var entry := HBoxContainer.new()
		legend.add_child(entry)
		var mark := TextureRect.new()
		mark.texture = icon(kind)
		mark.modulate = Color("e7a63c")
		mark.custom_minimum_size = Vector2(22, 22)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		entry.add_child(mark)
		var description := VBoxContainer.new()
		description.add_theme_constant_override("separation", 0)
		entry.add_child(description)
		var label := Label.new()
		label.text = kind.to_upper()
		label.add_theme_font_size_override("font_size", 18)
		description.add_child(label)
		var purpose := Label.new()
		purpose.text = PURPOSE[kind]
		purpose.add_theme_font_size_override("font_size", 15)
		purpose.modulate = Color("afa28b")
		description.add_child(purpose)
