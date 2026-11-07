extends SceneTree
## LAN leftovers part 3: custom decks on both seats, the opening evolution choice, and no leak.
## The host plays one side with its own saved custom deck, the client sends a custom deck for the other side.
## The LAN evolution override is on (lan_evolution_picks_override true). Both orientations run:
##   host Preparedness + client Disaster (the client picks the opening evolution over the wire),
##   host Disaster + client Preparedness (the host picks it on its own screen with a real click).
## Every view and event the client got is searched for the host side's cards and for private keys.

const LanSession = preload("res://scripts/lan_session.gd")
const Decks = preload("res://scripts/versus_decks.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24760
const MAX_FRAMES := 3000
const SAVE_PATH := "user://test_lan_leftover_deck_opening.cfg"
const PRIVATE_KEYS := ["evolution_offer", "held_evolutions", "match_id", "offer_id", "candidates",
	"reserve_copies", "reserve_order", "index", "reserve_index", "next_id", "rng", "run_rng_state"]

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession client
var other_joined := false
var other_events: Array = []  # [kind, data] from the host
var views: Array = []  # every view the client got


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
	make_other()
	# A fresh game per orientation. A leftover Disaster turn of an ended match can still move the phase of
	# the next match in the same app run (game_3d_manager _enemy_turn, no serial guard in LAN). Not this test.
	await check_flow("preparedness")
	await check_flow("disaster")
	other.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_leftover_deck_opening_smoke (%d checks)" % checks)
	quit(0)


func new_game() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	await process_frame
	director.show_title()
	director.add_lan_buttons(director.content.get_child(0))
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_lan_leftover_deck_opening_lan.cfg"
	game.lan_evolution_picks_override = true


func free_game() -> void:
	lan.session.close()
	game.lan_evolution_picks_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await frames(5)


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.joined_host.connect(func() -> void: other_joined = true)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.view_received.connect(func(view: Dictionary) -> void: views.append(view))


# One orientation. host_side is the side the host plays; the client plays the other side.
func check_flow(host_side: String) -> void:
	var client_side := other_side_of(host_side)
	var name := "host " + host_side
	await new_game()
	views.clear()
	Decks.save_custom(host_side, custom_deck(host_side))
	var versus: Node = await host_to_deck_step(name, host_side, "custom")
	if versus == null:
		await free_game()
		return
	var client_deck := custom_deck(client_side)
	other.request_deck(client_deck)
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the seat comes after the deck")
	expect(not has_kind("deck_note"), name + ": no deck note for a valid deck")
	expect(versus.custom_decks.size() == 2, name + ": both seats play a custom deck")
	expect(versus.custom_decks.get(client_side, {}) == client_deck, name + ": the host keeps the client deck")
	expect(versus.custom_decks.get(host_side, {}) == Decks.load_custom(host_side), name + ": the host deck is its own")
	# The opening evolution choice is open for the Disaster.
	var opened: bool = await wait_until(func() -> bool: return opening_seen(client_side))
	expect(opened, name + ": the client view shows the opening evolution state")
	expect(game.evolution_choice.lan_enabled(), name + ": the LAN evolution picks are on")
	expect(game.evolution_choice.pending() and game.evolution_choice.offer.size() == 3, name + ": three cards on offer")
	check_zones(host_side, name)
	var forbidden := host_cards(host_side)
	expect(forbidden.size() > 10, name + ": the host side has cards to hide")
	audit(client_side, forbidden, name + " opening")
	# Pick the opening evolution.
	if client_side == "disaster":
		await pick_over_the_wire(name)
	else:
		await pick_on_host(name)
	expect(game.evolution_choice.held.size() == 1, name + ": one evolution is held")
	expect(not game.evolution_choice.pending(), name + ": the choice is closed")
	expect(game.enemy_evolution_deck.size() == 5, name + ": five evolutions stay in the deck")
	var moved: bool = await wait_until(func() -> bool: return game.phase != game.Phase.SETUP)
	expect(moved, name + ": the match goes on after the pick")
	await frames(10)
	audit(client_side, forbidden, name + " after the pick")
	check_no_host_deck(name)
	await end_host_match(name)
	await free_game()


# True once a view for the client shows the opening evolution state.
func opening_seen(client_side: String) -> bool:
	for view: Dictionary in views:
		if client_side == "disaster" and not view.get("evolution_offer", {}).is_empty(): return true
		if client_side == "preparedness" and view.get("evolution_waiting", false): return true
	return false


# The cards of both piles are the custom decks, on the host board.
func check_zones(host_side: String, name: String) -> void:
	var prep_deck: Dictionary = game_custom("preparedness", host_side)
	var disaster_deck: Dictionary = game_custom("disaster", host_side)
	var prep_ids := ids(game.deck)
	prep_ids.append_array(hand_ids())
	prep_ids.sort()
	var want_prep: Array = prep_deck.main.duplicate()
	want_prep.sort()
	expect(prep_ids == want_prep, name + ": Preparedness deck and hand are its custom deck")
	expect(game.plans.unlocked == prep_deck.tactics, name + ": Preparedness uses its custom tactics")
	var main_ids := ids(game.enemy_deck)
	main_ids.append_array(ids(game.enemy_hand))
	main_ids.sort()
	var want_main: Array = disaster_deck.main.duplicate()
	want_main.sort()
	expect(main_ids == want_main, name + ": the Disaster main cards are its custom deck")
	var evo_ids := ids(game.enemy_evolution_deck)
	for entry in game.evolution_choice.held: evo_ids.append(entry.definition.get("id", ""))
	evo_ids.sort()
	var want_evo: Array = disaster_deck.evolutions.duplicate()
	want_evo.sort()
	expect(evo_ids == want_evo, name + ": the Disaster evolutions are its custom deck")


# The custom deck of a side: the host's saved one, or the one the client sent.
func game_custom(side: String, host_side: String) -> Dictionary:
	return director.versus_match.custom_decks.get(side, {})


# Ids and names of every card in the host side's master list. The client must never see them.
# A text the client's own cards also use (an effect called "seal" and a card id "seal") is not a clue.
func host_cards(host_side: String) -> Array:
	var own: Array = []
	for card: Dictionary in game.versus_master[other_side_of(host_side)]:
		for value in card.values():
			if value is String and value not in own: own.append(value)
	var out: Array = []
	for card: Dictionary in game.versus_master[host_side]:
		for key in ["id", "name"]:
			var text := str(card.get(key, ""))
			if text != "" and text not in out and text not in own: out.append(text)
	return out


# No view or event the client got holds a host card or a private key. Disaster views may hold their own offer.
func audit(client_side: String, forbidden: Array, label: String) -> void:
	var text := JSON.stringify(views) + JSON.stringify(other_events)
	var leaked: Array = []
	for card_text: String in forbidden:
		if text.contains("\"%s\"" % card_text): leaked.append(card_text)
	expect(leaked.is_empty(), label + ": no host card in the client views and events " + str(leaked))
	expect(not views.is_empty(), label + ": the client got views")
	for view: Dictionary in views:
		if client_side == "preparedness":
			expect(not has_private_key(view), label + ": a Preparedness view has no private zones or keys")
			expect(not view.has("disaster_hand"), label + ": a Preparedness view has no Disaster hand")
		else:
			expect(not view.has("prep_hand") and not view.has("deck"), label + ": a Disaster view has no Preparedness zone")


func has_private_key(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if key in PRIVATE_KEYS or has_private_key(value[key]): return true
	elif value is Array:
		for entry in value:
			if has_private_key(entry): return true
	return false


# The Disaster client names the first card on offer, through the real network.
func pick_over_the_wire(name: String) -> void:
	var offer: Dictionary = {}
	for view: Dictionary in views:
		if not view.get("evolution_offer", {}).is_empty(): offer = view.evolution_offer
	expect(not offer.is_empty(), name + ": the client has an offer")
	if offer.is_empty(): return
	expect(offer.candidates.size() == 3, name + ": the client sees three candidates")
	other.request_action({"kind": "evolution_pick", "match_id": offer.match_id, "offer_id": offer.offer_id,
		"id": offer.candidates[0].id})
	expect(await wait_until(func() -> bool: return game.evolution_choice.held.size() == 1),
		name + ": the host takes the client's pick")
	var count := views.size()
	var shown: bool = await wait_until(func() -> bool: return client_holds_one(count))
	expect(shown, name + ": the client view shows the held copy")


# The host is the Disaster: it picks on its own screen with a real click on the first Choose button.
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
	var count := views.size()
	expect(await wait_until(func() -> bool: return prep_stopped_waiting(count)),
		name + ": the Preparedness view stops waiting")


# A newer Disaster view with exactly one held copy.
func client_holds_one(old_count: int) -> bool:
	if views.size() <= old_count: return false
	return views[-1].get("held_evolutions", []).size() == 1


# A newer Preparedness view that no longer waits for a Disaster pick.
func prep_stopped_waiting(old_count: int) -> bool:
	if views.size() <= old_count: return false
	return not views[-1].get("evolution_waiting", true)


func find_choose_button() -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == "Choose" and node.is_visible_in_tree(): return node
	return null


# --- helpers, same as lan_deck_smoke.gd ---

# Host, join, Start match, call the coin, pick so that Player 1 gets host_side, then wait for the step.
func host_to_deck_step(name: String, host_side: String, host_deck: String) -> Node:
	director.show_title()
	lan.show_host()
	other_joined = false
	other_events.clear()
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, name + ": the client starts joining")
	expect(await wait_until(func() -> bool: return other_joined and lan.room_connected()), name + ": joined")
	lan.start_match()
	var versus: Node = director.versus_match
	versus.deck_choice = true
	versus.automated_deck = host_deck
	expect(versus.remote_deck_choice, name + ": the host waits for the client deck")
	expect(await wait_until(coin_screen_ready), name + ": the coin screen shows")
	await frames(3)
	await click(game.presentation.choice_buttons[0])
	expect(await wait_until(func() -> bool: return versus.prematch_active), name + ": the side pick starts")
	versus.choose_side(host_side if versus.coin_winner == 1 else other_side_of(host_side))
	expect(versus.player1_side == host_side, name + ": the host has its side")
	if not await wait_until(func() -> bool: return has_kind("deck_step")):
		expect(false, name + ": the client hears the deck step")
		return null
	return versus


func end_host_match(name: String) -> void:
	director.versus_match.automated_deck = ""
	other.close()
	expect(await wait_until(func() -> bool: return not director.versus_match.running), name + ": the match ended")
	lan.session.close()
	await frames(5)


# Nothing the client got has a deck in it. deck_step has only the side.
func check_no_host_deck(name: String) -> void:
	var clean := true
	for event in other_events:
		var data: Dictionary = event[1]
		if data.has("main") or data.has("evolutions") or data.has("tactics") or data.has("deck"):
			clean = false
		if event[0] == "deck_step" and data.keys() != ["side"]:
			clean = false
	expect(clean, name + ": no deck goes to the client")


static func other_side_of(side: String) -> String:
	return "disaster" if side == "preparedness" else "preparedness"


# A legal deck that differs from the preset: one copy of a main card is swapped for another.
func custom_deck(side: String) -> Dictionary:
	var deck: Dictionary = Decks.preset(side).duplicate(true)
	var pool: Dictionary = Decks.pool(side)
	var main_pool: Dictionary = pool.base.duplicate()
	if side == Decks.SIDE_DISASTER: main_pool.merge(pool.spells)
	deck.main = swap_one(deck.main, main_pool)
	if side == Decks.SIDE_DISASTER: deck.evolutions = swap_one(deck.evolutions, pool.evolutions)
	else: deck.tactics = ["brace", "supply", "flank"]
	expect(Decks.validate(side, deck).ok, "custom deck for " + side + " is valid")
	return deck


func swap_one(pile: Array, allowed: Dictionary) -> Array:
	var out: Array = pile.duplicate()
	for id: String in allowed:
		if out.count(id) == 0:
			out[0] = id
			return out
	return out


func ids(cards: Array) -> Array:
	var out: Array = []
	for card: Dictionary in cards: out.append(card.get("id", ""))
	out.sort()
	return out


func hand_ids() -> Array:
	var out: Array = []
	for card in game.hand: out.append(card.card_data.get("id", ""))
	out.sort()
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
