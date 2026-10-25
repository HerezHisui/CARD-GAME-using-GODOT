extends Control
## The title screen: one hallway picture with mouse parallax, blur, sunrays, dust and a soft glow.
## run_director.gd picks which menu buttons to keep and hooks up their clicks.
const UI = preload("res://scripts/ui_theme.gd")
const GlowShader = preload("res://assets/title/title_glow.gdshader")

## The background picture. Keep mipmaps on in its import tab so the glow stays soft.
const BACKGROUND_PATH := "res://assets/title/title_bg_art.png"
## Most pixels the background moves with the mouse.
const BACKGROUND_PARALLAX := 6.0
## The sunrays move this much more than the background.
const RAY_PARALLAX_SCALE := 1.5
## Higher is snappier. Used for the parallax and the menu markers.
const SMOOTHING := 5.0
## One slow shimmer of the sunrays takes this long.
const SHIMMER_SECONDS := 8.0
const RAY_ALPHA := 0.5
## Extra space between title letters, in pixels.
const TITLE_SPACING := 18
const SUBTITLE_SPACING := 6
## The title text dims by at most this much in its slow flicker.
const FLICKER_AMOUNT := 0.07
## Gap between a menu item's text and its arrow marker.
const MARKER_GAP := 22.0

## One switch for every effect: parallax, blur, sunrays, dust, glow, pulse and flicker.
static var effects_enabled := true

var background: TextureRect
var glow_material: ShaderMaterial
var parallax_on := true
var mouse_offset := Vector2.ZERO
var time := 0.0
var selected: Button
## Only set when the Compatibility renderer is used.
var cpu_dust: CPUParticles2D
var marker_y := -1.0

@onready var backdrop: Control = %Backdrop
@onready var rays: TextureRect = %Rays
@onready var dust: GPUParticles2D = %Dust
@onready var title_box: Control = %TitleBox
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var title_glow: CanvasGroup = %TitleGlow
@onready var glow_label: Label = %GlowLabel
@onready var sub_glow_label: Label = %SubGlowLabel
@onready var menu: VBoxContainer = %Menu
@onready var markers: Control = %Markers

func _ready() -> void:
	build_background()
	style_text()
	for item in menu.get_children():
		if item is Button: style_menu_button(item)
	markers.draw.connect(draw_markers)
	resized.connect(fit_to_size)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility": use_cpu_dust()
	set_effects(effects_enabled)
	fit_to_size.call_deferred()

## The hallway picture sits behind the sunrays and dust.
func build_background() -> void:
	glow_material = ShaderMaterial.new()
	glow_material.shader = GlowShader
	background = TextureRect.new()
	background.texture = load(BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(background)
	backdrop.move_child(background, 0)

func style_text() -> void:
	# Tracked copies of the heading face; the font itself stays the theme's.
	var title_face := spaced_face(TITLE_SPACING)
	var subtitle_face := spaced_face(SUBTITLE_SPACING)
	for label in [title_label, glow_label]:
		label.add_theme_font_override("font", title_face)
	for label in [subtitle_label, sub_glow_label]:
		label.add_theme_font_override("font", subtitle_face)
	# Bone-white MIDNIGHT and dark red DRRills, both with a thin dark outline.
	title_label.add_theme_color_override("font_color", UI.TEXT)
	subtitle_label.add_theme_color_override("font_color", UI.ACTION.darkened(0.2))
	for label in [title_label, subtitle_label]:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
	# The glow copies are red, with a thick outline so the halo is wide.
	for label in [glow_label, sub_glow_label]:
		label.add_theme_color_override("font_color", UI.ACTION)
		label.add_theme_color_override("font_outline_color", UI.ACTION)
	rays.modulate = Color(UI.TEXT, RAY_ALPHA)
	dust.modulate = Color(UI.TEXT, 0.55)
	if cpu_dust: cpu_dust.modulate = dust.modulate
	%SaveLabel.add_theme_color_override("font_color", UI.MUTED)
	UI.outline(%SaveLabel)

## The theme's heading font with extra space between letters.
func spaced_face(spacing: int) -> FontVariation:
	var face := FontVariation.new()
	face.base_font = title_label.get_theme_font("font")
	face.spacing_glyph = spacing
	return face

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
	background.material = glow_material if on else null
	if not on:
		mouse_offset = Vector2.ZERO
		title_box.modulate = Color.WHITE

## Keeps the background a little bigger than the screen, so parallax never shows an edge.
func fit_to_size() -> void:
	var margin := BACKGROUND_PARALLAX + 2.0
	background.size = size + Vector2.ONE * margin * 2.0
	var ray_margin := ray_parallax() + 2.0
	rays.size = size + Vector2.ONE * ray_margin * 2.0
	# The glow copies sit exactly on top of the real labels.
	glow_label.position = title_label.position
	glow_label.size = title_label.size
	sub_glow_label.position = subtitle_label.position
	sub_glow_label.size = subtitle_label.size
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
	return BACKGROUND_PARALLAX * RAY_PARALLAX_SCALE

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
	update_flicker()

## The background moves against the mouse; the sunrays move more. The title and menu stay still.
func move_layers() -> void:
	var margin := BACKGROUND_PARALLAX + 2.0
	background.position = -Vector2.ONE * margin - mouse_offset * BACKGROUND_PARALLAX
	var ray_margin := ray_parallax() + 2.0
	rays.position = -Vector2.ONE * ray_margin - mouse_offset * ray_parallax()

## The title and its glow dim a little, slowly, like a weak light.
func update_flicker() -> void:
	# Three waves at odd speeds, so the flicker does not look like a loop.
	var wave := sin(time * 0.9) * 0.5 + sin(time * 2.3) * 0.3 + sin(time * 5.1) * 0.2
	var light := 1.0 - FLICKER_AMOUNT * (wave * 0.5 + 0.5)
	title_box.modulate = Color(light, light, light, 1.0)

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
