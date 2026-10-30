extends RefCounted
## The clean sheet is a derivative; source artwork and its baked counts are preserved outside the project.
const SHEET = preload("res://assets/ui/hubs/clean_hubs.png")
const GRAVEYARD = preload("res://assets/ui/hubs/graveyard.webp")
const UI = preload("res://scripts/ui_theme.gd")

static func atlas(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = SHEET
	texture.region = region
	return texture

static func apply(hud: Control) -> void:
	var draw: Button = hud.get_node("DeckDrawButton")
	var plans: Button = hud.get_node("PlansBox/PlansButton")
	var graveyard: Button = hud.get_node("GraveyardButton")
	var art := [atlas(Rect2(190, 207, 190, 200)), atlas(Rect2(192, 651, 190, 215)), GRAVEYARD]
	for index in 3:
		var button: Button = [draw, plans, graveyard][index]
		button.icon = null
		button.text = ""
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := UI.panel(Color("1d1c19"), Color("e5ad4c"), 4)
			style.set_corner_radius_all(0)
			style.border_color = Color("ffe1a0") if state in ["hover", "focus"] else Color("e5ad4c")
			if state == "pressed": style.bg_color = Color("3a3021")
			if state == "disabled": style.border_color = Color("6d5738")
			button.add_theme_stylebox_override(state, style)
		var icon: TextureRect
		if index == 0:
			icon = draw.get_node("DrawIcon")
		else:
			icon = TextureRect.new()
			icon.name = "HubIcon"
			button.add_child(icon)
		icon.texture = art[index]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(8, 8)
		icon.size = Vector2(36, 40)
		var count: Label
		if index == 0:
			count = draw.get_node("DeckCountLabel")
		else:
			count = Label.new()
			count.name = "CountLabel"
			button.add_child(count)
		count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		count.offset_left = 46
		count.offset_right = -4
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_theme_font_size_override("font_size", 22)
		count.add_theme_color_override("font_color", Color("f2dfba"))
		count.add_theme_constant_override("outline_size", 0)
