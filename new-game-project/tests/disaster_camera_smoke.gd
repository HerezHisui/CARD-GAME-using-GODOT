extends SceneTree

var checks := 0
var failures := 0
var game: Node
var rendered := false
var output := "C:/Users/0stef/Downloads/drrills-disaster-camera-checks"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func far_camera() -> bool:
	return game.camera.global_position.z < -3.0 \
		and game.get_node("CameraPivot").rotation_degrees.is_equal_approx(game.disaster_seat.SEAT_VIEW.rot)

func fixture(remote_prep: bool) -> void:
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.set_seats("remote" if remote_prep else "local", "local")
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()
	game.disaster_waiting = true
	game._set_phase(game.Phase.ENEMY)

func capture(name: String) -> void:
	if not rendered: return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, "Capture " + name)

func run() -> void:
	rendered = "--render-camera" in OS.get_cmdline_user_args()
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.presentation.automated_choice = 0
	fixture(true)
	await frames()
	expect(far_camera(), "LAN host Disaster starts on its own side")
	# _enemy_turn clears this wait before combat; the seat must not give the LAN camera away.
	game.disaster_waiting = false
	await frames()
	expect(far_camera(), "LAN host keeps Disaster camera when its input wait ends")
	if not far_camera():
		quit(1)
		return
	await check_lan_host()
	await check_hotseat()
	await check_client()
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: disaster_camera_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func add_card(title: String, slot: Node3D, response: bool = false) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"name": title, "type": "response" if response else "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 3})
	card.place_on_slot(slot)
	return card

func press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func check_lan_host() -> void:
	var ally := add_card("Disaster Ally", game._threat_slots()[0])
	var foe := add_card("Preparedness Ally", game._response_slots()[1], true)
	await create_timer(0.7, true).timeout
	game._set_phase(game.Phase.COMBAT)
	await frames()
	expect(far_camera(), "LAN host keeps its camera through combat")
	game._set_phase(game.Phase.PLAYER_PLAY)
	await frames()
	expect(far_camera(), "LAN host keeps its camera during remote Preparedness turn")
	expect(not game.opponent_hand.visible, "Local Janitor does not obstruct the far-side camera")
	expect(absf(absf(ally.rotation.y) - PI) < 0.05 and absf(absf(foe.rotation.y) - PI) < 0.05,
		"Both landed rows remain upright for the LAN Disaster owner")
	var own_point: Vector2 = game.camera.unproject_position(game._threat_slots()[0].global_position)
	var foe_point: Vector2 = game.camera.unproject_position(game._response_slots()[0].global_position)
	expect(own_point.y > foe_point.y, "LAN host own row remains below opponent row")
	game._apply_view(game.DESK_VIEW)
	expect(far_camera(), "Direct Preparedness view request cannot steal the LAN camera")
	game._shift_camera(game.DESK_VIEW, 0.05)
	await create_timer(0.15, true).timeout
	expect(far_camera(), "Preparedness camera tween cannot steal the LAN camera")
	var mode: int = game.view_mode
	await press_key(KEY_W)
	await press_key(KEY_S)
	expect(far_camera() and game.view_mode == mode, "W/S do not change the LAN Disaster view")
	expect(game._view_forward_btn.disabled and game._view_back_btn.disabled, "LAN Disaster view buttons stay disabled")
	game.run_director.show_menu()
	await frames()
	expect(far_camera(), "Esc menu keeps the owner camera")
	game.run_director.close_modal()
	await frames()
	await capture("lan-host-after-turn")
	game.disaster_waiting = true
	game._set_phase(game.Phase.ENEMY)
	await frames()
	expect(far_camera() and game.disaster_seat.active, "Next Disaster turn keeps the same camera")
	game.disaster_actions.begin_turn()
	game.tension = 3
	await capture("lan-host-disaster-turn")

func check_hotseat() -> void:
	fixture(false)
	await frames()
	expect(far_camera(), "Hot-seat Disaster still uses far seat while waiting")
	game._apply_view(game.DESK_VIEW)
	expect(far_camera(), "Direct reset cannot steal the active hot-seat camera")
	game._shift_camera(game.DESK_VIEW, 0.05)
	await create_timer(0.15, true).timeout
	expect(far_camera(), "Tween request cannot steal the active hot-seat camera")
	game.disaster_waiting = false
	game._set_phase(game.Phase.PLAYER_PLAY)
	await frames()
	expect(not game.disaster_seat.active and game.camera.global_position.z > 3.0,
		"Hot-seat still hands camera back to Preparedness")
	game.encounter_kind = "battle"
	game.set_seats("remote", "local")
	await frames()
	game.set_view(game.View.BOARD)
	await create_timer(0.7, true).timeout
	expect(game.get_node("CameraPivot").rotation_degrees.is_equal_approx(game.BOARD_VIEW.rot),
		"Singleplayer retains its normal view controls")
	game.set_view(game.View.DESK)
	await create_timer(0.7, true).timeout
	expect(game.camera.global_position.z > 3.0, "Singleplayer returns to Preparedness desk view")
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.set_seats("local", "remote")
	await frames()
	game._apply_view(game.DESK_VIEW)
	expect(game.camera.global_position.z > 3.0, "Preparedness host keeps its existing camera")

func check_client() -> void:
	game.disaster_waiting = false
	game.set_seats("local", "local")
	game.run_director.battle_active = false
	await frames()
	var session: Node = load("res://scripts/lan_session.gd").new()
	root.add_child(session)
	var panel: Control = load("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	var board: Node = load("res://scripts/lan_board_3d.gd").new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "disaster")
	for own_turn in [true, false, true]:
		session.view_received.emit({"round": 2, "phase": "play", "turn_side": "disaster" if own_turn else "preparedness",
			"is_disaster_turn": own_turn,
			"sides": {"response": {"hp": 20, "max_hp": 20, "resource": 3, "resource_cap": 3},
				"disaster": {"hp": 20, "max_hp": 20, "resource": 3, "resource_cap": 3}},
			"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
			"cards": {}, "hints": [], "disaster_hand": [], "counts": {}})
		await frames()
		expect(far_camera(), "LAN Disaster client retains camera across view updates")
	board.queue_free()
	panel.queue_free()
	session.queue_free()
	await frames()

