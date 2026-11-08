extends SceneTree

class Link:
	extends "res://scripts/lan_session.gd"
	var updates := 0
	var recipient := "preparedness"
	func send_view() -> void:
		updates += 1
		last_view = LanView.build(game, recipient)
		view_received.emit(last_view)

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 3) -> void:
	for i in count: await process_frame

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.clear_battle()
	game.encounter_kind = "versus"
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.deck.assign([{"id": "test_draw", "name": "Test draw", "type": "response",
		"cost": 0, "attack": 1, "health": 2, "element": "evac"}])
	game.set_seats("remote", "local")
	game._set_phase(game.Phase.PLAYER_DRAW)
	game._on_draw_button_pressed()
	expect(game.deck.size() == 1, "Disaster host cannot draw for remote Preparedness")
	game.complete_draw_choice(game.deck[0])
	expect(game.deck.size() == 1, "Direct host completion also respects ownership")
	var actions = preload("res://scripts/lan_actions.gd")
	var result: Dictionary = await actions.apply(game, {"kind": "draw"}, "disaster")
	expect(not result.ok and game.deck.size() == 1, "Remote Disaster cannot request Prep Draw")
	game._set_phase(game.Phase.ENEMY)
	result = await actions.apply(game, {"kind": "draw"}, "preparedness")
	expect(not result.ok and game.deck.size() == 1, "Remote Prep cannot draw on opponent turn")
	game._set_phase(game.Phase.PLAYER_DRAW)
	result = await actions.apply(game, {"kind": "draw"}, "preparedness")
	expect(result.ok and game.deck.is_empty(), "Remote Prep Draw advances own draw phase")
	result = await actions.apply(game, {"kind": "draw"}, "preparedness")
	expect(not result.ok, "Duplicate Draw rejected after phase advances")
	game.clear_battle()
	game.deck.assign([{"id": "test_draw", "name": "Test draw", "type": "response",
		"cost": 0, "attack": 1, "health": 2, "element": "evac"}])
	game.encounter_kind = "versus"
	game.set_seats("remote", "local")
	game._set_phase(game.Phase.PLAYER_DRAW)
	expect(game.get_node("HUD/Root/DeckDrawButton").disabled, "Wrong-owner Draw button disabled")
	game.set_seats("local", "remote")
	game._set_phase(game.Phase.ENEMY)
	game._on_draw_button_pressed()
	expect(game.deck.size() == 1, "Host cannot draw on Disaster turn")
	game._set_phase(game.Phase.PLAYER_DRAW)
	game._on_draw_button_pressed()
	expect(game.deck.is_empty() and game.get_hand_cards().size() == 1, "Owner Draw works in own draw phase")
	var link := Link.new()
	root.add_child(link)
	link.game = game
	link.is_host = true
	link.prep_peer = 2
	for seat in ["preparedness", "disaster"]:
		link.recipient = seat
		var panel: Control = (preload("res://scripts/lan_prep_panel.gd").new() if seat == "preparedness"
			else preload("res://scripts/lan_client_panel.gd").new())
		root.add_child(panel)
		var board: Node = preload("res://scripts/lan_board_3d.gd").new()
		root.add_child(board)
		board.setup(game, game.run_director, link, panel, seat)
		game._set_phase(game.Phase.PLAYER_DRAW)
		link.send_view()
		await frames()
		# The host turn plate: the player tag and the side whose turn it is. The client is Player 2.
		var expected := "P2  PREPAREDNESS" if seat == "preparedness" else "P1  PREPAREDNESS"
		expect(board.turn_label.text == expected, seat + " draw owner")
		expect(board.draw_button.disabled == (seat != "preparedness"), seat + " draw button on only for the drawer")
		var foe := "disaster" if seat == "preparedness" else "response"
		var slots: Array = game._threat_slots() if foe == "disaster" else game._response_slots()
		var unit: Node = game.Card3DScene.instantiate()
		game.add_child(unit)
		unit.setup({"id": "test_lane", "name": "Visible foe", "type": foe, "element": "fire",
			"cost": 0, "attack": 2, "health": 3})
		unit.in_hand = false
		unit.current_slot = slots[0]
		unit.position = slots[0].position
		unit.add_to_group("cards")
		await frames()
		expect(board.lane_cards[foe][0] != null, seat + " local host placement appears without phase change")
		unit.card_data.health = 1
		await frames()
		expect(board.lane_cards[foe][0].card_data.health == 1, seat + " lane damage updates immediately")
		board.mouse = game.camera.unproject_position(slots[0].global_position)
		board._update_lane_inspection()
		expect(is_instance_valid(board.lane_inspection), seat + " opponent lane inspection opens")
		expect(board.lane_cards[foe][0].preview_only, seat + " inspected opponent remains read-only")
		expect(not link.last_view.has("disaster_hand") if seat == "preparedness" else true,
			seat + " private Disaster hand remains absent")
		if "--render-batch2" in OS.get_cmdline_user_args() and seat == "preparedness":
			await frames(30)
			await RenderingServer.frame_post_draw
			var path := "C:/Users/0stef/Downloads/evolution-stage1-checks/client-turn-indicator.png"
			expect(root.get_texture().get_image().save_png(path) == OK, "Rendered client screenshot")
		unit.remove_from_group("cards")
		unit.queue_free()
		await frames()
		expect(board.lane_cards[foe][0] == null, seat + " lane removal updates without phase change")
		board.queue_free()
		panel.queue_free()
		await frames()
	link.queue_free()
	await frames()
	await check_network_draw(game)
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: lan_testers_batch2_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func make_peer(label: String) -> Node:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = preload("res://scripts/lan_session.gd").new()
	session.name = "LanSession"
	holder.add_child(session)
	return session

func wait_for(check: Callable) -> bool:
	for attempt in 500:
		if check.call(): return true
		await create_timer(0.01, true).timeout
	return check.call()

func check_network_draw(game: Node) -> void:
	var host := make_peer("Batch2Host")
	var client := make_peer("Batch2Client")
	var results: Array = []
	host.action_done.connect(func(result: Dictionary): results.append(result))
	expect(host.host_game(24703) == OK, "Loopback host listens")
	expect(client.join_game("127.0.0.1", 24703) == OK, "Loopback client connects")
	var joined: bool = await wait_for(func(): return host.disaster_peer != 0)
	expect(joined, "Loopback handshake completes")
	if joined:
		host.game = game
		host.seat_client("preparedness")
		game.set_seats("remote", "local")
		game._set_phase(game.Phase.ENEMY)
		game.deck.assign([{"id": "network_draw", "name": "Network draw", "type": "response",
			"cost": 0, "attack": 1, "health": 2, "element": "evac"}])
		client.request_action({"kind": "draw"})
		expect(await wait_for(func(): return results.size() == 1), "Wrong-turn draw returns over RPC")
		expect(results.size() == 1 and not results[0].ok and game.deck.size() == 1,
			"RPC refuses draw on opponent turn")
		game._set_phase(game.Phase.PLAYER_DRAW)
		client.request_action({"kind": "draw"})
		expect(await wait_for(func(): return results.size() == 2), "Own-turn draw returns over RPC")
		expect(results.size() == 2 and results[1].ok and game.deck.is_empty(), "RPC draws during own draw phase")
		client.request_action({"kind": "draw"})
		expect(await wait_for(func(): return results.size() == 3), "Repeated draw returns over RPC")
		expect(results.size() == 3 and not results[2].ok, "RPC refuses repeated draw in play phase")
	client.close()
	host.close()
	client.get_parent().queue_free()
	host.get_parent().queue_free()
	await frames()
