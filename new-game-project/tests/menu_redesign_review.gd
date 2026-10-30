extends SceneTree
## Reproducible menu inventory. Saves are disabled before constructing any run state.
var game: Node
var director: Node
var output := "C:/Users/0stef/Downloads/midnight-menu-review/revised"

func _initialize() -> void:
	call_deferred("run")

func capture(screen_name: String) -> void:
	await create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%d.png" % [output, screen_name, root.size.x]
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Capture failed: " + path)
		quit(1)
	print("CAPTURE ", screen_name)

## Opens one screen from a clean state and captures it.
func shot(screen_name: String, open: Callable, in_battle: bool = false) -> void:
	director.close_modal()
	director.screen = ""
	director.battle_active = in_battle
	# The victory capture ends the run; later screens still belong to a live run.
	director.run_active = true
	open.call()
	await capture(screen_name)

## Long lists, disabled buttons, pickers, confirmations and the end screens.
func extra_states() -> void:
	var starter: Array = director.collection.duplicate(true)
	while director.collection.size() < 30: director.collection.append(starter.pick_random().duplicate(true))
	await shot("deck-full", director.show_deck)
	game.player_graveyard.assign(starter.duplicate(true))
	await shot("graveyard-full", director.show_graveyard, true)
	game.player_graveyard.clear()
	await shot("upgrade-preview", func(): director.show_upgrade(); director.show_upgrade_preview(0))
	await shot("remove", func(): director.show_remove_cards("shop"))
	await shot("remove-confirm", func(): director.show_remove_cards("shop"); director.preview_remove(0))
	director.coins = 0
	await shot("shop-broke", director.show_shop)
	director.coins = 100
	await shot("intel", director.show_intel, true)
	await shot("buffs", director.show_buff_choices, true)
	await shot("floor-buffs", director.show_floor_buffs)
	await shot("pick-card", func(): director.choose_card("CHOOSE A CARD", starter.slice(0, 3),
		func(_card): pass, func(): pass), true)
	await shot("pick-lane", func(): director.choose_slot(game._response_slots(), func(_slot): pass,
		func(): pass), true)
	await shot("confirm-title", director.confirm_title, true)
	await shot("confirm-abandon", director.confirm_abandon)
	await shot("defeat", func(): director.battle_finished(false), true)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900) if "--large" in OS.get_cmdline_user_args() else Vector2i(1280, 800)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await process_frame
	director.show_characters()
	await capture("characters")
	director.show_character_preview(0)
	await capture("character-preview")
	director.new_run()
	director.coins = 100
	game.player_hp = 12
	for method in ["show_rest", "show_shop", "show_upgrade", "show_deck", "show_graveyard",
		"show_menu", "show_settings", "show_battle_log", "show_debug", "show_run_victory"]:
		director.close_modal()
		director.screen = ""
		director.battle_active = method in ["show_graveyard", "show_menu", "show_settings", "show_battle_log", "show_debug"]
		director.call(method)
		await capture(method.trim_prefix("show_"))
	director.battle_active = false
	for event in ["radio", "rooftop", "science", "infirmary", "lost_found", "locked"]:
		director.close_modal()
		director.current = 0
		director.rooms[0]["event"] = event
		director.event_key = ""
		director.show_event()
		await capture("event-" + event)
	await extra_states()
	game.queue_free()
	await process_frame
	quit()
