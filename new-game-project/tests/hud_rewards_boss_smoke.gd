extends SceneTree

var failures := 0
var game: Node
var director: Node
var output := ""
var underlying_clicks := 0
var target_size := Vector2i(1440, 900)

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func capture(title: String) -> void:
	await create_timer(0.4).timeout
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	check(pixels.get_size() == target_size, "Capture uses requested dimensions")
	pixels.save_png(output.path_join(title + ".png"))

func battle() -> void:
	paused = false
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--width="):
			target_size = Vector2i(int(argument.trim_prefix("--width=")), 800)
	root.size = target_size
	game = preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	director.new_run()
	battle()
	await process_frame
	# Finish the startup frame before measuring timers against tween progress.
	await process_frame
	var tension_panel: Control = director.threat.get_parent()
	var enemy_rect: Rect2 = game._enemy_hp_ui.get_global_rect()
	var tension_rect := tension_panel.get_global_rect()
	check(tension_rect.size.y <= 44, "Tension panel is compact")
	check(is_equal_approx(tension_rect.position.x, enemy_rect.position.x), "Tension aligns with enemy HP")
	check(tension_rect.position.y - enemy_rect.end.y <= 6, "Tension sits directly below enemy HP")
	var hud: Control = game.get_node("HUD/Root")
	for path in ["EndTurnButton", "PlansBox/PlansButton"]:
		var control: Control = hud.get_node(path)
		var margin := hud.size.y - control.get_rect().end.y
		if path == "PlansBox/PlansButton":
			margin = hud.size.y - (control.get_parent().position.y + control.get_rect().end.y)
		check(margin >= 8 and margin <= 16, "Bottom-right actions use a safe bottom margin")
	for health in [game._player_hp_ui, game._enemy_hp_ui]:
		check(health.size.x <= 310 and health.size.y <= 54, "Health panel is compact")
		check(health.get_node("Bar").size.y <= 22, "HP fill is thin")
		for hp in [0, 1, 17, 34]:
			game._set_health(health, hp, 34, false)
			check(health.get_node("Value").text == "%d / 34" % hp, "HP values remain exact")
		game._set_health(health, 34, 34, false)
		game._set_health(health, 1, 34, true)
		await create_timer(0.25).timeout
		check(is_equal_approx(health.get_node("Bar").value, 1), "HP bar reaches damaged value")
		check(is_equal_approx(health.get_node("LagBar").value, 34), "Damage lag remains delayed")
		await create_timer(0.8).timeout
		check(is_equal_approx(health.get_node("LagBar").value, 1), "Damage lag reaches final value")
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game._refresh_bars()
	var caption: Label = game._enemy_hp_ui.get_node("Caption")
	caption.text = "MIDNIGHT WARDEN"
	check(caption.get_theme_font("font").get_string_size(caption.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x <= caption.size.x,
		"Full Midnight Warden label fits")
	game.final_boss = preload("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	await process_frame
	var panel: Control = director.boss_intent.get_parent()
	check(director.boss_intent.get_theme_color("font_color") == Color.WHITE, "Boss intent is white")
	check(director.boss_intent.get_theme_font_size("font_size") >= 24, "Boss intent is larger")
	check(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "Intent consumes clicks")
	await capture("compact_hud_and_intent")
	if panel.has_method("_gui_input"):
		var original_turn: int = game.turn
		var original_stage: int = game.final_boss.stage
		var underneath := Button.new()
		director.root.add_child(underneath)
		director.root.move_child(underneath, 0)
		underneath.position = panel.position
		underneath.size = panel.size
		underneath.pressed.connect(func(): underlying_clicks += 1)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = panel.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = true
		root.push_input(event, true)
		await process_frame
		var release := event.duplicate()
		release.pressed = false
		root.push_input(release, true)
		await process_frame
		await process_frame
		check(not panel.visible, "Dismissal persists through HUD updates")
		check(underlying_clicks == 0, "Dismissal does not click controls underneath")
		check(not director.inspect_hold_pending and not is_instance_valid(game.dragged_hand_card),
			"Dismissal does not inspect or drag board cards")
		underneath.queue_free()
		check(game.turn == original_turn and game.final_boss.stage == original_stage,
			"Dismissal preserves turn and phase")
		check(game.final_boss.last_resolved_round == -1, "Dismissal does not resolve boss actions")
		game.final_boss.resolve_intent()
		check(game.final_boss.last_resolved_round == game.turn, "Dismissed intent still resolves normally")
		check(caption.tooltip_text.contains(game.final_boss.intent()), "Intent remains in HP tooltip")
		game.turn += 1
		await process_frame
		check(panel.visible, "Next round intent appears normally")
	else:
		check(false, "Boss announcement supports dismissal")
	await reward_checks()
	director.persistence.discard()
	print("HUD / REWARDS / BOSS: %d failures" % failures)
	quit(1 if failures else 0)

func reward_checks() -> void:
	game.clear_battle()
	director.battle_active = false
	director.show_contingency_reward("cards")
	await capture("contingency_reward")
	check_reward_tiles()
	check(director.modal.get_meta("suspended_menu", false), "Contingency uses suspended noticeboard")
	var offers: Array = director.buff_choices.duplicate(true)
	check(director.persistence.checkpoint(), "Contingency saves")
	check(director.persistence.resume(), "Contingency resumes")
	check(director.buff_choices == offers, "Continue preserves exact contingency offers")
	var chosen: String = director.buff_choices[0].id
	director.select_contingency_reward(chosen)
	check(chosen in game.plans.unlocked, "Selected contingency unlocks")
	var count: int = game.plans.unlocked.size()
	director.select_contingency_reward(chosen)
	check(game.plans.unlocked.size() == count, "Contingency claim happens once")
	var first: Dictionary = director.collection[0].duplicate(true)
	var second: Dictionary = first.duplicate(true)
	second.test_copy = "specific rewarded copy"
	director.reward_stock.assign([first, second])
	director.show_rewards()
	await capture("card_reward")
	for preview in director.content.find_children("*", "Node3D", true, false):
		if not preview.get("preview_only"): continue
		check(preview._cost_label.get_theme_color("font_color") == director.UI.TEXT,
			"Reward skin preserves card face colors")
		check(preview._cost_label.get_theme_font("font") is SystemFont,
			"Reward skin preserves original card face font")
	check(director.modal.get_meta("suspended_menu", false), "Card rewards use noticeboard")
	check(director.persistence.checkpoint() and director.persistence.resume(), "Card rewards resume")
	check(director.reward_stock[1].get("test_copy") == second.test_copy, "Exact reward copy survives Continue")
	director.select_reward(1)
	await capture("card_reward_inspection")
	var before: int = director.collection.size()
	director.select_reward(1)
	director.select_reward(1)
	check(director.collection.size() == before + 1, "Card is claimed exactly once")
	check(director.collection.back().get("test_copy") == second.test_copy, "Exact selected copy is awarded")
	director.reward_stock.assign([first])
	director.show_rewards()
	before = director.collection.size()
	var skip: Button = director.content.get_node("Center/Box/SkipButton")
	skip.pressed.emit()
	check(director.collection.size() == before and director.screen != "reward", "Skipping grants no card")
	director.show_floor_buffs()
	await capture("floor_reward")
	check_reward_tiles()
	check(director.modal.get_meta("suspended_menu", false), "Floor rewards use noticeboard")

func check_reward_tiles() -> void:
	var checked := 0
	for tile in director.content.find_children("*", "PanelContainer", true, false):
		if not tile.has_node("Box/PickButton"): continue
		checked += 1
		check(tile.size.x >= 250, "Reward choices have readable column widths")
		check(director.modal.get_global_rect().encloses(tile.get_global_rect()), "Reward choice fits noticeboard")
	check(checked == director.buff_choices.size(), "Every offered choice has been checked")
