extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await frames()

func run() -> void:
	var cases: Array = OS.get_cmdline_user_args()
	if cases.is_empty():
		cases = ["hotseat_disaster", "hotseat_preparedness", "host_disaster", "host_preparedness",
			"client_disaster", "client_preparedness"]
	for mode in cases: await check_case(mode)
	print("%s: versus_return_title_smoke (%d cases, %d checks)" % [
		"FAIL" if failures else "PASS", cases.size(), checks])
	quit(1 if failures else 0)

func check_case(mode: String) -> void:
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await frames()
	print("CASE: " + mode)
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var director: Node = game.run_director
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	director.run_active = false
	director.battle_active = true
	director.close_modal()
	var disaster := mode.ends_with("disaster")
	game.set_seats("remote" if disaster and mode.begins_with("host") else "local",
		"remote" if not disaster and mode.begins_with("host") else "local")
	game._set_phase(game.Phase.ENEMY if disaster else game.Phase.PLAYER_PLAY)
	game.disaster_waiting = disaster
	game.enemy_hand.assign([{"id": "ember", "name": "Ember", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 3}])
	director.privacy_serial = game.encounter_serial
	director.privacy_last = "disaster" if disaster else "prep"
	director.privacy_screen.visible = false
	var other: Node
	var holder: Node
	if not mode.begins_with("hotseat"):
		director.ensure_lan_title()
		var lan: Node = director.lan_title
		lan._ensure_session()
		holder = Node.new()
		holder.name = "OtherPeer"
		root.add_child(holder)
		set_multiplayer(SceneMultiplayer.new(), holder.get_path())
		other = preload("res://scripts/lan_session.gd").new()
		other.name = "LanSession"
		holder.add_child(other)
		if mode.begins_with("host"):
			expect(lan.session.host_game(24704) == OK, "host listens")
			expect(other.join_game("127.0.0.1", 24704) == OK, "other joins")
		else:
			expect(other.host_game(24704) == OK, "other hosts")
			expect(lan.session.join_game("127.0.0.1", 24704) == OK, "client joins")
		for attempt in 500:
			if lan.session.multiplayer.get_peers().size() > 0: break
			await create_timer(0.01, true).timeout
		await create_timer(0.1, true).timeout
		expect(lan.session.multiplayer.get_peers().size() == 1, "peer connected before exit")
		if mode.begins_with("client"):
			lan.room = ""
			lan._show_client_panel()
			lan._on_seat("disaster" if disaster else "preparedness")
			lan.session.push_view(preload("res://scripts/lan_view.gd").build(
				game, "disaster" if disaster else "preparedness"))
	await frames(10)
	if mode.begins_with("client"):
		print("PATH: client Esc > Leave match (no Return/confirm in client menu)")
		await esc()
		expect(is_instance_valid(director.lan_title.esc_menu), "client menu opens")
		await click(director.lan_title.esc_menu.find_child("LeaveButton", true, false))
		await frames(30)
		expect(director.screen == "title", "client returns to title")
	else:
		await esc()
		expect(director.screen == "menu", "Esc menu opens")
		await click(director.content.get_node("TitleButton"))
		expect(director.screen == "confirm", "return confirmation opens")
		await click(director.content.get_node("ConfirmButton"))
		await frames(30)
		expect(not is_instance_valid(game), "old scene freed")
		expect(current_scene.run_director.screen == "title", "reloaded scene shows title")
	if is_instance_valid(other): other.close()
	if is_instance_valid(holder): holder.queue_free()
	await frames()
	print("%s: versus_return_title_smoke %s (%d checks)" % ["FAIL" if failures else "PASS", mode, checks])
