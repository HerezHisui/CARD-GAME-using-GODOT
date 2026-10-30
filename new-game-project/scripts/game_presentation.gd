extends CanvasLayer
const UI = preload("res://scripts/ui_theme.gd")
const COIN_SCENE = preload("res://assets/coin/midnight_coin.glb")
## Short, event-driven UI tweens. No polling, gameplay timers or game-state ownership.
signal coin_chosen(side: int)
var game: Node
var blocking := false
var automated_choice := -1 # Explicit opt-in for integration fixtures, never set by gameplay.
var coin_root: ColorRect
var coin_pivot: Node3D
var choice_buttons: Array[Button] = []
var coin_busy := false
var coin_epoch := 0
var banner_node: Control
var banner_tween: Tween
var draw_reminder: Panel
var draw_reminder_tween: Tween

func setup(owner_game: Node) -> void:
	game = owner_game
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	for button in game.get_node("HUD/Root").find_children("*", "Button", true, false):
		button_feedback(button)
	get_tree().node_added.connect(func(node: Node):
		if node is Button and game.is_ancestor_of(node): button_feedback(node)
	)

func choose_coin(result: int, previous_pick: int = -1) -> int:
	coin_epoch += 1
	var epoch := coin_epoch
	blocking = true
	coin_busy = false
	coin_root = ColorRect.new()
	var event_root := coin_root
	coin_root.name = "CoinFlip"
	coin_root.theme = game.run_director.root.theme
	coin_root.color = UI.BACKGROUND
	coin_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coin_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(coin_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coin_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title = game.run_director.label("CALL THE COIN", 34, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint = game.run_director.label("Choose a side. Match the toss to take the first turn.", 19)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var coin_space := CenterContainer.new()
	coin_space.custom_minimum_size = Vector2(600, 340)
	box.add_child(coin_space)
	coin_space.add_child(make_coin_view())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	choice_buttons.clear()
	for side in 2:
		var button = game.run_director.button("Heads" if side == 0 else "Tails", select_coin.bind(side), buttons)
		button.custom_minimum_size = Vector2(200, 56)
		button.theme_type_variation = "TerminalButton"
		UI.decorate(button)
		choice_buttons.append(button)
	reveal(box)
	game.run_director.persistence.checkpoint()
	if previous_pick >= 0: select_coin.call_deferred(previous_pick)
	elif automated_choice >= 0: select_coin.call_deferred(automated_choice)
	var pick: int = await coin_chosen
	if pick < 0 or epoch != coin_epoch: return -1
	var toss := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	toss.tween_method(func(t: float):
		if epoch != coin_epoch: return
		# Hop up and down while flipping; ends Heads up for 0, Tails up for 1.
		coin_pivot.position.y = 0.9 * sin(t * PI)
		coin_pivot.rotation.x = t * (TAU * 4 + PI * result)
		coin_pivot.rotation.z = sin(t * TAU) * 0.12
	, 0.0, 1.0, 1.15)
	await toss.finished
	if epoch != coin_epoch:
		event_root.queue_free()
		return -1
	coin_pivot.position = Vector3.ZERO
	coin_pivot.rotation = Vector3(PI * result, 0, 0)
	title.text = "HEADS" if result == 0 else "TAILS"
	hint.text = "You take the first turn." if pick == result else "The Janitor takes the first turn."
	for button in choice_buttons: button.hide()
	var linger := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	linger.tween_interval(0.7)
	linger.tween_property(coin_root, "modulate:a", 0.0, 0.18)
	await linger.finished
	if epoch != coin_epoch:
		event_root.queue_free()
		return -1
	coin_root.queue_free()
	coin_root = null
	blocking = false
	return pick

## Small 3D view with its own world, so the classroom does not show behind the coin.
func make_coin_view() -> SubViewportContainer:
	var view_box := SubViewportContainer.new()
	view_box.custom_minimum_size = Vector2(240, 240)
	view_box.stretch = true
	view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	view_box.add_child(view)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 3.6)
	view.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 20, 0)
	light.light_energy = 1.5
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("ffe2b1")
	environment.environment.ambient_light_energy = 0.65
	view.add_child(environment)
	coin_pivot = make_coin()
	view.add_child(coin_pivot)
	return view_box

## Centered octagonal solid with beveled borders and raised sun/moon geometry.
func make_coin() -> Node3D:
	return COIN_SCENE.instantiate() as Node3D

func cancel_coin() -> void:
	coin_epoch += 1
	if blocking and not coin_busy: coin_chosen.emit(-1)
	if is_instance_valid(coin_root):
		if coin_busy: coin_root.hide()
		else: coin_root.queue_free()
	coin_root = null
	blocking = false

func select_coin(side: int) -> void:
	if coin_busy or not blocking or side not in [0, 1]: return
	coin_busy = true
	game.coin_pick = side
	for button in choice_buttons: button.disabled = true
	game.run_director.persistence.checkpoint()
	coin_chosen.emit(side)

func reveal(control: Control) -> void:
	control.modulate.a = 0
	control.pivot_offset = control.size / 2
	control.scale = Vector2.ONE * 0.985
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func clear_banner() -> void:
	if banner_tween: banner_tween.kill()
	if is_instance_valid(banner_node): banner_node.queue_free()
	banner_node = null

func remind_to_draw(active: bool) -> void:
	if draw_reminder_tween: draw_reminder_tween.kill()
	if is_instance_valid(draw_reminder): draw_reminder.hide()
	if not active: return
	if not is_instance_valid(draw_reminder):
		var button := game.get_node("HUD/Root/DeckDrawButton")
		draw_reminder = Panel.new()
		draw_reminder.name = "DrawReminder"
		draw_reminder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		draw_reminder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		draw_reminder.add_theme_stylebox_override("panel", UI.panel(UI.ACTION, UI.GOLD, 0))
		button.add_child(draw_reminder)
		# Overlay the icon too: its source art has an opaque dark background.
	draw_reminder.show()
	draw_reminder.modulate.a = 0.0
	draw_reminder_tween = draw_reminder.create_tween().set_loops()
	draw_reminder_tween.tween_property(draw_reminder, "modulate:a", 0.35, 0.45)
	draw_reminder_tween.tween_property(draw_reminder, "modulate:a", 0.0, 0.45)

func button_feedback(button: Button) -> void:
	if button.has_meta("hover_feedback"): return
	button.set_meta("hover_feedback", true)
	# Native theme states preserve custom skins, toggle state and controller focus.
	# Do not override or tween style resources here: menus can reskin after setup.

func card_feedback(face: Control) -> void:
	var tween: Array = [null]
	var reference: WeakRef = weakref(face)
	var animate := func(amount: float):
		var live_face = reference.get_ref()
		if not is_instance_valid(live_face) or live_face.is_queued_for_deletion(): return
		if tween[0]: tween[0].kill()
		live_face.pivot_offset = live_face.size / 2
		tween[0] = live_face.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween[0].tween_property(live_face, "scale", Vector2.ONE * amount, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	face.mouse_entered.connect(func(): animate.call(1.025))
	face.mouse_exited.connect(func(): animate.call(1.0))

@warning_ignore("unused_parameter")
func banner(title: String, subtitle: String = "", color: Color = UI.GOLD, entry: bool = false) -> void:
	if blocking and not entry: return
	if banner_tween: banner_tween.kill()
	if is_instance_valid(banner_node): banner_node.queue_free()
	var panel := PanelContainer.new()
	panel.theme = UI.get_theme()
	banner_node = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -64
	panel.offset_bottom = 64
	var style := UI.panel(Color.TRANSPARENT, UI.AMBER)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.content_margin_left = 0
	style.content_margin_right = 0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var heading: Label = add_banner_labels(box, title, subtitle)
	var material: ShaderMaterial = add_banner_strip(panel)
	panel.modulate.a = 0
	banner_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	banner_tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	var expand := banner_tween.parallel().tween_property(material, "shader_parameter/reveal", 1.0, 0.2)
	expand.set_trans(Tween.TRANS_EXPO if entry else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if heading != null: animate_banner_heading(heading)
	banner_tween.tween_interval(0.65)
	banner_tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	banner_tween.tween_callback(panel.queue_free)

func add_banner_labels(box: VBoxContainer, title: String, subtitle: String) -> Label:
	var heading: Label
	for words in [title, subtitle]:
		if words.is_empty(): continue
		var text_color: Color = UI.TEXT if words == title else UI.TEXT.darkened(0.12)
		var label: Label = game.run_director.label(words, 48 if words == title else 20, text_color)
		label.clip_text = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if words == title:
			heading = label
			label.text = words.to_upper()
			var heading_font := FontVariation.new()
			heading_font.base_font = UI.font(true)
			heading_font.spacing_glyph = 2
			label.add_theme_font_override("font", heading_font)
			label.add_theme_color_override("font_shadow_color", Color(UI.AMBER, 0.35))
			label.add_theme_constant_override("shadow_outline_size", 4)
			label.add_theme_constant_override("shadow_offset_x", 0)
			label.add_theme_constant_override("shadow_offset_y", 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
	return heading

func animate_banner_heading(heading: Label) -> void:
	heading.modulate.a = 0.0
	heading.scale = Vector2.ONE * 1.1
	heading.resized.connect(func(): heading.pivot_offset = heading.size * 0.5)
	banner_tween.parallel().tween_property(heading, "modulate:a", 1.0, 0.2)
	var settle := banner_tween.parallel().tween_property(heading, "scale", Vector2.ONE, 0.2)
	settle.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func add_banner_strip(panel: PanelContainer) -> ShaderMaterial:
	var strip := ColorRect.new()
	strip.name = "BannerStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/banner_strip.gdshader")
	material.set_shader_parameter("fill_color", Color(UI.INSET, 0.82))
	material.set_shader_parameter("line_color", UI.GOLD)
	material.set_shader_parameter("line_width", 1.5)
	material.set_shader_parameter("reveal", 0.0)
	strip.material = material
	panel.add_child(strip)
	return material
