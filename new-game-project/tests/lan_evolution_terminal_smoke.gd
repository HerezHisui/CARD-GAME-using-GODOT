extends SceneTree
# Regression for the LAN evolution terminal identity (flag LAN_EVOLUTION_PICKS, tested through the override).
# At game over the host rotates the match identity. The final board view carries the rotated identity, so the
# Disaster client must treat it as the finished match, not as a new match that clears the result screen.

var checks := 0
var failures := 0
var game: Node
const Session = preload("res://scripts/lan_session.gd")
const Decks = preload("res://scripts/versus_decks.gd")

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < seconds * 1000:
		await process_frame
	return predicate.call()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.run_director.persistence.enabled = false
	var versus: Node = preload("res://scripts/versus_match.gd").new()
	game.run_director.add_child(versus)
	game.run_director.versus_match = versus
	versus.setup(game.run_director)
	await check_terminal_identity()
	await check_events_and_default_off()
	game.clear_battle()
	paused = false
	game.queue_free()
	await process_frame
	print("%s: lan_evolution_terminal_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func fixture() -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.lan_evolution_picks_override = true
	game.set_seats("local", "remote")
	game.run_director.close_modal()
	game.run_director.battle_active = true
	game.run_director.privacy_screen.hide()
	game.phase = game.Phase.SETUP
	game.turn = 1
	game.enemy_evolution_deck.assign([evolution(), evolution(), evolution()])
	game.tension = 6
	game.disaster_waiting = true
	game.disaster_actions.begin_turn()

func evolution() -> Dictionary:
	return Decks.pool("disaster").evolutions.wildfire.duplicate(true)

func network_side(label: String) -> Node:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var link: Node = Session.new()
	link.name = "LanSession"
	holder.add_child(link)
	return link

func connect_pair(port: int) -> Array:
	var host := network_side("TerminalHost")
	var client := network_side("TerminalClient")
	expect(host.host_game(port) == OK, "Terminal host starts")
	expect(client.join_game("127.0.0.1", port) == OK, "Terminal client connects")
	expect(await wait_until(func(): return host.disaster_peer != 0), "Client takes the Disaster seat")
	host.game = game
	return [host, client]

func close_pair(pair: Array) -> void:
	pair[1].close()
	pair[0].close()
	pair[0].get_parent().queue_free()
	pair[1].get_parent().queue_free()
	await frames()

func check_terminal_identity() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	var pair := await connect_pair(24731)
	var host: Node = pair[0]
	var client: Node = pair[1]
	var views: Array = []
	var events: Array = []
	client.view_received.connect(func(view): views.append(view))
	client.event_received.connect(func(kind, data): events.append({"kind": kind, "data": data}))
	host.send_view()
	expect(await wait_until(func(): return client.last_view.has("match_id")), "Client gets the live match view")
	var live_id: String = str(client.last_view.get("match_id", ""))
	expect(live_id != "" and live_id == game.evolution_choice.match_id, "Live view carries the host match identity")
	# Game over rotates the host identity, then the host tells the client, then sends the final board view.
	game._set_phase(game.Phase.GAME_OVER)
	var terminal_id: String = game.evolution_choice.match_id
	expect(terminal_id != "" and terminal_id != live_id, "Game over rotates the host match identity")
	host.send_match_over("preparedness")
	expect(await wait_until(func(): return events.any(func(e): return e.kind == "match_over")),
		"Client receives match_over")
	var over: Dictionary = events.filter(func(e): return e.kind == "match_over")[0].data
	expect(str(over.get("terminal_match_id", "")) == terminal_id, "Disaster match_over carries the terminal identity")
	expect(client.completed_evolution_terminal == terminal_id, "Client records the terminal identity")
	var seen := views.size()
	host.send_view()
	host.send_event("terminal_canary", {})
	expect(await wait_until(func(): return events.any(func(e): return e.kind == "terminal_canary")),
		"Ordered channel delivers the canary after the final view")
	expect(views.size() == seen, "Final board view of the finished match is not shown as a new match")
	expect(client.last_view.is_empty(), "Client keeps the finished state after the final board view")
	# A genuinely new match has a new identity and must be accepted again.
	game.evolution_choice.reset()
	var next_id: String = game.evolution_choice.match_id
	expect(next_id != terminal_id and next_id != live_id, "A new match gets a fresh identity")
	host.send_view()
	expect(await wait_until(func(): return client.last_view.get("match_id", "") == next_id),
		"A genuinely new match view is accepted after a finished one")
	await close_pair(pair)

func check_events_and_default_off() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	var pair := await connect_pair(24732)
	var host: Node = pair[0]
	var client: Node = pair[1]
	var events: Array = []
	client.event_received.connect(func(kind, data): events.append({"kind": kind, "data": data}))
	# Preparedness never receives a private token, even with the flag on.
	host.seat_client("preparedness")
	host.send_match_over("disaster")
	expect(await wait_until(func(): return events.any(func(e): return e.kind == "match_over")),
		"Preparedness client receives match_over")
	var prep: Dictionary = events.filter(func(e): return e.kind == "match_over")[0].data
	expect(not prep.has("terminal_match_id") and prep.keys() == ["winner"],
		"Preparedness match_over carries only the winner")
	# Flag off: the Disaster event is exactly as protocol 3 sent it.
	events.clear()
	host.seat_client("disaster")
	game.lan_evolution_picks_override = false
	host.send_match_over("preparedness")
	expect(await wait_until(func(): return events.any(func(e): return e.kind == "match_over")),
		"Default-off client receives match_over")
	var off: Dictionary = events.filter(func(e): return e.kind == "match_over")[0].data
	expect(off.keys() == ["winner"], "Default-off Disaster match_over is unchanged")
	await close_pair(pair)
