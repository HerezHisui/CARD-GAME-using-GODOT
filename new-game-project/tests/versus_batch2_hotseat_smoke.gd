extends SceneTree

var failures := 0
var checks := 0
var rendered := false
var output := "res://../docs/notes/batch2-part1"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(folder)
	expect(root.get_texture().get_image().save_png(folder + "/" + name + ".png") == OK, name + " screenshot")

func fixture(game: Node) -> void:
	paused = false
	game.clear_battle()
	var director: Node = game.run_director
	director.battle_active = true
	director.encounter = "versus"
	director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.set_seats("local", "local")
	director.privacy_serial = game.encounter_serial
	director.privacy_last = ""
	director.privacy_screen.hide()
	game._set_phase(game.Phase.SETUP)

func check_opening(game: Node) -> void:
	fixture(game)
	var director: Node = game.run_director
	var card := {"id": "fixture", "name": "Fixture", "type": "response", "cost": 0,
		"attack": 1, "health": 2, "element": "fire"}
	game.add_card_to_hand(card)
	game.enemy_deck.assign([card.duplicate(true)])
	game.player_first = false
	game.turn = 1
	# The opening evolution picker previously marked this side as already covered.
	director.privacy_last = "disaster"
	game._enemy_turn()
	var exposed := false
	var start := Time.get_ticks_msec()
	while not game.disaster_waiting and Time.get_ticks_msec() - start < 3000:
		if game.hand_container.visible and not director.privacy_screen.visible: exposed = true
		await process_frame
	await frames()
	expect(not exposed, "Disaster opening never exposes Preparedness faces before the cover")
	expect(game.disaster_waiting and director.privacy_screen.visible, "Opening gets its first-turn cover")
	expect(not game.hand_container.visible, "Preparedness hand stays hidden under opening cover")
	await capture("disaster-first-cover")
	director._hide_privacy_screen()
	await frames()
	expect(game.hand_container.visible and game.is_hand_tucked, "Ready restores the tucked hand")
	game._set_phase(game.Phase.GAME_OVER)
	await frames()

func check_finish(game: Node) -> void:
	fixture(game)
	var director: Node = game.run_director
	director.start_versus_match()
	var match_node: Node = director.versus_match
	var start := Time.get_ticks_msec()
	while not is_instance_valid(game.presentation.coin_root) and Time.get_ticks_msec() - start < 4000:
		await process_frame
	expect(is_instance_valid(game.presentation.coin_root), "Pending coin fixture reaches coin screen")
	var serial: int = game.encounter_serial
	var epoch: int = game.presentation.coin_epoch
	director.battle_finished(true)
	expect(game.encounter_serial == serial + 1, "Finish invalidates encounter callbacks")
	expect(game.presentation.coin_epoch > epoch and not game.presentation.blocking, "Finish cancels pending coin")
	expect(not is_instance_valid(game.presentation.coin_root), "Finish removes pending coin UI")
	await create_timer(1.4, true).timeout
	expect(director.screen == "result" and not match_node.running, "Late coin cannot replace result")
	# Finish while the opening callback is still waiting, then start a fresh encounter.
	fixture(game)
	match_node.start()
	director.battle_finished(false)
	game.clear_battle()
	var restart_serial: int = game.encounter_serial
	await create_timer(1.3, true).timeout
	expect(game.encounter_serial == restart_serial and not is_instance_valid(game.presentation.coin_root),
		"Old opening callback cannot start a coin after restart")

func check_menu(game: Node) -> void:
	fixture(game)
	var director: Node = game.run_director
	game._set_phase(game.Phase.PLAYER_PLAY)
	director.privacy_last = "prep"
	game.add_card_to_hand({"id": "drag", "name": "Drag fixture", "type": "response", "element": "fire",
		"cost": 0, "attack": 1, "health": 2})
	await frames()
	var card: Node = game.get_hand_cards()[0]
	card._start_drag()
	expect(card.is_dragging and game.dragged_hand_card == card, "Fixture starts a real hand drag")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await frames()
	expect(director.screen == "menu" and director.modal.visible, "Escape opens Menu during drag")
	expect(not card.is_dragging and not is_instance_valid(game.dragged_hand_card), "Menu cancels drag ownership")
	expect(card.in_hand and card.get_parent() == game.hand_parent(), "Menu returns card to hand")
	expect(not game._slots_lit and game.get_hand_cards().size() == 1, "Menu clears targets without losing card")
	await capture("menu-after-drag")
	director.close_modal()
	card.cancel_hand_drag()

func check_disaster_menu(game: Node) -> void:
	fixture(game)
	var director: Node = game.run_director
	game.enemy_hand.assign([{"id": "seat_drag", "name": "Disaster drag", "type": "disaster",
		"element": "fire", "cost": 0, "attack": 1, "health": 2}])
	game._set_phase(game.Phase.ENEMY)
	game.disaster_waiting = true
	director.privacy_last = "disaster"
	await frames(8)
	var seat: Node = game.disaster_seat
	var card: Node = seat.cards[0]
	seat.held = card
	seat.press_pos = Vector2.ZERO
	seat.mouse = Vector2(100, 100)
	seat._maybe_start_drag()
	expect(seat.dragging, "Disaster fixture starts drag")
	director.menu_button.pressed.emit()
	expect(director.screen == "menu" and not seat.dragging and seat.held == null,
		"Menu button cancels Disaster drag before pausing")
	expect(seat.cards.has(card) and game.enemy_hand.size() == 1, "Disaster drag returns without spending card")
	director.close_modal()

func run() -> void:
	rendered = "--render-part1" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 800)
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.presentation.automated_choice = -1
	await check_opening(game)
	await check_finish(game)
	await check_menu(game)
	await check_disaster_menu(game)
	paused = false
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: versus_batch2_hotseat_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
