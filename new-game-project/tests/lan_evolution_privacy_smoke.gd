extends SceneTree

const View = preload("res://scripts/lan_view.gd")
const Session = preload("res://scripts/lan_session.gd")
const Actions = preload("res://scripts/lan_actions.gd")
const PRIVATE_KEYS := ["evolution_offer", "held_evolutions", "match_id", "offer_id", "candidates",
	"reserve_copies", "reserve_order", "index", "reserve_index", "next_id", "rng", "run_rng_state"]
var game: Node
var checks := 0
var failures := 0
var secrets: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	var versus: Node = preload("res://scripts/versus_match.gd").new()
	game.run_director.add_child(versus)
	game.run_director.versus_match = versus
	versus.setup(game.run_director)
	check_default_gates()
	fixture()
	game.enemy_draw_evolutions(1)
	remember_secrets()
	var owner: Dictionary = View.build(game)
	expect(owner.has("evolution_offer"), "Disaster receives its private evolution offer")
	expect(owner.has("held_evolutions"), "Disaster receives its private held browser data")
	expect(View.build(game, "preparedness").has("evolution_waiting"), "Preparedness receives public waiting state")
	if owner.has("evolution_offer") and owner.has("held_evolutions"):
		await check_phases()
		await check_hints_and_copies()
		await check_wire()
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: lan_evolution_privacy_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func fixture(host_disaster: bool = false) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.lan_evolution_picks_override = true
	game.set_seats("remote" if host_disaster else "local", "local" if host_disaster else "remote")
	game.phase = game.Phase.SETUP
	game.turn = 1
	game.disaster_waiting = true
	game.tension = 6
	game.disaster_actions.begin_turn()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.run_director.privacy_screen.hide()
	game.run_director.rng.state = 1739123456789012345
	secrets.assign([str(game.run_director.rng.state), "PRIVATE_DISASTER_MAIN", "PRIVATE_PREP_RESERVE"])
	for i in 5:
		var definition := {"id": "PRIVATE_EVOLUTION_ID_%d" % i, "name": "PRIVATE_EVOLUTION_NAME_%d" % i,
			"type": "disaster", "element": "fire", "cost": 1, "attack": 2, "health": 3,
			"private_hint_marker": "PRIVATE_EVOLUTION_HINT_%d" % i}
		game.enemy_evolution_deck.append(definition)
		secrets.append(definition.id)
		secrets.append(definition.name)
		secrets.append(definition.private_hint_marker)
	game.enemy_hand.assign([{"id": "PRIVATE_DISASTER_MAIN", "name": "PRIVATE_DISASTER_MAIN",
		"type": "disaster", "element": "fire", "cost": 0, "attack": 1, "health": 2}])
	game.deck.assign([{"id": "PRIVATE_PREP_RESERVE", "name": "PRIVATE_PREP_RESERVE", "cost": 1}])
	game.add_card_to_hand({"id": "PUBLIC_PREP_HAND", "name": "PUBLIC_PREP_HAND", "type": "response",
		"element": "brace", "cost": 1, "attack": 1, "health": 3})
	unit(0)
	unit(1)

func unit(lane: int) -> void:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": "PUBLIC_THREAT_%d" % lane, "name": "PUBLIC_THREAT_%d" % lane,
		"type": "disaster", "element": "fire", "cost": 0, "attack": 1, "health": 3})
	card.place_on_slot(game._threat_slots()[lane])

func remember_secrets() -> void:
	var choice: RefCounted = game.evolution_choice
	for entry in choice.reserve_copies + choice.held:
		if entry.id not in secrets: secrets.append(entry.id)
	if not choice.match_id.is_empty() and choice.match_id not in secrets: secrets.append(choice.match_id)

func has_private_key(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key in PRIVATE_KEYS or has_private_key(value[key]): return true
	elif value is Array:
		for entry in value:
			if has_private_key(entry): return true
	return false

func assert_private_free(value: Variant, label: String, keys: bool = true) -> void:
	var serialized := JSON.stringify(value)
	expect(secrets.all(func(secret): return serialized.find(secret) < 0), label + " has no private values")
	if keys: expect(not has_private_key(value), label + " has no private zones, indices, tokens or RNG keys")

func audit_prep(view: Dictionary) -> void:
	assert_private_free(view, "Preparedness view")
	expect(view.get("evolution_waiting") == game.evolution_choice.pending(), "Waiting state matches host")
	expect(view.counts.get("disaster_held_evolutions", -1) == game.evolution_choice.held.size(),
		"Preparedness receives held count only")
	expect(view.counts.disaster_evolution == game.enemy_evolution_deck.size(), "Reserve count matches host")
	expect(view.cards.size() == game.get_hand_cards().size() + 2, "Only recipient hand and public lanes enter cards")
	assert_private_free(game.battle_log, "Public battle log", false)

func audit_owner(view: Dictionary) -> void:
	var choice: RefCounted = game.evolution_choice
	expect(view.get("match_id") == choice.match_id, "Disaster receives current match identity for held plays")
	expect(view.evolution_waiting == choice.pending(), "Disaster receives mandatory waiting state")
	expect(view.held_evolutions.size() == choice.held.size(), "Disaster receives every held physical copy")
	if choice.pending():
		var offer: Dictionary = view.evolution_offer
		expect(offer.size() == 3 and offer.match_id == choice.match_id and offer.offer_id == choice.offer_id,
			"Offer carries only match, offer and candidate fields")
		expect(offer.candidates.size() == choice.offer.size(), "Disaster receives all offered candidates")
		for i in offer.candidates.size():
			var candidate: Dictionary = offer.candidates[i]
			expect(candidate.size() == 2 and candidate.id == choice.offer[i].id
				and candidate.card == choice.offer[i].definition, "Candidate carries opaque physical ID and card only")
	else:
		expect(view.evolution_offer.is_empty(), "Resolved or absent offer is empty")
	for i in view.held_evolutions.size():
		var held: Dictionary = view.held_evolutions[i]
		expect(held.size() == 3 and held.id == choice.held[i].id and held.card == choice.held[i].definition,
			"Held entry carries physical ID, card and legal hints only")
		expect(not held.hints.has("index") and not held.hints.has("rng"), "Held hints omit reserve indices and RNG")
	var serialized := JSON.stringify(view)
	expect(serialized.find("PRIVATE_PREP_RESERVE") < 0 and serialized.find("PUBLIC_PREP_HAND") < 0,
		"Disaster cannot see Preparedness hidden zones")
	expect(not view.has("zones") and not view.has("battle_log") and not view.has("run_rng_state"),
		"Host sends a recipient whitelist, never a full snapshot")
	expect(not view.evolution_offer.has("index") and not view.evolution_offer.has("reserve_copies"),
		"Owner offer omits host reserve addresses")

func pick_request() -> Dictionary:
	var choice: RefCounted = game.evolution_choice
	return {"kind": "evolution_pick", "match_id": choice.match_id,
		"offer_id": choice.offer_id, "id": choice.offer[0].id}

func check_default_gates() -> void:
	fixture()
	game.lan_evolution_picks_override = null
	expect(game.get("lan_evolution_picks_override") == null and Session.PROTOCOL == 3,
		"Null override and production protocol stay unchanged")
	for side in ["disaster", "preparedness"]:
		var view: Dictionary = View.build(game, side)
		expect(not view.has("evolution_offer") and not view.has("held_evolutions")
			and not view.has("evolution_waiting") and not view.has("match_id"), "Default-off view schema unchanged")
	game.lan_evolution_picks_override = true
	for kind in ["battle", "ai", "hotseat"]:
		game.encounter_kind = "battle" if kind == "battle" else "versus"
		game.disaster_is_human = kind != "ai"
		game.set_seats("local", "local" if kind == "hotseat" else "remote")
		expect(not View.build(game).has("evolution_offer"), "Singleplayer, AI and local hot-seat views unchanged")

func check_phases() -> void:
	for host_disaster in [false, true]:
		for prep_first in [false, true]:
			fixture(host_disaster)
			game.player_first = prep_first
			game.enemy_draw_evolutions(1)
			remember_secrets()
			for phase in [game.Phase.SETUP, game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY,
					game.Phase.ENEMY, game.Phase.COMBAT]:
				game.phase = phase
				audit_prep(View.build(game, "preparedness"))
				audit_owner(View.build(game))
			game.phase = game.Phase.SETUP
			expect((await Actions.apply(game, pick_request())).ok, "Opening pick accepted")
			for phase in [game.Phase.SETUP, game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY,
					game.Phase.ENEMY, game.Phase.COMBAT]:
				game.phase = phase
				audit_prep(View.build(game, "preparedness"))
				audit_owner(View.build(game))
			game.phase = game.Phase.ENEMY
			game.enemy_draw_evolutions(1)
			audit_prep(View.build(game, "preparedness"))
			expect((await Actions.apply(game, pick_request())).ok, "Scheduled pick accepted")
			game.enemy_draw_evolutions(1)
			expect(not game.evolution_choice.pending(), "Two-held skip has no mandatory waiting state")
			audit_prep(View.build(game, "preparedness"))
			audit_owner(View.build(game))
			game._set_phase(game.Phase.GAME_OVER)
			audit_prep(View.build(game, "preparedness"))
			audit_owner(View.build(game))
			expect(game.evolution_choice.held.is_empty(), "Game over clears private zones before next view")

func check_hints_and_copies() -> void:
	fixture()
	game.enemy_draw_evolutions(1)
	remember_secrets()
	var rng_before: int = game.run_director.rng.state
	var owner: Dictionary = View.build(game)
	owner.evolution_offer.candidates[0].card.name = "CLIENT_MUTATION"
	expect(game.evolution_choice.offer[0].definition.name != "CLIENT_MUTATION", "Offer payload is detached")
	await Actions.apply(game, pick_request())
	game.phase = game.Phase.ENEMY
	owner = View.build(game)
	var held: Dictionary = owner.held_evolutions[0]
	expect(held.hints.can_use and held.hints.problem.is_empty(), "Legal held card can be played")
	expect(held.hints.sacrifices == [0, 1] and held.hints.lanes == [0, 1], "Hints reuse legal sacrifice lanes")
	held.card.cost = 99
	held.hints.sacrifices.clear()
	expect(game.evolution_choice.held[0].definition.cost == 1, "Client cannot mutate held source")
	var definition: Dictionary = game.evolution_choice.held[0].definition
	definition.locked_until = game.turn + 2
	owner = View.build(game)
	expect(owner.held_evolutions[0].hints.problem == "sealed"
		and not owner.held_evolutions[0].hints.can_use, "Held hints obey seal rule")
	audit_prep(View.build(game, "preparedness"))
	definition.erase("locked_until")
	game.increase_cost(definition)
	owner = View.build(game)
	expect(owner.held_evolutions[0].card.cost == 2, "Held view reflects current cost")
	game.tension = 0
	expect(View.build(game).held_evolutions[0].hints.problem == "no_tension", "Held hints obey tension rule")
	game.tension = 6
	game.disaster_actions.action_limit = 0
	expect(View.build(game).held_evolutions[0].hints.problem == "action_limit", "Held hints obey action limit")
	game.disaster_actions.begin_turn()
	game.enemy_draw_evolutions(1)
	expect(View.build(game).held_evolutions[0].hints.problem == "busy", "Offer locks held-play hints")
	expect(game.run_director.rng.state == rng_before, "Building views never advances run RNG")
	audit_prep(View.build(game, "preparedness"))

func network_side(label: String) -> Node:
	var holder := Node.new()
	holder.name = label
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var link: Node = Session.new()
	link.name = "LanSession"
	holder.add_child(link)
	return link

func wait_until(predicate: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < 8000:
		await process_frame
	return predicate.call()

func check_wire() -> void:
	fixture(true)
	game.enemy_draw_evolutions(1)
	remember_secrets()
	var host := network_side("EvolutionPrivacyHost")
	var client := network_side("EvolutionPrivacyClient")
	var views: Array = []
	var events: Array = []
	var results: Array = []
	client.view_received.connect(func(value): views.append(value))
	client.event_received.connect(func(kind, value): events.append({"kind": kind, "data": value}))
	host.action_done.connect(func(value): results.append(value))
	expect(host.host_game(24720) == OK, "Privacy host starts")
	expect(client.join_game("127.0.0.1", 24720) == OK, "Privacy client connects")
	if not await wait_until(func(): return host.disaster_peer != 0):
		expect(false, "Privacy client receives a network seat")
		host.close()
		client.close()
		host.get_parent().queue_free()
		client.get_parent().queue_free()
		return
	host.game = game
	host.seat_client("preparedness")
	for phase in game.Phase.values():
		game.phase = phase
		var count := views.size()
		host.send_view()
		expect(await wait_until(func(): return views.size() > count), "Preparedness view crosses real ENet")
		if views.size() > count: audit_prep(views[-1])
	game.phase = game.Phase.SETUP
	client.request_action(pick_request())
	expect(await wait_until(func(): return not results.is_empty() and not events.is_empty()),
		"Wrong-seat pick produces a rejection event")
	assert_private_free(views, "All Preparedness wire views")
	assert_private_free(events, "Preparedness rejection events")
	game.set_seats("local", "remote")
	host.seat_client("disaster")
	var count := views.size()
	host.send_view()
	expect(await wait_until(func(): return (views.size() > count
		and client.last_view.has("evolution_offer"))), "Disaster private view crosses real ENet")
	if client.last_view.has("evolution_offer"): audit_owner(client.last_view)
	client.request_action(pick_request())
	expect(await wait_until(func(): return (game.evolution_choice.held.size() == 1
		and not client.last_view.get("held_evolutions", []).is_empty())), "Accepted pick refreshes held owner view")
	game.set_seats("remote", "local")
	host.seat_client("preparedness")
	count = views.size()
	host.send_view()
	expect(await wait_until(func(): return (views.size() > count
		and client.last_view.get("side") == "preparedness")), "Seat change sends freshly redacted view")
	if client.last_view.get("side") == "preparedness": audit_prep(client.last_view)
	game.phase = game.Phase.ENEMY
	game.enemy_draw_evolutions(1)
	count = views.size()
	expect(await wait_until(func(): return views.size() > count), "Opening another offer refreshes public waiting")
	if views.size() > count: audit_prep(views[-1])
	var identity: String = game.evolution_choice.match_id
	client.close()
	expect(await wait_until(func(): return game.evolution_choice.match_id != identity),
		"Disconnect invalidates private zones")
	audit_prep(View.build(game, "preparedness"))
	fixture()
	game.enemy_draw_evolutions(1)
	remember_secrets()
	audit_prep(View.build(game, "preparedness"))
	expect(game.evolution_choice.match_id != identity, "Restart uses a different match identity")
	host.close()
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await frames()
