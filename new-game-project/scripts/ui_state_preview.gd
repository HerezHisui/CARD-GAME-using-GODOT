@tool
extends Control
## Gallery only: draws one button style from the theme in a fixed state.
## Godot can't hold a real button in hover or pressed, so this draws that state's style and text color.

@export var theme_type := "Button":
	set(value):
		theme_type = value
		_refresh()
@export_enum("normal", "hover", "pressed", "disabled") var state := "normal":
	set(value):
		state = value
		_refresh()
@export var text := "Button":
	set(value):
		text = value
		_refresh()

const COLOR_NAMES := {"normal": "font_color", "hover": "font_hover_color",
	"pressed": "font_pressed_color", "disabled": "font_disabled_color"}
var _watched: Theme

func _notification(what: int) -> void:
	if what in [NOTIFICATION_ENTER_TREE, NOTIFICATION_THEME_CHANGED]: _refresh()

func _refresh() -> void:
	var current := _find_theme()
	if current != _watched:
		if _watched and _watched.changed.is_connected(_refresh): _watched.changed.disconnect(_refresh)
		# Redraw when the theme file is edited in the editor.
		if current: current.changed.connect(_refresh)
		_watched = current
	update_minimum_size()
	queue_redraw()

func _find_theme() -> Theme:
	var node: Node = self
	while node != null:
		if node is Control and node.theme != null: return node.theme
		node = node.get_parent()
	return null

## Theme lookup that follows type variations, e.g. PrimaryButton falls back to Button.
func _item(kind: String, item: String) -> Variant:
	var current := _find_theme()
	if current == null: return null
	var type := theme_type
	while type != "":
		if current.call("has_" + kind, item, type): return current.call("get_" + kind, item, type)
		type = current.get_type_variation_base(type)
	return null

func preview_style() -> StyleBox:
	return _item("stylebox", state)

func _font() -> Font:
	var found: Variant = _item("font", "font")
	if found: return found
	return _find_theme().default_font if _find_theme() and _find_theme().default_font else get_theme_default_font()

func _font_size() -> int:
	var found: Variant = _item("font_size", "font_size")
	if found != null: return found
	return _find_theme().default_font_size if _find_theme() else get_theme_default_font_size()

func _get_minimum_size() -> Vector2:
	var box := preview_style()
	var text_size := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size())
	return text_size + (box.get_minimum_size() if box else Vector2.ZERO)

func _draw() -> void:
	var box := preview_style()
	if box: draw_style_box(box, Rect2(Vector2.ZERO, size))
	var font := _font()
	var font_size := _font_size()
	var color: Variant = _item("color", COLOR_NAMES[state])
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := ((size - text_size) / 2.0).round() + Vector2(0, round(font.get_ascent(font_size)))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color if color else Color.WHITE)
