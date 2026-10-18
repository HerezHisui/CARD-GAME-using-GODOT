extends CanvasLayer
const UI = preload("res://scripts/ui_theme.gd")
## Short, event-driven UI tweens. No polling, gameplay timers or game-state ownership.
signal coin_chosen(side: int)
var game: Node
var blocking := false
var automated_choice := -1 # Explicit opt-in for integration fixtures, never set by gameplay.
var coin_root: ColorRect
var coin_sprite: TextureRect
var choice_buttons: Array[Button] = []
var coin_busy := false
var coin_epoch := 0
var coin_textures: Array[Texture2D] = []
var banner_node: Control
var banner_tween: Tween

func setup(owner_game: Node) -> void:
	game = owner_game
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	for button in game.get_node("HUD/Root").find_children("*", "Button", true, false):
		button_feedback(button)
	get_tree().node_added.connect(func(node: Node):
		if node is Button and game.is_ancestor_of(node): button_feedback(node)
	)
	for side in ["H", "T"]:
		var letter := "M87 78h20v40h42V78h20v100h-20v-40h-42v40H87z" if side == "H" else "M84 78h88v20h-34v80h-20V98H84z"
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><defs><radialGradient id="g"><stop stop-color="#%s"/><stop offset=".75" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></radialGradient></defs><circle cx="128" cy="128" r="121" fill="url(#g)" stroke="#%s" stroke-width="5"/><circle cx="128" cy="128" r="103" fill="none" stroke="#%s" stroke-width="3"/><circle cx="128" cy="128" r="94" fill="none" stroke="#%s" stroke-width="2"/><path d="%s" fill="#%s"/></svg>' % [UI.GOLD.to_html(false), UI.BRONZE.to_html(false), UI.BRONZE.darkened(0.55).to_html(false), UI.TEXT.to_html(false), UI.BRONZE.darkened(0.5).to_html(false), UI.GOLD.to_html(false), letter, UI.INSET.to_html(false)]
		var image := Image.new()
		image.load_svg_from_string(svg)
		coin_textures.append(ImageTexture.create_from_image(image))

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
	var title = game.run_director.label("CALL THE COIN", 34, game.run_director.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint = game.run_director.label("Choose a side. Match the toss to take the first turn.", 19)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var coin_space := CenterContainer.new()
	coin_space.custom_minimum_size = Vector2(600, 340)
	box.add_child(coin_space)
	coin_sprite = TextureRect.new()
	coin_sprite.texture = coin_textures[0]
	coin_sprite.custom_minimum_size = Vector2(170, 170)
	coin_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_space.add_child(coin_sprite)
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
	var rest: Vector2 = coin_sprite.position
	coin_sprite.pivot_offset = coin_sprite.size / 2
	var toss := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	toss.tween_method(func(t: float):
		if epoch != coin_epoch: return
		coin_sprite.position = rest + Vector2(0, -70 * sin(t * PI))
		var angle := t * (TAU * 4 + PI * result)
		coin_sprite.scale.x = maxf(0.06, absf(cos(angle)))
		coin_sprite.rotation = sin(t * TAU) * 0.12
		coin_sprite.texture = coin_textures[0 if cos(angle) >= 0 else 1]
	, 0.0, 1.0, 1.15)
	await toss.finished
	if epoch != coin_epoch:
		event_root.queue_free()
		return -1
	coin_sprite.texture = coin_textures[result]
	coin_sprite.scale = Vector2.ONE
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

func button_feedback(button: Button) -> void:
	if button.has_meta("hover_feedback"): return
	button.set_meta("hover_feedback", true)
	var tween: Array = [null]
	var fill: Array = [null]
	var reference: WeakRef = weakref(button)
	var animate := func(scale_value: float, color: Color):
		var live_button = reference.get_ref()
		if not is_instance_valid(live_button) or live_button.is_queued_for_deletion(): return
		if tween[0]: tween[0].kill()
		if fill[0] == null:
			fill[0] = live_button.get_theme_stylebox("normal").duplicate()
			for state in ["normal", "hover", "pressed", "hover_pressed"]:
				live_button.add_theme_stylebox_override(state, fill[0])
		live_button.pivot_offset = live_button.size / 2
		tween[0] = live_button.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween[0].tween_property(live_button, "scale", Vector2.ONE * scale_value, 0.10)
		tween[0].tween_property(fill[0], "bg_color", color, 0.14)
	button.mouse_entered.connect(func():
		var live_button = reference.get_ref()
		if is_instance_valid(live_button) and not live_button.disabled: animate.call(1.0, UI.ACTION)
	)
	button.mouse_exited.connect(func(): animate.call(1.0, UI.BACKGROUND))
	button.button_down.connect(func(): animate.call(1.0, UI.CRIMSON))
	button.button_up.connect(func():
		var live_button = reference.get_ref()
		if is_instance_valid(live_button):
			animate.call(1.0, UI.ACTION if live_button.is_hovered() else UI.BACKGROUND)
	)

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

func banner(title: String, subtitle: String = "", color: Color = UI.GOLD, entry: bool = false) -> void:
	if blocking and not entry: return
	if banner_tween: banner_tween.kill()
	if is_instance_valid(banner_node): banner_node.queue_free()
	var panel := PanelContainer.new()
	panel.theme = UI.get_theme()
	banner_node = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 350
	panel.offset_right = -350
	panel.offset_top = 85
	panel.offset_bottom = 172
	panel.add_theme_stylebox_override("panel", UI.panel(UI.CRIMSON if entry else UI.PANEL, color))
	add_child(panel)
	UI.decorate(panel, entry)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	for words in [title, subtitle]:
		if words.is_empty(): continue
		var label = game.run_director.label(words, 26 if words == title else 16, color)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
	panel.modulate.a = 0
	banner_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	banner_tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	banner_tween.parallel().tween_property(panel, "offset_top", 96.0, 0.2).from(75.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if entry:
		banner_tween.parallel().tween_property(panel, "offset_left", 350.0, 0.2).from(550.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	banner_tween.tween_interval(0.65)
	banner_tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	banner_tween.tween_callback(panel.queue_free)
