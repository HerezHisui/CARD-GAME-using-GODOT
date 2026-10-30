extends Control
## Menu-only skin. The existing controls keep their callbacks and focus behavior.
const INK := Color("2b241f")
const CREAM := Color("ead3a5")
const BRONZE := Color("987046")
const METAL := Color("302d29")
var panel: Control
var previous_rect := Rect2()

static func box(fill: Color, border: Color, inset: int = 14) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(2)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(inset)
	return result

static func apply_skin(modal: Control, content: Control) -> void:
	var frame := box(CREAM, BRONZE, 26)
	frame.set_border_width_all(12)
	frame.shadow_color = Color(0, 0, 0, 0.6)
	frame.shadow_size = 10
	modal.add_theme_stylebox_override("panel", frame)
	style_children(content)

static func style_children(parent: Node) -> void:
	for child in parent.get_children():
		# Card preview viewports own their typography and colors.
		if child is Node3D or child is SubViewport: continue
		if child is Label or child is Button or child is RichTextLabel:
			child.add_theme_color_override("font_color", INK)
			child.add_theme_color_override("default_color", INK)
			child.add_theme_constant_override("outline_size", 0)
		if child is Button:
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var fill := CREAM.lightened(0.15) if state == "normal" else CREAM
				if state == "hover": fill = Color("ffe5ac")
				if state in ["pressed", "hover_pressed"]: fill = Color("d0b37e")
				if state == "disabled": fill = Color("c1b39a")
				if state == "focus": fill = Color.TRANSPARENT
				child.add_theme_stylebox_override(state, box(fill, INK if state != "focus" else BRONZE))
			for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				child.add_theme_color_override(state, INK)
			child.add_theme_color_override("font_disabled_color", Color("6c6458"))
		if child is PanelContainer:
			child.add_theme_stylebox_override("panel", box(CREAM.lightened(0.08), BRONZE))
		if child is VBoxContainer or child is HBoxContainer:
			child.add_theme_constant_override("separation", 14)
		style_children(child)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not is_instance_valid(panel): return
	var show_frame: bool = panel.visible and panel.get_meta("suspended_menu", false)
	var bounds := panel.get_global_rect()
	if visible != show_frame or bounds != previous_rect:
		visible = show_frame
		previous_rect = bounds
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(panel): return
	var bounds := panel.get_global_rect()
	# Suspended straps stay behind the title/header and never intercept input.
	for fraction in [0.17, 0.83]:
		var x: float = bounds.position.x + bounds.size.x * fraction
		var start := 0.0
		draw_line(Vector2(x, start), Vector2(x, bounds.position.y + 5), METAL, 12)
		draw_line(Vector2(x - 2, start), Vector2(x - 2, bounds.position.y + 5), BRONZE, 2)
		for y in range(int(start + 12), int(bounds.position.y + 4), 24):
			draw_circle(Vector2(x, y), 6, METAL)
			draw_arc(Vector2(x, y), 5, 0, TAU, 16, BRONZE, 2)
		for y in [bounds.position.y + 6, bounds.end.y - 6]:
			draw_circle(Vector2(x, y), 4, METAL)
			draw_line(Vector2(x - 2, y), Vector2(x + 2, y), BRONZE, 1)
