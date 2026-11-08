extends SceneTree

var checks := 0
var failures := 0
var game: Node
const Actions = preload("res://scripts/lan_actions.gd")
const Session = preload("res://scripts/lan_session.gd")
const Decks = preload("res://scripts/versus_decks.gd")
const PickInput = preload("res://tests/card_pick_input.gd")

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

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
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.set_seats("local", "remote")
	# Legacy fixture: the picks flag is switched off explicitly. Flag-on defaults: lan_flag_defaults_smoke.
	game.set("lan_evolution_picks_override", false)
	expect(not game.evolution_choice.enabled(), "Flag-off LAN keeps legacy draws")
	game.set("lan_evolution_picks_override", true)
	expect(game.evolution_choice.enabled(), "Test override enables authoritative LAN evolution choices")
	if game.evolution_choice.enabled():
		await check_copies()
		await check_validation()
		await check_held()
		await check_cancelled_play()
		await check_opening()
		await check_turns()
		await check_network()
	game.clear_battle()
	paused = false
	game.queue_free()
	await process_frame
	print("%s: lan_evolution_choice_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func fixture(host_disaster: bool = false) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.lan_evolution_picks_override = true
	game.set_seats("remote" if host_disaster else "local", "local" if host_disaster else "remote")
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

func request() -> Dictionary:
	var choice: RefCounted = game.evolution_choice
	return {"kind": "evolution_pick", "match_id": choice.match_id,
		"offer_id": choice.offer_id, "id": choice.offer[0].id}

func check_copies() -> void:
	for host_disaster in [false, true]:
		for size in range(4):
			fixture(host_disaster)
			game.enemy_evolution_deck.resize(size)
			var choice: RefCounted = game.evolution_choice
			game.enemy_draw_evolutions(1)
			expect(choice.offer.size() == size, "Empty and small reserves offer all physical copies")
			expect(game.enemy_hand.is_empty(), "Offer does not enter the main hand")
			if size == 0: continue
			var ids: Array = choice.offer.map(func(entry): return entry.id)
			expect(ids.all(func(id): return ids.count(id) == 1), "Duplicate definitions have unique copy IDs")
			var unchosen: Array = choice.offer.slice(1)
			var msg := request()
			expect((await Actions.apply(game, msg)).ok, "Disaster picks during opening SETUP")
			expect(choice.held.size() == 1 and game.enemy_evolution_deck.size() == size - 1,
				"Pick removes exactly one reserve copy")
			expect(not (await Actions.apply(game, msg)).ok, "Replay cannot consume a second copy")
			game.enemy_draw_evolutions(1)
			for entry in unchosen:
				expect(choice.offer.any(func(candidate): return candidate.id == entry.id),
					"Unchosen copy ID persists across offers")
			if choice.pending(): await Actions.apply(game, request())
			game.enemy_draw_evolutions(1)
			expect(not choice.pending(), "Two held cards skip the next offer")
	fixture()
	game.disaster_is_human = false
	expect(not game.evolution_choice.enabled(), "AI remains excluded with override true")
	expect(not game.evolution_choice.lan_enabled(), "AI does not enter LAN transport mode")
	game.disaster_is_human = true
	game.encounter_kind = "battle"
	expect(not game.evolution_choice.enabled(), "Singleplayer remains excluded")
	expect(not game.evolution_choice.lan_enabled(), "Singleplayer does not enter LAN transport mode")
	game.encounter_kind = "versus"
	game.set_seats("local", "local")
	game.evolution_draw_choice_override = false
	expect(not game.evolution_choice.enabled(), "LAN override never enables local hot-seat")
	game.evolution_draw_choice_override = null

func check_validation() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	var choice: RefCounted = game.evolution_choice
	var msg := request()
	for patch in [{"match_id": "old"}, {"offer_id": -1}, {"id": "forged"}, {"id": 4},
			{"offer_id": "1"}, {"match_id": 1}, {"card": evolution()}, {"hand": 0}]:
		var bad := msg.duplicate(true)
		bad.merge(patch, true)
		expect(not (await Actions.apply(game, bad)).ok, "Forged or malformed pick refused")
		expect(choice.pending() and choice.held.is_empty() and game.enemy_evolution_deck.size() == 3,
			"Rejected pick preserves offer and reserve")
	for side in ["preparedness", "", "forged"]:
		expect(not (await Actions.apply(game, msg, side)).ok, "Only Disaster owns the pick")
	game.phase = game.Phase.ENEMY
	expect(not (await Actions.apply(game, msg)).ok, "Opening offer rejects a changed phase")
	game.phase = game.Phase.SETUP
	game.evolution_choice.held.assign([{"id": "h1", "definition": evolution()},
		{"id": "h2", "definition": evolution()}])
	expect(not (await Actions.apply(game, msg)).ok, "Full held zone rechecked at commit")
	choice.held.clear()
	game.phase = game.Phase.ENEMY
	# A fresh scheduled offer binds the current phase.
	choice.reset()
	game.enemy_draw_evolutions(1)
	game.enemy_hand.assign([Decks.pool("disaster").base.ember.duplicate(true)])
	for blocked in [{"kind": "base", "hand": 0, "lane": 0}, {"kind": "cast", "hand": 0},
			{"kind": "evolve", "hand": 0, "lane": 0, "sacrifices": []}, {"kind": "end"}]:
		expect((await Actions.apply(game, blocked)).reason == "busy", "Mandatory pick locks actions")
	msg = request()
	var old_match: String = msg.match_id
	game.clear_battle()
	expect(choice.match_id != old_match, "Clearing a match rotates wire identity")
	expect(not (await Actions.apply(game, msg)).ok, "Prior match pick refused")
	fixture()
	game.enemy_draw_evolutions(1)
	expect(not (await Actions.apply(game, msg)).ok, "Restart cannot reuse an old pick")

func unit(lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(Decks.pool("disaster").base.ember.duplicate(true))
	card.place_on_slot(game._threat_slots()[lane])
	return card

func check_held() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	await Actions.apply(game, request())
	game.phase = game.Phase.ENEMY
	var choice: RefCounted = game.evolution_choice
	var id: String = choice.held[0].id
	var msg := {"kind": "evolve", "source": "held_evolutions", "match_id": choice.match_id,
		"id": id, "lane": 0, "sacrifices": [0, 1]}
	unit(0)
	unit(1)
	for patch in [{"hand": 0}, {"source": "unknown"}, {"id": "forged"}, {"match_id": "old"},
			{"sacrifices": [0, 0]}, {"sacrifices": []}, {"lane": 2}, {"id": 5}, {"card": evolution()}]:
		var bad := msg.duplicate(true)
		bad.merge(patch, true)
		expect(not (await Actions.apply(game, bad)).ok, "Invalid held play refused")
		expect(choice.held.size() == 1 and game.tension == 6 and game.disaster_actions.actions_used == 0,
			"Refused held play consumes nothing")
	var definition: Dictionary = choice.definition(id)
	definition.locked_until = game.turn + 2
	expect((await Actions.apply(game, msg)).reason == "sealed", "Held play reuses seal rule")
	definition.erase("locked_until")
	game.disaster_actions.action_limit = 0
	expect((await Actions.apply(game, msg)).reason == "action_limit", "Held play reuses action limit")
	game.disaster_actions.begin_turn()
	game.tension = 0
	expect((await Actions.apply(game, msg)).reason == "no_tension", "Held play reuses resource rule")
	game.tension = 6
	expect(not (await Actions.apply(game, msg, "preparedness")).ok, "Preparedness cannot play held copy")
	expect((await Actions.apply(game, msg)).ok, "Valid held play uses local evolution rules")
	expect(choice.held.is_empty(), "Successful evolution consumes its held physical copy")
	expect(not (await Actions.apply(game, msg)).ok, "Held play replay refused")
	var conflicting := {"kind": "evolve", "hand": 0, "id": id, "lane": 0, "sacrifices": [0]}
	expect(not (await Actions.apply(game, conflicting)).ok, "Main-hand form rejects conflicting held ID")

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < seconds * 1000:
		await process_frame
	return predicate.call()

func apply_later(msg: Dictionary, done: Array) -> void:
	done.append(await Actions.apply(game, msg))

func check_cancelled_play() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	await Actions.apply(game, request())
	game.phase = game.Phase.ENEMY
	unit(0)
	unit(1)
	var choice: RefCounted = game.evolution_choice
	var msg := {"kind": "evolve", "source": "held_evolutions", "match_id": choice.match_id,
		"id": choice.held[0].id, "lane": 0, "sacrifices": [0, 1]}
	var done: Array = []
	apply_later(msg, done)
	fixture()
	game.enemy_draw_evolutions(1)
	var identity: String = choice.match_id
	expect(await wait_until(func(): return not done.is_empty()), "Aborted held animation returns a refusal")
	if not done.is_empty(): expect(not done[0].ok, "Aborted held play cannot succeed in a new match")
	expect(choice.match_id == identity and choice.pending() and choice.held.is_empty(),
		"Old animation leaves new match offer intact")
	expect(game._threat_slots().all(func(slot): return game._get_card_in_slot(slot) == null),
		"Old animation cannot land an evolution in a restarted match")

func resolve_choice(done: Array) -> void:
	done.append(await game.evolution_choice.resolve())

func capture(label: String) -> void:
	if "--render-lan-evolution-core" not in OS.get_cmdline_user_args(): return
	await frames(30)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../docs/notes/lanA-part1")
	DirAccess.make_dir_recursive_absolute(folder)
	expect(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"Rendered local host " + label)

## The first card tile of the picker (the tiles replaced the Choose button).
func choose_button(node: Node) -> Control:
	return PickInput.tile(node)

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

func enemy_turn(done: Array) -> void:
	await game._enemy_turn()
	done.append(true)

func check_opening() -> void:
	for host_disaster in [false, true]:
		for prep_first in [false, true]:
			fixture(host_disaster)
			game.disaster_waiting = false
			var versus: Node = game.run_director.versus_match
			versus.clear_prematch()
			versus.deck_choice = false
			versus.automated_side = "preparedness" if prep_first else "disaster"
			var host_first: bool = host_disaster != prep_first
			game.coin_pick = 0 if host_first else 1
			game.coin_result = 0
			game.deck.assign([Decks.pool("preparedness").base.fire_drill.duplicate(true)])
			game.enemy_hand.assign([Decks.pool("disaster").base.ember.duplicate(true)])
			game.enemy_draw_evolutions(1)
			game._resume_versus_coin(game.encounter_serial)
			await frames(20)
			expect(game.phase == game.Phase.SETUP and game.evolution_choice.pending(),
				"Real opening suspends after side assignment")
			expect(not game.run_director.privacy_screen.visible, "LAN opening never raises laptop cover")
			expect(game.lan_remote_prep == host_disaster, "Coin preserves both host roles")
			if host_disaster:
				var button := choose_button(game.run_director.content)
				if button != null:
					PickInput.double_click(root, button)
					await frames()
			else:
				await Actions.apply(game, request())
			expect(await wait_until(func(): return game.phase != game.Phase.SETUP), "Real opening resumes")
			expect(game.player_first == prep_first, "Both selected first-turn sides are preserved")
			expect(game.evolution_choice.held.size() == 1 and game.enemy_evolution_deck.size() == 2,
				"Real opening consumes one copy exactly once")
			if not prep_first:
				expect(await wait_until(func(): return game.disaster_waiting), "Opening Disaster turn becomes ready")
				await frames(10)
				game.disaster_actions.end_turn()
				expect(await wait_until(func(): return game.phase == game.Phase.PLAYER_DRAW),
					"First Disaster turn ends without an extra opening offer")
	game.run_director.versus_match.automated_side = ""
	game.run_director.versus_match.deck_choice = true

func check_turns() -> void:
	for host_disaster in [false, true]:
		for prep_first in [false, true]:
			fixture(host_disaster)
			game.player_first = prep_first
			game.enemy_draw_evolutions(1)
			var done: Array = []
			resolve_choice(done)
			await frames()
			expect(done.is_empty() and not game.run_director.privacy_screen.visible,
				"Opening offer suspends without a laptop cover for either LAN role or first side")
			expect(game.run_director.modal.visible == host_disaster, "Only local Disaster sees local offer")
			if host_disaster:
				await capture("local-host-offer")
				var button := choose_button(game.run_director.content)
				expect(button != null, "Local host uses the existing picker card")
				if button != null:
					PickInput.double_click(root, button)
					await frames()
			else:
				await Actions.apply(game, request())
			expect(await wait_until(func(): return not done.is_empty()), "Opening resumes after pick")
			await frames()
			expect(done == [true] and game.player_first == prep_first, "Opening continuation resolves once")
			if host_disaster: await capture("local-host-after-pick")
			game.turn = 2
			done = []
			enemy_turn(done)
			expect(await wait_until(func(): return game.evolution_choice.pending()), "Even turn opens scheduled offer")
			expect(not game.disaster_actions.end_turn().ok, "Scheduled offer blocks End Turn")
			await Actions.apply(game, request())
			await frames()
			expect(game.disaster_actions.end_turn().ok, "Scheduled pick resumes normal turn")
			expect(await wait_until(func(): return not done.is_empty()), "Turn completes after End Turn")
			expect(done == [true], "Turn continuation completes exactly once")

func network_side(label: String) -> Node:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var link: Node = Session.new()
	link.name = "LanSession"
	holder.add_child(link)
	return link

func check_network() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	var host := network_side("EvolutionHost")
	var client := network_side("EvolutionClient")
	var results: Array = []
	var rejects: Array = []
	host.action_done.connect(func(value): results.append(value))
	client.event_received.connect(func(kind, value):
		if kind == "reject": rejects.append(value))
	expect(Session.PROTOCOL == 6, "Default production protocol is 6 with the current flag defaults")
	expect(Session.build_string().begins_with("6|"), "Default build signature is protocol 6")
	expect(host.host_game(24719) == OK, "Evolution host starts")
	expect(client.join_game("127.0.0.1", 24719) == OK, "Evolution client connects")
	expect(await wait_until(func(): return host.disaster_peer != 0), "Network assigns remote seat")
	host.game = game
	var msg := request()
	host.seat_client("preparedness")
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() == 1), "Wrong network owner receives result")
	expect(not results[0].ok and not rejects.is_empty(), "Wrong owner gets existing rejection event")
	host.seat_client("disaster")
	host.lobby = true
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() == 2), "Lobby pick receives result")
	expect(results[1].reason == "lobby", "Pick cannot bypass lobby or deck setup")
	host.lobby = false
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() == 3), "Disaster network pick receives result")
	expect(results[2].ok and game.evolution_choice.held.size() == 1, "Host accepts IDs-only remote pick")
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() == 4), "Network replay receives result")
	expect(not results[3].ok, "Network replay refused")
	game.enemy_draw_evolutions(1)
	var pending_match: String = game.evolution_choice.match_id
	var done: Array = []
	resolve_choice(done)
	client.close()
	expect(await wait_until(func(): return game.evolution_choice.match_id != pending_match),
		"Disconnect invalidates match identity and pending offer")
	expect(await wait_until(func(): return not done.is_empty()), "Disconnect wakes suspended choice")
	expect(done == [false] and not game.evolution_choice.pending(), "Disconnected opening never resumes play")
	host.close()
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await frames()
