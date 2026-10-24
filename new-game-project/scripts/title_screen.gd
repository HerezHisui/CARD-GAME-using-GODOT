extends Control
## The title screen: layered art with mouse parallax, sunrays, dust and a soft glow.
## run_director.gd picks which menu buttons to keep and hooks up their clicks.
const UI = preload("res://scripts/ui_theme.gd")
const GlowShader = preload("res://assets/title/title_glow.gdshader")

## Drop these three files into assets/title/ to get a three-layer background (far, mid, near).
## Turn on mipmaps in their import tab so the glow stays soft.
const LAYER_PATHS: Array[String] = [
	"res://assets/title/title_far_art.png",
	"res://assets/title/title_mid_art.png",
	"res://assets/title/title_near_art.png",
]
## Used when the three layers above are not all there.
const SINGLE_LAYER_PATH := "res://assets/title/title_bg_art.png"
## Most pixels each layer moves with the mouse.
const LAYER_PARALLAX: Array[float] = [3.0, 7.0, 12.0]
const SINGLE_PARALLAX := 6.0
## The sunrays move this much more than the nearest layer.
const RAY_PARALLAX_SCALE := 1.5
## Higher is snappier. Used for the parallax and the menu markers.
const SMOOTHING := 5.0
## One slow shimmer of the sunrays takes this long.
const SHIMMER_SECONDS := 8.0
const RAY_ALPHA := 0.5
## UV x ranges of the eyes in title_bg_art.png. One range blinks at a time.
const EYE_BANDS: Array[Vector2] = [
	Vector2(0.13, 0.17), Vector2(0.25, 0.28), Vector2(0.30, 0.33),
	Vector2(0.66, 0.70), Vector2(0.81, 0.87),
]
const BLINK_SECONDS := 0.14
## Gap between a menu item's text and its arrow marker.
const MARKER_GAP := 22.0

## One switch for every effect: parallax, sunrays, dust, glow, pulse and blink.
static var effects_enabled := true

var layers: Array[TextureRect] = []
var layer_parallax: Array[float] = []
var glow_material: ShaderMaterial
var parallax_on := true
var mouse_offset := Vector2.ZERO
var time := 0.0
var blink_wait := 3.0
var blink_left := 0.0
var selected: Button
## Only set when the Compatibility renderer is used.
var cpu_dust: CPUParticles2D
var marker_y := -1.0

@onready var backdrop: Control = %Backdrop
@onready var rays: TextureRect = %Rays
@onready var dust: GPUParticles2D = %Dust
@onready var title_label: Label = %Title
@onready var title_glow: CanvasGroup = %TitleGlow
@onready var glow_label: Label = %GlowLabel
@onready var menu: VBoxContainer = %Menu
@onready var markers: Control = %Markers

func _ready() -> void:
	build_layers()
	style_text()
	for item in menu.get_children():
		if item is Button: style_menu_button(item)
	markers.draw.connect(draw_markers)
	resized.connect(fit_to_size)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility": use_cpu_dust()
	set_effects(effects_enabled)
	fit_to_size.call_deferred()

## Uses the three layer files when they all exist, otherwise the single picture.
func build_layers() -> void:
	var paths: Array[String] = [SINGLE_LAYER_PATH]
	layer_parallax = [SINGLE_PARALLAX]
	if LAYER_PATHS.all(func(path: String) -> bool: return ResourceLoader.exists(path)):
		paths = LAYER_PATHS
		layer_parallax = LAYER_PARALLAX
	glow_material = ShaderMaterial.new()
	glow_material.shader = GlowShader
	for path in paths:
		var layer := TextureRect.new()
		layer.texture = load(path)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(layer)
		backdrop.move_child(layer, layers.size())
		layers.append(layer)

func style_text() -> void:
	# A slightly tracked copy of the heading face; the font itself stays the theme's.
	var face := FontVariation.new()
	face.base_font = title_label.get_theme_font("font")
	face.spacing_glyph = 4
	for label in [title_label, glow_label]:
		label.add_theme_font_override("font", face)
	title_label.add_theme_color_override("font_color", UI.TEXT)
	glow_label.add_theme_color_override("font_color", UI.ACTION)
	glow_label.add_theme_color_override("font_outline_color", UI.ACTION)
	rays.modulate = Color(UI.TEXT, RAY_ALPHA)
	dust.modulate = Color(UI.TEXT, 0.55)
	if cpu_dust: cpu_dust.modulate = dust.modulate
	%SaveLabel.add_theme_color_override("font_color", UI.MUTED)
	UI.outline(%SaveLabel)

## Plain text items: no plate, gold when selected, and the mouse selects what it points at.
func style_menu_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.add_theme_color_override("font_color", UI.TEXT)
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, UI.GOLD)
	button.add_theme_color_override("font_disabled_color", UI.DISABLED)
	UI.outline(button)
	if button.disabled:
		button.focus_mode = Control.FOCUS_NONE
		return
	button.focus_entered.connect(select.bind(button))
	button.mouse_entered.connect(button.grab_focus)

func select(button: Button) -> void:
	selected = button
	if marker_y < 0: marker_y = marker_target()
	markers.queue_redraw()

func set_effects(on: bool) -> void:
	rays.visible = on
	var particles: Node2D = cpu_dust if cpu_dust else dust
	particles.visible = on
	particles.set("emitting", on)
	title_glow.visible = on
	for layer in layers:
		layer.material = glow_material if on else null
	if not on: mouse_offset = Vector2.ZERO

## Keeps every layer a little bigger than the screen, so parallax never shows an edge.
func fit_to_size() -> void:
	for i in layers.size():
		var margin := layer_parallax[i] + 2.0
		layers[i].size = size + Vector2.ONE * margin * 2.0
	var ray_margin := ray_parallax() + 2.0
	rays.size = size + Vector2.ONE * ray_margin * 2.0
	glow_label.size = title_label.size
	# The dust spawns over the whole screen plus a border, from the center.
	var half := size * 0.5 + Vector2(60.0, 60.0)
	(dust.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(half.x, half.y, 1.0)
	dust.position = size * 0.5
	dust.visibility_rect = Rect2(-half, half * 2.0)
	if cpu_dust:
		cpu_dust.emission_rect_extents = half
		cpu_dust.position = size * 0.5
	move_layers()
	# Snap the marker after a resize, so it does not slide in from where the layout used to be.
	marker_y = marker_target()
	markers.queue_redraw()

func ray_parallax() -> float:
	return layer_parallax[-1] * RAY_PARALLAX_SCALE

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-SMOOTHING * delta)
	if is_instance_valid(selected):
		marker_y = lerpf(marker_y, marker_target(), weight)
		markers.queue_redraw()
	if not effects_enabled: return
	time += delta
	var target := Vector2.ZERO
	if parallax_on and size.x > 0.0 and size.y > 0.0:
		var mouse := get_local_mouse_position() / size - Vector2(0.5, 0.5)
		target = (mouse * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
	mouse_offset = mouse_offset.lerp(target, weight)
	move_layers()
	# Two slow waves that never quite line up, so the shimmer does not look like a loop.
	var shimmer := 0.8 + 0.12 * sin(time * TAU / SHIMMER_SECONDS)
	shimmer += 0.08 * sin(time * TAU / (SHIMMER_SECONDS * 0.63))
	rays.modulate.a = RAY_ALPHA * shimmer
	update_blink(delta)

## Each layer moves against the mouse; nearer layers move more. The title and menu stay still.
func move_layers() -> void:
	for i in layers.size():
		var margin := layer_parallax[i] + 2.0
		layers[i].position = -Vector2.ONE * margin - mouse_offset * layer_parallax[i]
	var ray_margin := ray_parallax() + 2.0
	rays.position = -Vector2.ONE * ray_margin - mouse_offset * ray_parallax()

## Now and then one group of eyes shuts for a moment.
func update_blink(delta: float) -> void:
	if blink_left > 0.0:
		blink_left -= delta
		if blink_left <= 0.0: glow_material.set_shader_parameter("blink_band", Vector2(1.0, 0.0))
		return
	blink_wait -= delta
	if blink_wait > 0.0: return
	blink_wait = randf_range(2.5, 6.0)
	blink_left = BLINK_SECONDS
	glow_material.set_shader_parameter("blink_band", EYE_BANDS.pick_random())

## Parallax pauses when the window loses focus or a controller is used; the mouse brings it back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: parallax_on = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: parallax_on = true

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		parallax_on = false
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		parallax_on = false
	elif event is InputEventMouseMotion:
		parallax_on = true

func marker_target() -> float:
	if not is_instance_valid(selected): return 0.0
	var rect := selected.get_global_rect()
	return rect.get_center().y - markers.global_position.y

## Small cut-corner arrow plates on both sides of the selected item, like the Drill Placard.
func draw_markers() -> void:
	if not is_instance_valid(selected): return
	var rect := selected.get_global_rect()
	var font := selected.get_theme_font("font")
	var font_size := selected.get_theme_font_size("font_size")
	var half_text := font.get_string_size(selected.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	var center_x := rect.get_center().x - markers.global_position.x
	var y := marker_y
	markers.draw_colored_polygon(arrow(Vector2(center_x - half_text - MARKER_GAP, y), 1.0), UI.GOLD)
	markers.draw_colored_polygon(arrow(Vector2(center_x + half_text + MARKER_GAP, y), -1.0), UI.GOLD)

## An arrow plate whose tip sits at `tip`. side 1 points right, -1 points left.
func arrow(tip: Vector2, side: float) -> PackedVector2Array:
	var shape := [Vector2(0, 0), Vector2(-6, -7), Vector2(-14, -7), Vector2(-16, -5),
		Vector2(-16, 5), Vector2(-14, 7), Vector2(-6, 7)]
	var points := PackedVector2Array()
	for point in shape:
		points.append(tip + Vector2(point.x * side, point.y))
	return points

## The Compatibility renderer gets the same dust from the CPU.
func use_cpu_dust() -> void:
	cpu_dust = CPUParticles2D.new()
	cpu_dust.convert_from_particles(dust)
	cpu_dust.texture = dust.texture
	cpu_dust.material = dust.material
	dust.add_sibling(cpu_dust)
	dust.hide()
	dust.emitting = false
