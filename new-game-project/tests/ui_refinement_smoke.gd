extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
var failures := 0
var output := ""
var game: Node
var director: Node
var target_size := Vector2i(1440, 900)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--width="):
			var width := int(argument.trim_prefix("--width="))
			target_size = Vector2i(width, 800 if width == 1280 else 900)
	root.size = target_size
	var presentation := preload("res://scripts/game_presentation.gd").new()
	root.add_child(presentation)
	var button := Button.new()
	button.theme = UI.get_theme()
	root.add_child(button)
	preload("res://scripts/suspended_menu.gd").style_children(root)
	var states := {}
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		states[state] = button.get_theme_stylebox(state)
	var original_color: Color = states.normal.bg_color
	presentation.button_feedback(button)
	for i in 5:
		button.mouse_entered.emit()
		button.button_down.emit()
		button.button_up.emit()
		button.mouse_exited.emit()
		await create_timer(0.16).timeout
	for state in states:
		check(button.get_theme_stylebox(state) == states[state], "Feedback preserves " + state)
	check(button.get_theme_stylebox("normal").bg_color == original_color, "Exit restores cream normal fill")
	button.disabled = true
	button.mouse_exited.emit()
	await create_timer(0.16).timeout
	check(button.get_theme_stylebox("disabled") == states.disabled, "Disabled state survives exit")
	check(UI.get_theme().default_font is FontFile, "Non-card UI uses bundled font")
	check(UI.get_theme().default_font.resource_path.ends_with("CaveatBrush-Regular.ttf"), "UI uses Caveat Brush")
	check(UI.card_font(true) is SystemFont and UI.card_font(true).font_weight == 700,
		"Card headings retain their original bold system font")
	check(UI.card_font().font_names[0] == "Bahnschrift Condensed", "Card font family is preserved")
	button.queue_free()
	presentation.queue_free()
	await process_frame
	await game_checks()
	print("UI REFINEMENTS: %d failures" % failures)
	quit(1 if failures else 0)

func capture(screen: String) -> void:
	root.size = target_size
	await create_timer(0.35).timeout
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	check(pixels.get_size() == target_size, "Capture uses the requested resolution")
	pixels.save_png(output.path_join(screen + ".png"))

func battle() -> void:
	paused = false
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func game_checks() -> void:
	game = preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await capture("title")
	director.new_run()
	battle()
	game.add_card_to_hand(director.collection[0])
	await process_frame
	var card: Node = game.get_hand_cards()[0]
	for text in card._vp.find_children("*", "Label", true, false):
		check(text.get_theme_font("font") is SystemFont, "Rendered card text retains system fonts")
	director.inspect_board_card(card, true)
	await capture("card_inspection")
	director.close_modal()
	battle()
	for hp in [1, game.hero_max_hp()]:
		game.player_hp = hp
		game.enemy_hp = hp
		game.tension = 1 if hp == 1 else game.tension_cap
		game._set_health(game._player_hp_ui, hp, game.hero_max_hp(), false)
		game._set_health(game._enemy_hp_ui, hp, game.enemy_max_hp, false)
		await capture("hud_%d" % hp)
		check(game._player_hp_ui.get_node("Value").text == "%d / %d" % [hp, game.hero_max_hp()],
			"Student health value remains dynamic")
		check(director.threat.get_parent().get_node("Value").text == "%d / %d" % [game.tension, game.tension_cap],
			"Tension value remains dynamic")
	game.plans.tokens = 2
	director.show_plans()
	await capture("plans")
	check(director.content.get_node("Status").text == "PLANS 2 / 2", "Plans heading omits unlock count")
	battle()
	game.turn = 5
	director.buff_choices = director.Rules.BUFFS.filter(func(buff): return buff.id in ["blood_pact", "overclock", "precision"])
	game.player_buffs = {"strength": 2, "blood_pact": 1, "precision": 1, "overclock": 1}
	director.show_buff_choices(true)
	await capture("adaptations")
	var heading: Label = director.content.get_node("Center/Box").get_child(0)
	check(director.modal_scroll.get_global_rect().encloses(heading.get_global_rect()),
		"Adaptation heading remains visible with focused choice")
	for details in director.content.find_children("Details", "Label", true, false):
		check(details.get_line_count() * details.get_line_height() <= details.size.y + 2,
			"Long adaptation descriptions fit")
	for pick in director.content.find_children("PickButton", "Button", true, false):
		check(root.get_visible_rect().encloses(pick.get_global_rect()), "Adaptation choice fits viewport")
	var picks: Array = director.content.find_children("PickButton", "Button", true, false)
	picks[1].toggle_mode = true
	picks[1].button_pressed = true
	picks[2].disabled = true
	await capture("adaptation_states")
	battle()
	for title in ["JANITOR'S TURN", "CLASH"]:
		game.presentation.banner(title, "Watch the opposing formation")
		await capture(title.to_lower().replace("'", "").replace(" ", "_"))
		await create_timer(1.0).timeout
		check(not is_instance_valid(game.presentation.banner_node), "Announcement cleans up")
	check(preload("res://scripts/battle_vfx.gd").PROFILES.evac[0] == "wind", "Evac uses wind visuals")
	var location: Vector3 = game._response_slots()[2].global_position
	game.vfx.impact("evac", location)
	await create_timer(0.6).timeout
	game.vfx.impact("evac", location)
	await create_timer(0.1).timeout
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("evac_wind.png"))
	await create_timer(0.6).timeout
	check(game.vfx._bursts.is_empty(), "Wind bursts keep their existing cleanup timing")
