extends SceneTree
## LAN finish part 2: a Disaster turn left over from a finished LAN match must not run in the next match.
## One app run, one game, three LAN matches in a row with the evolution picks override on:
## host Preparedness, then host Disaster, then host Preparedness again. Each match must start in SETUP with the
## opening evolution offer open, accept the pick, and then go on. Before the fix the leftover _enemy_turn of the
## old match could move the new match to the ENEMY phase, so the opening pick was refused.

const LanSession = preload("res://scripts/lan_session.gd")
const Decks = preload("res://scripts/versus_decks.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24770
const MAX_FRAMES := 3000
const SAVE_PATH := "user://test_lan_finish_two_matches.cfg"

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession client of the running match
var other_joined := false
var other_events: Array = []
var views: Array = []
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
	lan.cfg_path = "user://test_lan_finish_two_matches_lan.cfg"
	game.lan_evolution_picks_override = true
	var serial_before: int = game.encounter_serial
	await play_match(1, "preparedness")
	await play_match(2, "disaster")
	await play_match(3, "preparedness")
	expect(game.encounter_serial > serial_before, "three matches started three encounters")
	lan.session.close()
	game.lan_evolution_picks_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await frames(5)
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_finish_two_matches_smoke (%d checks)" % checks)
	quit(0)


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


# One match. host_side is the side the host plays; the client plays the other side.
func play_match(number: int, host_side: String) -> void:
	var client_side := "disaster" if host_side == "preparedness" else "preparedness"
	var name := "match %d (host %s)" % [number, host_side]
	make_other()
	Decks.save_custom(host_side, custom_deck(host_side))
	var versus: Node = await host_to_deck_step(name, host_side)
	if versus == null:
		return
	other.request_deck(custom_deck(client_side))
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the seat comes after the deck")
	# The new match is in SETUP with the opening offer open. A leftover turn would have moved it on.
	expect(await wait_until(func() -> bool: return game.evolution_choice.pending()),
		name + ": the opening offer is open")
	expect(game.phase == game.Phase.SETUP, name + ": the phase is SETUP (got %d)" % game.phase)
	await frames(30)
	expect(game.phase == game.Phase.SETUP and game.evolution_choice.pending(),
		name + ": still SETUP after a pause, no stale Disaster turn")
	if client_side == "disaster": await pick_over_the_wire(name)
	else: await pick_on_host(name)
	expect(game.evolution_choice.held.size() == 1 and not game.evolution_choice.pending(),
		name + ": the pick was taken")
	expect(await wait_until(func() -> bool: return game.phase != game.Phase.SETUP), name + ": the match goes on")
	await end_match(name)


func pick_over_the_wire(name: String) -> void:
	expect(await wait_until(func() -> bool: return last_offer().size() > 0), name + ": the client has an offer")
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


# The host is the Disaster: a real click on the first Choose button.
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


func find_choose_button() -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == "Choose" and node.is_visible_in_tree(): return node
	return null


# Host, join, Start match, call the coin, pick so that Player 1 gets host_side, then wait for the deck step.
func host_to_deck_step(name: String, host_side: String) -> Node:
	director.show_title()
	lan.show_host()
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
	var client_side := "disaster" if host_side == "preparedness" else "preparedness"
	versus.choose_side(host_side if versus.coin_winner == 1 else client_side)
	if not await wait_until(func() -> bool: return has_kind("deck_step")):
		expect(false, name + ": the client hears the deck step")
		return null
	return versus


# The client leaves and the host session closes, as at the end of a real match.
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
