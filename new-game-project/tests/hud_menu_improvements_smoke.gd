extends SceneTree

var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var director = game.run_director
	director.new_run()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	paused = false
	game.phase = game.Phase.PLAYER_PLAY
	game.plans.tokens = 2
	game.deck.append({"id":"count_fixture"})
	game.player_graveyard.append({"id":"grave_fixture"})
	director._process(0)
	check(director.plans_button.get_node("CountLabel").text == "2/2", "Plans count remains dynamic")
	check(director.graveyard_button.get_node("CountLabel").text == "1", "grave count remains dynamic")
	check(game._deck_count.text == str(game.deck.size()), "draw count remains dynamic")
	check(director.plans_button.text.is_empty() and director.graveyard_button.text.is_empty(), "counts use child labels")
	for path in ["DeckDrawButton", "PlansBox/PlansButton", "GraveyardButton"]:
		var button: Button = game.get_node("HUD/Root/" + path)
		check(button.size.x >= 100 and button.size.y >= 56, "consistent usable hit area")
		check(not button.tooltip_text.is_empty(), "hub tooltip preserved")
		check(button.get_global_rect().end.y <= root.get_visible_rect().size.y, "hub remains inside viewport")
	director.show_plans()
	await process_frame
	check(director.screen == "plans" and director.modal.get_meta("suspended_menu"), "contingencies use suspended skin")
	check(director.content.has_node("ReturnButton"), "Plans keeps return control")
	root.size_changed.emit()
	var panel_style: StyleBoxFlat = director.modal.get_theme_stylebox("panel")
	check(panel_style.bg_color.r > 0.8, "resize keeps cream backdrop under dark menu text")
	director.show_deck()
	director.close_modal()
	panel_style = director.modal.get_theme_stylebox("panel")
	check(director.screen == "plans" and director.modal.get_meta("suspended_menu"), "restored Plans keeps frame metadata")
	check(panel_style.bg_color.r > 0.8, "restored Plans keeps cream backdrop")
	director.close_modal()
	director.show_menu()
	await process_frame
	check(director.content.has_node("ResumeButton") and director.content.has_node("DebugButton"), "menu controls retained")
	director.show_settings()
	await process_frame
	check(director.content.get_node("effects_enabled") is CheckButton, "effects setting present")
	check(director.content.get_node("boss_fog_enabled") is CheckButton, "fog setting present")
	for key in ["effects_enabled", "boss_fog_enabled"]:
		var original: bool = game.get(key)
		var toggle: CheckButton = director.content.get_node(key)
		toggle.button_pressed = not original
		check(game.get(key) == not original, "setting button updates only its own game preference")
		toggle.button_pressed = original
	director.show_menu_from_settings()
	director.close_modal()
	director.show_buff_choices()
	await process_frame
	check(director.buff_choices.size() == 3, "adaptation retains three real offers")
	check(director.modal.get_meta("suspended_menu"), "adaptation uses suspended skin")
	game.queue_free()
	await process_frame
	print("HUD/menu improvements smoke: %d failures" % failures)
	quit(1 if failures else 0)
