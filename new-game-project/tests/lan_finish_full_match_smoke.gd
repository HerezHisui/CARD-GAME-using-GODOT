extends SceneTree
## LAN finish part 3: two whole LAN matches over a real ENet loopback link, both flags on through the overrides.
## Match 1: the host is the Disaster, the client is Preparedness. Opening evolution pick (real click on the host),
##   a unit, Rally (lane pick), Tutor (list pick), Scout, Tax with the named hand, then game over.
## Match 2: the host is Preparedness, the client is the Disaster. Opening evolution pick over the wire, the Disaster
##   graveyard list, a privacy audit of every Disaster view against the host's Preparedness secrets, then game over
##   and the terminal identity guard.
## Both matches run in one app run, so a leftover turn of match 1 would break match 2.

const LanSession = preload("res://scripts/lan_session.gd")
const Decks = preload("res://scripts/versus_decks.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24771
const MAX_FRAMES := 3000
const SAVE_PATH := "user://test_lan_finish_full_match.cfg"
# Texts only a host Preparedness card can hold. They must never reach the Disaster client.
const SECRET_UNIT := "ZzSecretUnit"
const SECRET_SPELL := "ZzSecretSpell"
const SECRET_DECK := "ZzSecretDeck"

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title; lan.session is the host session
var other: Node  # the plain LanSession client of the running match
var other_joined := false
var other_events: Array = []
var views: Array = []
var host_results: Array = []
var hooked_session: Node
var holders: Array = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	Decks.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	await process_frame
	director.show_title()
	director.add_lan_buttons(director.content.get_child(0))
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_lan_finish_full_match_lan.cfg"
	game.lan_evolution_picks_override = true
	game.lan_prep_utilities_override = true
	await match_one()
	await match_two()
	lan.session.close()
	game.lan_evolution_picks_override = null
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await frames(5)
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_finish_full_match_smoke (%d checks)" % checks)
	quit(0)


# ------------------------------------------------------------------- helpers

func unit(id: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": id, "type": "response", "element": "evac", "cost": cost, "attack": 1, "health": 10}


func spell(id: String, effect: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": id, "type": "response", "element": "evac", "cost": cost,
		"utility": true, "effect": effect}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 4, "tension_cost": 1}


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other%d" % holders.size()
	root.add_child(holder)
	holders.append(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other_joined = false
	other_events.clear()
	views.clear()
	other.joined_host.connect(func() -> void: other_joined = true)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.view_received.connect(func(view: Dictionary) -> void: views.append(view))


# Host, join, Start match, call the coin, pick the side, then wait for the deck step. Returns the versus node.
func start_match(name: String, host_side: String) -> Node:
	var client_side := "disaster" if host_side == "preparedness" else "preparedness"
	make_other()
	Decks.save_custom(host_side, custom_deck(host_side))
	director.show_title()
	lan.show_host()
	hook_host_results()
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, name + ": the client starts joining")
	expect(await wait_until(func() -> bool: return other_joined and lan.room_connected()), name + ": joined")
	lan.start_match()
	var versus: Node = director.versus_match
	versus.deck_choice = true
	versus.automated_deck = "custom"
	expect(await wait_until(coin_screen_ready), name + ": the coin screen shows")
	await frames(3)
	await click(game.presentation.choice_buttons[0])
	expect(await wait_until(func() -> bool: return versus.prematch_active), name + ": the side pick starts")
	versus.choose_side(host_side if versus.coin_winner == 1 else client_side)
	if not await wait_until(func() -> bool: return has_kind("deck_step")):
		expect(false, name + ": the client hears the deck step")
		return null
	other.request_deck(custom_deck(client_side))
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the seat comes after the deck")
	expect(await wait_until(func() -> bool: return game.evolution_choice.pending()),
		name + ": the opening offer is open")
	expect(game.phase == game.Phase.SETUP, name + ": the match starts in SETUP")
	return versus


func pick_on_host(name: String) -> void:
	var button: Button = null
	for i in 600:
		button = find_choose_button()
		if button != null: break
		await process_frame
	expect(button != null, name + ": the host offer screen shows a Choose button")
	if button == null: return
	await frames(3)
	await click(button)
	expect(await wait_until(func() -> bool: return game.evolution_choice.held.size() == 1),
		name + ": the host click takes the pick")


func pick_over_the_wire(name: String) -> void:
	expect(await wait_until(func() -> bool: return not last_offer().is_empty()), name + ": the client has an offer")
	var offer: Dictionary = last_offer()
	if offer.is_empty(): return
	other.request_action({"kind": "evolution_pick", "match_id": offer.match_id, "offer_id": offer.offer_id,
		"id": offer.candidates[0].id})
	expect(await wait_until(func() -> bool: return game.evolution_choice.held.size() == 1),
		name + ": the host takes the client's pick")


func last_offer() -> Dictionary:
	var offer: Dictionary = {}
	for view: Dictionary in views:
		if not view.get("evolution_offer", {}).is_empty(): offer = view.evolution_offer
	return offer


func find_choose_button() -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == "Choose" and node.is_visible_in_tree(): return node
	return null


# One client message, answered by the host. Waits for the host's result.
func send(msg: Dictionary) -> Dictionary:
	var before := host_results.size()
	other.request_action(msg)
	if not await wait_until(func() -> bool: return host_results.size() > before):
		return {"ok": false, "reason": "timeout"}
	return host_results[before]


# The host session is made by show_host. Listen to its action results once per session object.
func hook_host_results() -> void:
	if lan.session == null or lan.session == hooked_session: return
	hooked_session = lan.session
	hooked_session.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))


func hand_index(id: String) -> int:
	var cards: Array = game.get_hand_cards()
	for i in cards.size():
		if str(cards[i].card_data.get("id", "")) == id: return i
	return -1


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return str(card.card_data.get("id", "")))


# The open choice on the client side, from the newest view.
func open_choice() -> Dictionary:
	return other.last_view.get("pending_choice", {})


func pick_msg(handle: int) -> Dictionary:
	var open: Dictionary = open_choice()
	return {"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": open.stage, "handle": handle}


# Moves a match with a human Disaster host to the Preparedness play phase. The host ends its own turn.
func to_prep_turn(name: String) -> void:
	var reached: bool = false
	for i in 1500:
		if game.phase == game.Phase.PLAYER_PLAY and game.board_input.action.is_empty():
			reached = true
			break
		if game.phase == game.Phase.PLAYER_DRAW:
			other.request_action({"kind": "draw"})
		elif game.phase == game.Phase.ENEMY and game.disaster_waiting and not game.evolution_choice.pending():
			game.disaster_actions.end_turn()
		await frames(3)
	expect(reached, name + ": the Preparedness play phase comes (phase %d)" % game.phase)


# The client got a view whose phase says it is its turn, newer than the host's change.
func client_sees_prep_turn() -> bool:
	return bool(other.last_view.get("is_prep_turn", false))


# ------------------------------------------------------------------- match 1: host Disaster, client Preparedness

func match_one() -> void:
	var name := "match 1 (host Disaster)"
	var versus: Node = await start_match(name, "disaster")
	if versus == null: return
	await pick_on_host(name)
	await to_prep_turn(name)
	if game.phase != game.Phase.PLAYER_PLAY:
		await end_match(name)
		return
	expect(await wait_until(client_sees_prep_turn), name + ": the client view says it is its turn")
	# Cards for the script go straight into the hand, as the other suites do.
	game.preparedness = 9
	game.add_card_to_hand(unit("ff_unit"))
	game.add_card_to_hand(spell("ff_rally", "rally"))
	game.add_card_to_hand(spell("ff_tutor", "tutor"))
	game.add_card_to_hand(spell("ff_scout", "scout"))
	game.add_card_to_hand(spell("ff_tax", "tax"))
	game.enemy_hand.assign([threat("ff_h1"), threat("ff_h2")])
	# Until Scout, the Disaster hand stays hidden from the client.
	await refresh_client()
	var before_text := JSON.stringify(views)
	expect(not before_text.contains("ff_h1") and not before_text.contains("ff_h2"),
		name + ": no Disaster card before Scout")
	# A unit into lane 0.
	var result: Dictionary = await send({"kind": "play", "hand": hand_index("ff_unit"), "lane": 0})
	expect(result.ok, name + ": the unit is played over the wire")
	var ally: Node = game._get_card_in_slot(game._response_slots()[0])
	expect(ally != null and ally.card_data.get("id", "") == "ff_unit", name + ": the unit stands in lane 0")
	# Rally: a lane pick.
	result = await send({"kind": "utility", "hand": hand_index("ff_rally"), "target": -1})
	expect(result.ok, name + ": Rally opens a choice")
	expect(await wait_until(func() -> bool: return open_choice().get("stage", "") == "ally"),
		name + ": the client sees the ally stage")
	result = await send(pick_msg(0))
	expect(result.ok and int(ally.statuses.get("strength", 0)) == 2, name + ": Rally gave +2 strength")
	# Tutor: a list pick from the own deck.
	var deck_before: int = game.deck.size()
	result = await send({"kind": "utility", "hand": hand_index("ff_tutor"), "target": -1})
	expect(result.ok, name + ": Tutor opens a choice")
	expect(await wait_until(func() -> bool: return open_choice().get("stage", "") == "deck"),
		name + ": the deck list is open")
	var candidates: Array = open_choice().get("candidates", [])
	expect(not candidates.is_empty() and candidates[0].has("card"), name + ": the deck list names its cards")
	var wanted: String = str(candidates[0].card.get("id", ""))
	result = await send(pick_msg(0))
	expect(result.ok and game.deck.size() == deck_before - 1 and wanted in hand_ids(),
		name + ": the tutored card is in the hand")
	# Scout, then Tax names the hand.
	result = await send({"kind": "utility", "hand": hand_index("ff_scout"), "target": -1})
	expect(result.ok and game.run_director.intel_revealed, name + ": Scout reveals")
	expect(not director.modal.visible, name + ": Scout opens no modal on the host")
	expect(await wait_until(func() -> bool: return other.last_view.has("disaster_hand_revealed")),
		name + ": the client view carries the Disaster hand")
	var revealed: Array = other.last_view.disaster_hand_revealed
	expect(revealed.size() == 2 and revealed[0].id == "ff_h1", name + ": the copy is the hand at the cast")
	result = await send({"kind": "utility", "hand": hand_index("ff_tax"), "target": -1})
	expect(result.ok, name + ": Tax opens a choice")
	expect(await wait_until(func() -> bool: return open_choice().get("stage", "") == "hand"),
		name + ": the hand list is open")
	candidates = open_choice().get("candidates", [])
	expect(candidates.size() == 2 and candidates[0].has("card") and candidates[0].card.id == "ff_h1",
		name + ": Tax names the hand while Scout lasts")
	result = await send(pick_msg(1))
	expect(result.ok and int(game.enemy_hand[1].tension_cost) == 2 and int(game.enemy_hand[0].tension_cost) == 1,
		name + ": only the named card was taxed")
	expect(await wait_until(func() -> bool: return open_choice().is_empty()), name + ": the choice closed")
	# Game over: the Disaster loses. The client hears it.
	game.enemy_hp = 0
	game._check_game_over()
	expect(game.phase == game.Phase.GAME_OVER, name + ": the match is over")
	expect(await wait_until(func() -> bool: return has_kind("match_over")), name + ": the client hears match_over")
	await end_match(name)


# ------------------------------------------------------------------- match 2: host Preparedness, client Disaster

func match_two() -> void:
	var name := "match 2 (host Preparedness)"
	var serial: int = game.encounter_serial
	var versus: Node = await start_match(name, "preparedness")
	if versus == null: return
	expect(game.encounter_serial > serial, name + ": a new encounter")
	await pick_over_the_wire(name)
	expect(await wait_until(func() -> bool: return game.phase != game.Phase.SETUP), name + ": the match goes on")
	var live_id: String = game.evolution_choice.match_id
	# Preparedness secrets on the host: a hand unit, a hand Scout, a deck card and a graveyard unit.
	game.add_card_to_hand(unit(SECRET_UNIT))
	game.add_card_to_hand(spell(SECRET_SPELL, "scout"))
	game.deck.append(unit(SECRET_DECK))
	game.record_graveyard(game.get_hand_cards()[0], "Cast")
	# The Disaster graveyard, public to the Disaster client as a list.
	game.disaster_graveyard.clear()
	game.record_disaster_definition(threat("gg_a"), "Destroyed")
	game.record_disaster_definition(threat("gg_b"), "Cast")
	# The host casts Scout on its own seat. Its modal and flag never go into a Disaster view.
	game.apply_simple_utility(game.get_hand_cards()[hand_index(SECRET_SPELL)], "scout")
	expect(director.intel_revealed and director.modal.visible, name + ": the local Scout opens the host modal")
	director.close_modal()
	views.clear()
	await refresh_client()
	expect(await wait_until(func() -> bool: return other.last_view.has("disaster_graveyard_list")),
		name + ": the Disaster client gets the graveyard list")
	var list: Array = other.last_view.disaster_graveyard_list
	expect(list.size() == 2 and list[0].id == "gg_a" and str(list[1].graveyard_reason) == "Cast",
		name + ": the list is in order with reasons")
	var text := JSON.stringify(views)
	for secret in [SECRET_UNIT, SECRET_SPELL, SECRET_DECK, "disaster_hand_revealed", "pending_choice", "intel"]:
		expect(not text.contains(secret), name + ": no Disaster view holds " + secret)
	text = JSON.stringify(other_events)
	for secret in [SECRET_UNIT, SECRET_SPELL, SECRET_DECK]:
		expect(not text.contains(secret), name + ": no event holds " + secret)
	# Game over: the host Preparedness loses. The terminal identity reaches the Disaster client.
	game.player_hp = 0
	game._check_game_over()
	expect(game.phase == game.Phase.GAME_OVER, name + ": the match is over")
	var terminal_id: String = game.evolution_choice.match_id
	expect(terminal_id != "" and terminal_id != live_id, name + ": game over rotates the match identity")
	expect(await wait_until(func() -> bool: return has_kind("match_over")), name + ": the client hears match_over")
	var over: Dictionary = {}
	for event in other_events:
		if event[0] == "match_over": over = event[1]
	expect(str(over.get("terminal_match_id", "")) == terminal_id,
		name + ": match_over carries the terminal identity")
	expect(other.completed_evolution_terminal == terminal_id, name + ": the client records the terminal identity")
	var seen := views.size()
	lan.session.send_view()
	lan.session.send_event("terminal_canary", {})
	expect(await wait_until(func() -> bool: return has_kind("terminal_canary")), name + ": the canary arrives")
	expect(views.size() == seen, name + ": the final board view is not shown as a new match")
	await end_match(name)


# Ask the host for a fresh view and wait until the client has one.
func refresh_client() -> void:
	var count := views.size()
	lan.session.send_view()
	await wait_until(func() -> bool: return views.size() > count)


func end_match(name: String) -> void:
	director.versus_match.automated_deck = ""
	other.close()
	expect(await wait_until(func() -> bool: return not director.versus_match.running), name + ": the match ended")
	lan.session.close()
	await frames(5)


func custom_deck(side: String) -> Dictionary:
	var deck: Dictionary = Decks.preset(side).duplicate(true)
	var pool: Dictionary = Decks.pool(side)
	var main_pool: Dictionary = pool.base.duplicate()
	if side == Decks.SIDE_DISASTER: main_pool.merge(pool.spells)
	deck.main = swap_one(deck.main, main_pool)
	if side == Decks.SIDE_DISASTER: deck.evolutions = swap_one(deck.evolutions, pool.evolutions)
	else: deck.tactics = ["brace", "supply", "flank"]
	return deck


func swap_one(pile: Array, allowed: Dictionary) -> Array:
	var out: Array = pile.duplicate()
	for id: String in allowed:
		if out.count(id) == 0:
			out[0] = id
			return out
	return out


func coin_screen_ready() -> bool:
	return director.screen == "coin" and game.presentation.blocking and not game.presentation.coin_busy \
		and is_instance_valid(game.presentation.coin_root) and game.presentation.choice_buttons.size() == 2


func has_kind(kind: String) -> bool:
	for event in other_events:
		if event[0] == kind: return true
	return false


func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call():
			return true
		if Time.get_ticks_msec() - start > 10000:
			return false
		await process_frame
	return check.call()


func frames(count: int) -> void:
	for i in count:
		await process_frame


# A real mouse click: motion first, then press and release on the middle of the control.
func click(control: Control) -> void:
	if control == null:
		expect(false, "click: control exists")
		return
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame
