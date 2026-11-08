extends SceneTree

var checks := 0
var failures := 0
var manual := false
var rendered := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func wait_until(predicate: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < 4000: await process_frame
	return predicate.call()

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func capture(name: String) -> void:
	if not rendered: return
	await create_timer(0.5, true).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../batch2-part3-renders")
	DirAccess.make_dir_recursive_absolute(folder)
	expect(root.get_texture().get_image().save_png(folder + "/" + name + ".png") == OK, name + " screenshot")

func definition() -> Dictionary:
	return {"id": "ember", "name": "Ember", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 2}

func fixture(game: Node) -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.evolution_draw_choice_override = false
	game.turn = 3
	game.set_seats("local", "local")
	game.enemy_deck.assign([definition(), definition()])
	game.run_director.battle_active = true
	game.run_director.encounter = "versus"
	game.run_director.close_modal()
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()

func run() -> void:
	rendered = "--render-draw" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 800)
	var flags: Script = load("res://scripts/versus_match.gd")
	# The flag now ships true, so the test follows the shipped value. --expect-manual still asks for the manual path.
	var shipped: bool = flags.get_script_constant_map().get("DISASTER_DRAW_BUTTON", false)
	manual = shipped or "--expect-manual" in OS.get_cmdline_user_args()
	expect(shipped == manual, "Draw flag matches tested state")
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	if game.get("disaster_draw") == null:
		expect(false, "Local Disaster draw gate exists")
	else:
		await check_draw(game)
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: disaster_draw_button_smoke (%d checks, manual=%s)" % [
		"FAIL" if failures else "PASS", checks, manual])
	quit(1 if failures else 0)

func check_draw(game: Node) -> void:
	fixture(game)
	var gate: RefCounted = game.disaster_draw
	game._enemy_turn()
	expect(await wait_until(func(): return game.disaster_waiting), "Disaster reaches human turn")
	var button: Button = game.get_node("HUD/Root/DeckDrawButton")
	if manual:
		expect(gate.waiting and game.enemy_hand.is_empty(), "Manual state waits without drawing")
		expect(game.disaster_actions.busy and game._end_turn_btn.disabled, "Draw blocks play and End Turn")
		expect(not (await game.disaster_actions.end_turn()).ok, "Cannot end before manual draw")
		await frames()
		expect(not button.disabled, "Disaster deck button accepts manual draw")
		await capture("before-disaster-draw")
		await click(button)
		expect(await wait_until(func(): return not game.disaster_actions.busy), "Draw releases action gate")
		expect(game.enemy_hand.size() == 1 and game.enemy_deck.size() == 1, "One click draws one card")
		await capture("after-disaster-draw")
		game._on_draw_button_pressed()
		expect(game.enemy_hand.size() == 1, "Duplicate draw rejected")
	else:
		expect(not gate.waiting and game.enemy_hand.size() == 1, "Default false keeps automatic draw")
		expect(button.disabled, "Default Disaster deck button stays disabled")
	game._set_phase(game.Phase.GAME_OVER)
	await frames()
	for count in [0, 6]:
		fixture(game)
		if count == 0: game.enemy_deck.clear()
		else:
			for i in count: game.enemy_hand.append(definition())
		game._enemy_turn()
		expect(await wait_until(func(): return game.disaster_waiting and not game.disaster_actions.busy),
			"Empty deck or full hand never waits for draw")
		expect(not gate.waiting, "Unavailable draw skips manual gate")
		game._set_phase(game.Phase.GAME_OVER)
		await frames()
	fixture(game)
	for seats in [["remote", "local"], ["local", "remote"]]:
		game.set_seats(seats[0], seats[1])
		expect(not gate.enabled(), "LAN retains automatic Disaster draw")
	game.set_seats("local", "local")
	game.encounter_kind = "battle"
	expect(not gate.enabled(), "Singleplayer stays automatic")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	expect(not gate.enabled(), "AI Versus stays automatic")
	if manual:
		fixture(game)
		game._enemy_turn()
		expect(await wait_until(func(): return gate.waiting), "Cancellation fixture waits for draw")
		game.clear_battle()
		var serial: int = game.encounter_serial
		await frames()
		expect(not gate.waiting and game.encounter_serial == serial and game.enemy_hand.is_empty(),
			"Restart cancels draw without stale callback mutation")
