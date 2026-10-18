extends RefCounted
## Shared interface tokens and cached native control styles.
const BACKGROUND := Color("0b0b0d")
const PANEL := Color("1e1c20")
const RAISED := Color("2c292e")
const INSET := Color("111014")
const BRONZE := Color("c69c49")
const GOLD := Color("e0b963")
const CRIMSON := Color("8b1e24")
const ACTION := Color("b8252b")
const AMBER := Color("d99b26")
const TEXT := Color("eae4dc")
const MUTED := Color("8c867e")
const DISABLED := Color("77716c")
const RESPONSE := GOLD
const DANGER := Color("ed8985")
const AFFINITIES := {
	"evac": Color("91ad59"), "douse": Color("66a9b4"),
	"clearance": Color("da9148"), "brace": Color("b8bcc5"),
	"earthquake": Color("c2aa57"), "fire": Color("d65349"),
	"flood": Color("598dc3"), "typhoon": Color("a47bc1")
}
const BODY_SIZE := 18
const SMALL_SIZE := 14
const HEADING_SIZE := 30
static var shared_theme: Theme
static var body_font: SystemFont
static var heading_font: SystemFont
static var icons: Dictionary = {}
static var card_styles: Dictionary = {}

static func font(heading: bool = false) -> SystemFont:
	if body_font == null:
		body_font = SystemFont.new()
		body_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
		heading_font = SystemFont.new()
		heading_font.font_names = PackedStringArray(["Bahnschrift Condensed", "Bahnschrift", "Arial Narrow", "Arial"])
		heading_font.font_weight = 700
	return heading_font if heading else body_font

static func affinity_color(element: String) -> Color:
	return AFFINITIES.get(element, BRONZE)

static func panel(fill: Color = PANEL, border: Color = BRONZE, inset: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_corner_radius_all(8)
	box.corner_detail = 1
	box.set_content_margin_all(inset)
	return box

static func bar(color: Color) -> StyleBoxFlat:
	var box := panel(color, BRONZE.darkened(0.5), 0)
	box.set_corner_radius_all(3)
	return box

static func card_frame(disaster: bool) -> StyleBoxFlat:
	var key := "disaster" if disaster else "response"
	if not card_styles.has(key):
		var style := panel(CRIMSON.darkened(0.72) if disaster else PANEL, BRONZE, 0)
		style.set_border_width_all(4)
		style.set_corner_radius_all(10)
		card_styles[key] = style
	return card_styles[key]

static func badge_style(fill: Color) -> StyleBoxFlat:
	var key := "badge" + fill.to_html()
	if not card_styles.has(key):
		var style := panel(fill, BRONZE, 0)
		style.set_border_width_all(3)
		style.set_corner_radius_all(9)
		card_styles[key] = style
	return card_styles[key]

static func affinity_band(element: String) -> StyleBoxFlat:
	var key := "affinity" + element
	if not card_styles.has(key):
		var accent := affinity_color(element)
		var style := panel(accent.darkened(0.6), accent.lerp(GOLD, 0.3), 0)
		style.set_corner_radius_all(0)
		card_styles[key] = style
	return card_styles[key]

static func icon(kind: String, color: Color = GOLD) -> Texture2D:
	var key := kind + color.to_html()
	if icons.has(key): return icons[key]
	var mark := ""
	if kind == "on": mark = '<path d="M5 8l5 5 9-10"/>'
	if kind == "off": mark = '<path d="M6 6l12 12M18 6L6 18"/>'
	elif kind == "empty": mark = ""
	elif kind == "arrow": mark = '<path d="M7 9l5 6 5-6"/>'
	elif kind == "up": mark = '<path d="M7 15l5-6 5 6"/>'
	elif kind == "updown": mark = '<path d="M7 8l5-4 5 4M7 16l5 4 5-4"/>'
	elif kind == "radio": mark = '<circle cx="12" cy="12" r="4"/>'
	elif kind == "radio_empty": mark = '<circle cx="12" cy="12" r="7"/>'
	elif kind == "strength": mark = '<path d="M6 15l6-8 6 8M12 7v13"/>'
	elif kind == "bleed": mark = '<path d="M12 4C8 10 6 12 6 15a6 6 0 0012 0c0-3-2-5-6-11z"/>'
	elif kind == "burn": mark = '<path d="M12 3l1 7 4-4 2 9c0 8-14 8-14 0l4-7 1 5z"/>'
	elif kind == "poison": mark = '<circle cx="12" cy="10" r="6"/><path d="M9 17l6 4m0-4l-6 4M9 9h1m4 0h1"/>'
	elif kind == "barrier": mark = '<path d="M5 6l7-3 7 3v8l-7 7-7-7z"/>'
	elif kind == "healing_reduced": mark = '<path d="M12 6v12M6 12h12M4 20L20 4"/>'
	elif kind in ["armored", "grave_guard", "brace"]: mark = '<path d="M6 5h12v9l-6 6-6-6zM9 9h6"/>'
	elif kind in ["piercing", "flank", "rampaging"]: mark = '<path d="M5 19L19 5M12 5h7v7M6 12l6 6"/>'
	elif kind in ["draw", "on_play_draw", "tutor", "recover"]:
		mark = '<path d="M5 8h10v12H5zM9 4h10v12M8 14h4m-2-2v4"/>'
	elif kind in ["cleanse", "herb", "tablet", "heal_all", "leech", "regenerating"]:
		mark = '<path d="M10 5h4v5h5v4h-5v5h-4v-5H5v-4h5z"/>'
	elif kind in ["move", "move_ally", "extract"]: mark = '<path d="M4 12h16M8 8l-4 4 4 4m8-8l4 4-4 4"/>'
	elif kind in ["sealed", "seal"]: mark = '<rect x="6" y="10" width="12" height="10"/><path d="M8 10V7a4 4 0 018 0v3"/>'
	elif kind in ["sluggish", "resting", "delay"]: mark = '<path d="M8 6v12M16 6v12"/>'
	elif kind in ["rally", "rally_all", "fierce"]: mark = '<path d="M5 14l7-9 7 9M12 5v15M7 19h10"/>'
	elif kind in ["blast", "thorns", "fragile"]: mark = '<path d="M12 4l2 5 6-1-4 5 3 6-7-3-6 3 2-6-4-5 6 1z"/>'
	elif kind in ["tax", "refund_energy"]: mark = '<path d="M14 4L7 13h5l-2 7 8-11h-5z"/>'
	elif kind == "scout": mark = '<path d="M4 12q8-12 16 0-8 12-16 0z"/><circle cx="12" cy="12" r="3"/>'
	if mark.is_empty() and kind != "empty": mark = '<path d="M12 5l7 7-7 7-7-7zM12 9v4m0 2v1"/>'
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><g fill="none" stroke="#%s" stroke-width="2"><rect x="2" y="2" width="20" height="20" rx="3"/>%s</g></svg>' % [color.to_html(false), mark])
	var texture := ImageTexture.create_from_image(image)
	icons[key] = texture
	return texture

static func decorate(control: Control, hazard: bool = false) -> void:
	if control.has_node("IndustrialTrim"): return
	var trim = load("res://scripts/ui_plate.gd").new()
	trim.name = "IndustrialTrim"
	control.add_child(trim)
	trim.setup(control, BRONZE, AMBER, hazard)

static func outline(label: Control, size: int = 2) -> void:
	label.add_theme_color_override("font_outline_color", BACKGROUND)
	label.add_theme_constant_override("outline_size", size)

static func get_theme() -> Theme:
	if shared_theme != null: return shared_theme
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = BODY_SIZE
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var fill := RAISED if state in ["hover", "pressed", "hover_pressed"] else PANEL
			var border := GOLD if state in ["hover", "pressed", "hover_pressed", "focus"] else BRONZE.darkened(0.35)
			if state == "disabled": border = MUTED.darkened(0.55)
			if state == "focus": fill = Color.TRANSPARENT
			var box := panel(fill, border, 12)
			box.content_margin_top = 8
			box.content_margin_bottom = 8
			theme.set_stylebox(state, type, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, TEXT if state == "font_color" else GOLD)
		theme.set_color("font_disabled_color", type, DISABLED)
		theme.set_font("font", type, font(true))
	for variant in ["PrimaryButton", "TerminalButton"]:
		theme.set_type_variation(variant, "Button")
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var fill := CRIMSON if state == "normal" else ACTION
			if state == "disabled": fill = PANEL
			if state == "focus": fill = Color.TRANSPARENT
			var box := panel(fill, GOLD if state in ["hover", "focus"] else BRONZE, 20)
			box.set_corner_radius_all(16 if variant == "TerminalButton" else 10)
			theme.set_stylebox(state, variant, box)
		theme.set_font_size("font_size", variant, 22 if variant == "TerminalButton" else 18)
	for type in ["Label", "RichTextLabel", "LineEdit", "TextEdit", "PopupMenu", "TooltipLabel"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_outline_color", type, BACKGROUND)
		theme.set_constant("outline_size", type, 0)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("normal_font", "RichTextLabel", font())
	theme.set_font("bold_font", "RichTextLabel", font(true))
	theme.set_font_size("normal_font_size", "RichTextLabel", BODY_SIZE)
	for type in ["PanelContainer", "Panel", "PopupMenu", "TooltipPanel"]:
		theme.set_stylebox("panel", type, panel(INSET if type == "TooltipPanel" else PANEL))
	theme.set_stylebox("hover", "PopupMenu", panel(CRIMSON, GOLD, 8))
	theme.set_stylebox("separator", "PopupMenu", bar(BRONZE.darkened(0.5)))
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	theme.set_color("font_disabled_color", "PopupMenu", DISABLED)
	theme.set_icon("arrow", "OptionButton", icon("arrow"))
	theme.set_icon("submenu", "PopupMenu", icon("arrow"))
	for type in ["CheckBox", "CheckButton", "PopupMenu"]:
		for state in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "radio_checked", "radio_unchecked", "radio_checked_disabled", "radio_unchecked_disabled"]:
			var mark := "on" if state.begins_with("checked") else "empty"
			if state.begins_with("radio_"): mark = "radio" if state.begins_with("radio_checked") else "radio_empty"
			theme.set_icon(state, type, icon(mark, DISABLED if state.ends_with("disabled") else GOLD))
	theme.set_icon("up", "SpinBox", icon("up"))
	theme.set_icon("down", "SpinBox", icon("arrow"))
	theme.set_icon("updown", "SpinBox", icon("updown"))
	for type in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only", "focus"]:
			theme.set_stylebox(state, type, panel(Color.TRANSPARENT if state == "focus" else INSET, GOLD if state == "focus" else BRONZE.darkened(0.4), 8))
			theme.set_color("caret_color", type, GOLD)
			theme.set_color("selection_color", type, CRIMSON)
			theme.set_color("font_selected_color", type, TEXT)
			theme.set_color("font_uneditable_color", type, DISABLED)
	theme.set_stylebox("separator", "HSeparator", bar(BRONZE.darkened(0.5)))
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, panel(INSET, INSET, 5))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			theme.set_stylebox(state, type, panel(BRONZE if state == "grabber" else GOLD, BRONZE, 5))
		for state in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			theme.set_icon(state, type, icon("arrow" if state.begins_with("increment") else "up"))
	theme.set_stylebox("background", "ProgressBar", panel(INSET, BRONZE.darkened(0.5), 0))
	theme.set_stylebox("fill", "ProgressBar", bar(GOLD))
	for type in ["VBoxContainer", "HBoxContainer"]: theme.set_constant("separation", type, 12)
	for direction in ["h_separation", "v_separation"]: theme.set_constant(direction, "GridContainer", 12)
	shared_theme = theme
	return theme

static func apply_hud(root: Control) -> void:
	root.theme = get_theme()
	root.get_node("EndTurnButton").theme_type_variation = "PrimaryButton"
	for side in ["PlayerHealth", "EnemyHealth"]:
		var health := root.get_node(side)
		health.get_node("Bar").add_theme_stylebox_override("fill", bar(GOLD if side == "PlayerHealth" else CRIMSON))
		health.get_node("LagBar").add_theme_stylebox_override("fill", bar(AMBER))
		health.get_node("Value").add_theme_color_override("font_color", INSET if side == "PlayerHealth" else TEXT)
