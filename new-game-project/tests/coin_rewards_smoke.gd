extends SceneTree
var game: Node
var director: Node
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/oct15_" + name + ".png")

func banner_style_checks() -> void:
	for entry in [true, false]:
		game.presentation.banner("DISASTER ENCOUNTER", "Prepare your formation", director.GOLD, entry)
		var banner: PanelContainer = game.presentation.banner_node
		var style: StyleBoxFlat = banner.get_theme_stylebox("panel")
		var strip: ColorRect = banner.get_node("BannerStrip")
		var material: ShaderMaterial = strip.material
		check(style.bg_color == Color.TRANSPARENT
			and material.get_shader_parameter("fill_color") == Color(director.UI.INSET, 0.94),
			"encounter and turn banners use a translucent dark strip")
		check(material.shader == load("res://scripts/banner_strip.gdshader")
			and material.get_shader_parameter("line_color") == Color("ffc16b")
			and material.get_shader_parameter("line_width") == 2.5,
			"banner uses the soft edge shader with two full width glowing amber lines")
		check(style.border_width_bottom == 0 and style.border_width_left == 0
			and style.border_width_right == 0, "banner omits full width borders")
		check(style.border_width_top == 0 and not banner.has_node("IndustrialTrim"),
			"banner omits the hazard bar and heavy frame")
		check(banner.anchor_left == 0.0 and banner.anchor_right == 1.0
			and banner.offset_left == 0 and banner.offset_right == 0,
			"banner spans the full screen width")
		check(banner.anchor_top == 0.5 and banner.anchor_bottom == 0.5
			and banner.offset_top == -64 and banner.offset_bottom == 64,
			"banner is centered vertically over the board")
		var title: Label = banner.get_child(0).get_child(0)
		check(title.text == "DISASTER ENCOUNTER" and title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
			"banner keeps its centered uppercase title")
		var heading_font: FontVariation = title.get_theme_font("font")
		check(title.get_theme_color("font_color") == director.UI.TEXT
			and title.get_theme_font_size("font_size") == 48
			and heading_font.base_font == director.UI.font(true) and heading_font.spacing_glyph == 2,
			"banner title uses the bold condensed heading font in off-white")
		var subtitle: Label = banner.get_child(0).get_child(1)
		check(subtitle.text == "Prepare your formation"
			and subtitle.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
			and subtitle.get_theme_color("font_color") == director.UI.TEXT.darkened(0.12)
			and subtitle.get_theme_font_size("font_size") == 20
			and subtitle.get_theme_font_size("font_size") < title.get_theme_font_size("font_size"),
			"banner preserves its smaller dim centered subtitle")
		check(banner.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and strip.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and banner.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE
			and title.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and subtitle.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"banner and its children let card input pass through")
		await create_timer(0.25).timeout
		var screen_center: Vector2 = root.get_visible_rect().get_center()
		check(banner.get_global_rect().get_center().distance_to(screen_center) < 2.0,
			"banner settles at the screen center after its slide")
		game.presentation.clear_banner()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.discard()
	director.new_run()
	await banner_style_checks()
	await create_timer(0.6).timeout
	director.visit(0)
	check(game.presentation.blocking and game.phase == game.Phase.SETUP, "battle entry animation blocks input")
	await create_timer(1.2).timeout
	check(game.presentation.blocking and director.screen == "coin" and game.phase == game.Phase.SETUP, "real encounter waits for a coin selection")
	check(game.presentation.choice_buttons.size() == 2 and game.coin_pick == -1, "both Heads and Tails are interactive")
	await create_timer(0.25).timeout
	check(game.presentation.coin_root.size.is_equal_approx(root.get_visible_rect().size), "coin event covers full screen")
	await capture("coin_choice")
	var result: int = game.coin_result
	check(director.persistence.checkpoint() and director.persistence.read_save().screen == "coin", "unresolved coin event saves")
	check(director.persistence.resume() and game.coin_result == result and game.coin_pick == -1, "continue preserves pending toss and held cards")
	game.presentation.choice_buttons[result].pressed.emit()
	check(game.coin_pick == result and game.presentation.choice_buttons.all(func(button): return button.disabled), "selection locks both buttons immediately")
	game.presentation.select_coin(1 - result)
	check(game.coin_pick == result, "repeated choices cannot change call or outcome")
	await create_timer(0.45).timeout
	await capture("coin_toss")
	check(director.persistence.resume(), "continue during animation restores the chosen call")
	for i in 60:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	check(not game.presentation.blocking and game.player_first and game.coin_result == result and game.coin_pick == result, "winning call actually plays first with no reroll")
	if game.phase == game.Phase.PLAYER_DRAW:
		game._on_draw_button_pressed()
	check(game.can_player_act(), "coin resolves into playable turn")
	var card = game.get_hand_cards()[0]
	game.hand.erase(card)
	card.reparent(game, true)
	card.place_on_slot(game._response_slots()[0])
	await create_timer(0.6).timeout
	director.inspect_board_card(card)
	await create_timer(0.25).timeout
	var face: TextureRect = director.inspected_face
	check(is_equal_approx(face.size.x / face.size.y, float(card.FACE_W) / card.FACE_H), "inspection preserves native aspect ratio")
	var inspection_row: Control = face.get_parent().get_parent()
	check(absf(inspection_row.get_global_rect().get_center().x - root.get_visible_rect().size.x / 2) < 2, "card and side description are centered together")
	await capture("inspection")
	var inside := InputEventMouseButton.new()
	inside.pressed = true
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.global_position = face.get_global_rect().get_center()
	director._modal_input(inside)
	check(director.screen == "inspect" and paused, "clicking the card keeps inspection open")
	inside.global_position = Vector2(10, 10)
	inside.position = Vector2(10, 10)
	root.push_input(inside)
	await process_frame
	check(not director.modal.visible and not paused, "outside-card click dismisses and resumes")
	game.enemy_hp = 0
	game._check_game_over()
	check(director.screen == "reward" and not director.battle_active, "victory reaches reward modal")
	var offers: Array = director.reward_stock.duplicate(true)
	await create_timer(1.1).timeout
	await capture("rewards")
	var images: Array = director.reward_faces
	check(images.size() == 3, "three actual card faces are shown")
	check(images.all(func(image): return absf(image.size.x / image.size.y - 264.0 / 360.0) < 0.01), "all reward faces preserve card shape")
	var mean_x := 0.0
	for image in images: mean_x += image.get_global_rect().get_center().x / 3
	check(absf(mean_x - root.get_visible_rect().size.x / 2) < 2, "reward trio is horizontally centered")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_D
	director._input(key)
	check(director.screen == "reward" and not game.can_player_act(), "background shortcuts and plays are blocked")
	check(director.persistence.checkpoint() and director.persistence.resume() and director.reward_stock == director.persistence.normalize(offers), "centered reward offers remain stable through Continue")
	var before: int = director.collection.size()
	var chosen_id: String = director.reward_stock[0].id
	director.select_reward(0)
	check(director.collection.size() == before and director.reward_selection == 0, "first reward click inspects without acquisition")
	director.select_reward(0)
	director.select_reward(0)
	check(director.collection.size() == before + 1 and director.collection.back().id == chosen_id and director.screen == "map", "chosen reward is acquired exactly once even on double click")
	director.current = 3
	director.show_shop()
	await create_timer(0.3).timeout
	await capture("shop")
	check(is_equal_approx(director.content.modulate.a, 1.0) and director.content.scale.is_equal_approx(Vector2.ONE), "shop reveal settles cleanly")
	check(game.get_node("Playmat").has_node("SchoolDrillBoard") and game.get_node("Playmat").find_children("*", "Label3D", true, false).is_empty(), "saved native board asset has no zone labels")
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	paused = false
	game._set_phase(game.Phase.PLAYER_PLAY)
	card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":"defeat", "name":"Test unit", "type":"response", "element":"evac", "cost":1, "attack":2, "health":3})
	card.place_on_slot(game._response_slots()[0])
	await create_timer(0.5).timeout
	card.take_damage(999, true)
	check(card.current_slot == null and card not in get_nodes_in_group("cards"), "defeat frees gameplay slot before dissolve finishes")
	await create_timer(0.25).timeout
	await capture("dissolve")
	await create_timer(0.9).timeout
	check(not is_instance_valid(card), "defeat animation cleans up its node")
	game.clear_battle()
	director.screen = ""
	director.battle_active = true
	game.start_encounter(director.collection, "battle", 1, 0)
	await create_timer(1.2).timeout
	var losing_pick: int = 1 - game.coin_result
	game.presentation.choice_buttons[losing_pick].pressed.emit()
	for i in 70:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	check(not game.player_first and not game.presentation.blocking, "a losing call gives the Janitor the actual first turn")
	check(game.presentation.get_children().filter(func(node): return str(node.name).begins_with("CoinFlip")).is_empty(), "cancelled and completed coin overlays are freed")
	director.persistence.discard()
	if failures:
		quit(1)
		return
	print("PASS: manual coin calls, duplicate guard, pending/mid-toss Continue, actual first side, native-ratio inspection/outside dismissal, centered exclusive rewards/exact acquisition, stable saves, shop entrance, board asset and dissolve cleanup")
	quit()
