extends SceneTree
## Targeted captures requested for the changed menus, hubs, coin, fog and particles only.
var game: Node
var director: Node
const OUTPUT := "res://tests/artifacts/improvements/"

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "_1280" if "--small" in OS.get_cmdline_user_args() else ""
	root.get_texture().get_image().save_png(OUTPUT + name + suffix + ".png")
	print("CAPTURE: " + name)

func unit(lane: int, side: String, element: String) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":"review", "name":"Review " + element, "type":side, "element":element,
		"cost":1, "attack":2, "health":12, "modifier":"armored", "on_hit":{"burn":2}})
	card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	return card

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800) if "--small" in OS.get_cmdline_user_args() else Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	paused = false
	game.clear_battle()
	game.phase = game.Phase.PLAYER_PLAY
	game.turn = 3
	game.player_first = false
	game.plans.tokens = 2
	game.effects_enabled = true
	game.set_view(game.View.BOARD)
	var target = unit(0, "disaster", "fire")
	unit(1, "disaster", "flood")
	unit(2, "disaster", "typhoon")
	unit(3, "disaster", "earthquake")
	var ally = unit(0, "response", "douse")
	unit(1, "response", "evac")
	game.seal_field_card(target)
	target.add_status("burn", 3)
	target.add_status("poison", 2)
	await create_timer(1.8).timeout
	await capture("arena_hubs_symbols_status")
	director.show_plans()
	await create_timer(0.3, true).timeout
	await capture("contingencies")
	director.close_modal()
	director.show_menu()
	await create_timer(0.3, true).timeout
	await capture("game_menu")
	director.show_settings()
	await create_timer(0.3, true).timeout
	await capture("settings")
	director.close_modal()
	director.show_buff_choices()
	await create_timer(0.3, true).timeout
	await capture("adaptation")
	director.close_modal()
	game.boss_fog.set_active(true)
	await capture("boss_arena_fog")
	for lane in 4:
		var attacker = game._get_card_in_slot(game._threat_slots()[lane])
		game.vfx.attack_start(attacker, ally.global_position)
		game.vfx.impact(attacker.card_data.element, attacker.global_position)
	await create_timer(0.14).timeout
	await capture("element_particles")
	director.current = int(director.rooms.back().id)
	director.screen = ""
	director.show_map()
	await create_timer(0.6, true).timeout
	await capture("boss_map_fog")
	director.close_modal()
	var panel := ColorRect.new()
	panel.color = Color("17191c")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.presentation.add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var view: SubViewportContainer = game.presentation.make_coin_view()
	view.custom_minimum_size = Vector2(620, 620)
	center.add_child(view)
	await capture("coin_heads")
	game.presentation.coin_pivot.rotation.x = PI
	await capture("coin_tails")
	game.queue_free()
	await process_frame
	quit(0)
