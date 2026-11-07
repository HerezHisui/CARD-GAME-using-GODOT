extends SceneTree
## Deck builder Part 3: the LAN client picks Standard or a custom deck (lan_title.gd, lan_session.gd).
## Part 1: the real host lan_title with a plain LanSession client, as in lan_lobby_smoke.gd.
## Part 2: the real client lan_title with a plain LanSession host that sends the events by hand.
## The flag is turned on through versus_match.deck_choice, so this suite works with the const either way.

const LanSession = preload("res://scripts/lan_session.gd")
const LanTitle = preload("res://scripts/lan_title.gd")
const Decks = preload("res://scripts/versus_decks.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24705
const MAX_FRAMES := 3000
const SAVE_PATH := "user://test_lan_deck_smoke.cfg"

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession on the other side
var other_joined := false
var other_refused := ""
var other_events: Array = []  # [kind, data] from the host
var other_decks: Array = []  # host side: decks the client sent
var other_joins: Array = []


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
	check_protocol_const()
	check_shape()
	make_other()
	director.show_title()
	director.add_lan_buttons(director.content.get_child(0))
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_lan_deck_smoke_lan.cfg"
	# Part 1: the real host.
	await check_host_standard()
	await check_host_custom("preparedness")
	await check_host_custom("disaster")
	await check_host_invalid("wrong sizes", {"main": ["fire_drill"], "evolutions": [], "tactics": ["brace"]})
	await check_host_invalid("too many copies", too_many_copies())
	await check_host_invalid("unknown ids", unknown_ids())
	await check_host_invalid("main as a String", {"main": "fire_drill", "evolutions": [], "tactics": []})
	await check_host_invalid("10000 entries", ten_thousand())
	await check_host_leaves_step()
	await check_version_refused()
	# Part 2: the real client.
	await check_client_standard()
	await check_client_customize()
	await check_client_host_left()
	lan.session.close()
	other.close()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_deck_smoke (%d checks)" % checks)
	quit(0)


func check_protocol_const() -> void:
	# PROTOCOL is a const from the flags: 3 + 1 (evolution picks) + 2 (prep utilities) with the defaults on.
	expect(LanSession.PROTOCOL == 6, "protocol: PROTOCOL is 6 with the current flag defaults")
	expect(LanSession.build_string().begins_with("6|"), "protocol: the build string starts with 6")


# The shape check runs before validate, so a bad payload cannot crash the host handler.
func check_shape() -> void:
	expect(LanTitle.deck_shape_ok({}), "shape: {} is Standard")
	expect(LanTitle.deck_shape_ok(Decks.preset("disaster")), "shape: a preset is fine")
	expect(not LanTitle.deck_shape_ok("deck"), "shape: a String is refused")
	expect(not LanTitle.deck_shape_ok([1, 2]), "shape: an Array is refused")
	expect(not LanTitle.deck_shape_ok(null), "shape: null is refused")
	expect(not LanTitle.deck_shape_ok({"main": "fire_drill"}), "shape: main as a String is refused")
	expect(not LanTitle.deck_shape_ok({"main": [1, 2]}), "shape: numbers in main are refused")
	expect(not LanTitle.deck_shape_ok({"tactics": {"a": 1}}), "shape: tactics as a Dictionary is refused")
	expect(not LanTitle.deck_shape_ok(ten_thousand()), "shape: 10000 entries are refused")
	var long_pile: Array = []
	for i in 41: long_pile.append("fire_drill")
	expect(not LanTitle.deck_shape_ok({"main": long_pile}), "shape: 41 entries are refused")


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.joined_host.connect(func() -> void: other_joined = true)
	other.join_refused.connect(func(reason: String) -> void: other_refused = reason)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.deck_requested.connect(func(deck) -> void: other_decks.append(deck))
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))


# --- Part 1: host ---

# Host and client play Standard. The step is sent once, a stale deck is ignored, the page ends with "seat".
func check_host_standard() -> void:
	var name := "host standard"
	var versus: Node = await host_to_deck_step(name, "preparedness", "standard")
	if versus == null:
		return
	var client_side: String = versus.player2_side
	var step: Dictionary = last_event("deck_step")
	expect(step.keys() == ["side"] and step.side == client_side, name + ": deck_step has only the client side")
	expect(not has_kind("seat"), name + ": no seat before the client deck")
	await frames(20)
	expect(count_kind("deck_step") == 1, name + ": deck_step is sent once")
	other.request_deck({})
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the seat comes after the deck")
	expect(count_kind("deck_step") == 1, name + ": still one deck_step")
	expect(not has_kind("deck_note"), name + ": no deck note for Standard")
	expect(versus.custom_decks.is_empty(), name + ": both play Standard")
	# A stale deck after the step is ignored (no lobby, no step).
	other.request_deck(Decks.preset(client_side))
	await frames(20)
	expect(not has_kind("deck_note") and versus.custom_decks.is_empty(), name + ": a stale deck is ignored")
	check_no_host_deck(name)
	await end_host_match(name)


# The client's custom deck is used: its cards and piles are on the host board.
func check_host_custom(client_side: String) -> void:
	var name := "host custom " + client_side
	var host_side := other_side_of(client_side)
	# Legacy fixture: no evolution draw choice (local or LAN), so the 21 / 5 piles are counted as before.
	game.evolution_draw_choice_override = false
	game.lan_evolution_picks_override = false
	# The host plays its own saved custom deck. It must never reach the client.
	Decks.save_custom(host_side, custom_deck(host_side))
	var versus: Node = await host_to_deck_step(name, host_side, "custom")
	if versus == null:
		return
	expect(versus.player2_side == client_side, name + ": the client has the side")
	var deck := custom_deck(client_side)
	other.request_deck(deck)
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the seat comes after the deck")
	expect(not has_kind("deck_note"), name + ": no deck note for a valid deck")
	expect(versus.custom_decks.get(client_side, {}) == deck, name + ": the host keeps the client deck")
	var want: Array = deck.main.duplicate()
	want.sort()
	if client_side == "preparedness":
		var all_ids := ids(game.deck)
		all_ids.append_array(hand_ids())
		all_ids.sort()
		expect(all_ids == want, name + ": deck and hand are the client's 24 cards")
		expect(game.hand.size() == 3 and game.deck.size() == 21, name + ": 3-card hand, 21 in the deck")
		expect(game.plans.unlocked == deck.tactics, name + ": the client's tactics")
	else:
		var main_ids := ids(game.enemy_deck)
		var evo_ids := ids(game.enemy_evolution_deck)
		for card: Dictionary in game.enemy_hand:
			if int(card.get("cost", 0)) > 0: evo_ids.append(card.id)
			else: main_ids.append(card.id)
		main_ids.sort()
		evo_ids.sort()
		var want_evo: Array = deck.evolutions.duplicate()
		want_evo.sort()
		expect(main_ids == want, name + ": the 24 main cards are the client's")
		expect(evo_ids == want_evo, name + ": the 6 evolutions are the client's")
		expect(game.enemy_deck.size() == 21 and game.enemy_evolution_deck.size() == 5, name + ": 21 / 5 piles")
	check_no_host_deck(name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await end_host_match(name)


# A bad deck means the Standard deck, and the client hears why.
func check_host_invalid(label: String, deck) -> void:
	var name := "host invalid " + label
	var versus: Node = await host_to_deck_step(name, "disaster", "standard")
	if versus == null:
		return
	# Send the raw payload through the real RPC, as a modified client would.
	other.pick_deck.rpc_id(1, deck)
	expect(await wait_until(func() -> bool: return has_kind("deck_note")), name + ": the client gets a deck note")
	expect(str(last_event("deck_note").get("text", "")) == LanTitle.DECK_NOTE, name + ": the note text")
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the match goes on")
	expect(versus.custom_decks.is_empty(), name + ": the client plays Standard")
	expect(game.enemy_deck.size() + game.enemy_hand.size() >= 24 or game.deck.size() + game.hand.size() == 24,
		name + ": the board still has full decks")
	await end_host_match(name)


# The client leaves during the deck step: the match ends, no hang, no deck screen left.
func check_host_leaves_step() -> void:
	var name := "leave in deck step"
	var versus: Node = await host_to_deck_step(name, "preparedness", "")
	if versus == null:
		return
	expect(is_instance_valid(game.presentation.deck_root), name + ": the host deck screen shows")
	other.close()
	expect(await wait_until(func() -> bool: return not versus.running), name + ": the match ended")
	await frames(10)
	expect(director.screen == "result" and find_label("OPPONENT LEFT") != null, name + ": Opponent left shows")
	expect(not is_instance_valid(game.presentation.deck_root), name + ": the deck screen is gone")
	expect(not versus.deck_step_active, name + ": no deck step is left")
	expect(not lan.session.is_open() and not lan.in_match, name + ": the host closed the session")
	versus.automated_deck = ""
	await frames(5)


# An old build (PROTOCOL 1) is still refused by the version check.
func check_version_refused() -> void:
	var name := "version"
	director.show_title()
	lan.show_host()
	other_refused = ""
	other.build = "1|" + Engine.get_version_info().string
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, name + ": the old client starts joining")
	expect(await wait_until(func() -> bool: return other_refused == "version"), name + ": the old build is refused")
	expect(not lan.room_connected(), name + ": no Player 2 in the room")
	other.close()
	other.build = LanSession.build_string()
	lan.cancel_host()
	await frames(5)


# --- Part 2: client ---

# Real mouse click on Standard deck: the host gets {}. A note shows in the hint, the seat closes the page.
func check_client_standard() -> void:
	var name := "client standard"
	await join_to_coin(name)
	# The Esc menu stays on top of the deck page.
	await key(KEY_ESCAPE)
	expect(is_instance_valid(lan.esc_menu), name + ": Esc opens the menu")
	other.send_event("deck_step", {"side": "disaster"})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.deck_page)), name + ": the deck page shows")
	expect(lan.client_layer.get_child(-1) == lan.esc_menu, name + ": the Esc menu stays on top")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(lan.esc_menu), name + ": Esc closes the menu")
	var title := find_in(lan.deck_page, "DeckTitle")
	expect(title != null and title.text == "PLAYER 2: DISASTER DECK", name + ": the title names the side")
	var standard := find_in(lan.deck_page, "StandardButton")
	await frames(5)
	await click(standard)
	expect(await wait_until(func() -> bool: return other_decks.size() == 1), name + ": a real click sends the deck")
	expect(other_decks[0] is Dictionary and other_decks[0].is_empty(), name + ": Standard is {}")
	expect(standard.disabled and find_in(lan.deck_page, "CustomizeButton").disabled, name + ": the buttons turn off")
	expect(find_in(lan.deck_page, "DeckHint").text == "Waiting for Player 1...", name + ": waiting for Player 1")
	await click(standard)
	await frames(10)
	expect(other_decks.size() == 1, name + ": a second click sends nothing")
	other.send_event("deck_note", {"text": LanTitle.DECK_NOTE})
	expect(await wait_until(func() -> bool: return find_in(lan.deck_page, "DeckHint").text == LanTitle.DECK_NOTE),
		name + ": the deck note shows in the hint")
	await seat_and_leave(name, "disaster")


# Customize opens the builder on the saved deck; Back returns; Done saves and sends the deck.
func check_client_customize() -> void:
	var name := "client customize"
	await join_to_coin(name)
	other.send_event("deck_step", {"side": "preparedness"})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.deck_page)), name + ": the deck page shows")
	expect(find_in(lan.deck_page, "DeckTitle").text == "PLAYER 2: PREPAREDNESS DECK", name + ": the title")
	await frames(5)
	await click(find_in(lan.deck_page, "CustomizeButton"))
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.deck_builder)), name + ": the builder opens")
	expect(lan.deck_builder.current_deck() == Decks.preset("preparedness"), name + ": the builder starts on Standard")
	lan.deck_builder.back.emit()
	await frames(3)
	expect(not is_instance_valid(lan.deck_builder), name + ": Back closes the builder")
	expect(find_in(lan.deck_page, "DeckCenter").visible, name + ": Back shows the two buttons")
	expect(other_decks.is_empty(), name + ": Back sends nothing")
	lan._open_deck_builder()
	var deck := custom_deck("preparedness")
	lan.deck_builder.done.emit(deck)
	expect(await wait_until(func() -> bool: return other_decks.size() == 1), name + ": Done sends the deck")
	expect(other_decks[0] == deck, name + ": the host gets the custom deck")
	expect(Decks.load_custom("preparedness") == deck, name + ": the deck is saved on the client")
	expect(find_in(lan.deck_page, "DeckHint").text == "Waiting for Player 1...", name + ": waiting for Player 1")
	expect(not is_instance_valid(lan.deck_builder), name + ": the builder closed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await seat_and_leave(name, "preparedness")


# The host leaves during the deck step: the page closes with the existing message.
func check_client_host_left() -> void:
	var name := "client host left"
	await join_to_coin(name)
	other.send_event("deck_step", {"side": "disaster"})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.deck_page)), name + ": the deck page shows")
	other.close()
	expect(await wait_until(func() -> bool: return not is_instance_valid(lan.deck_page)), name + ": the page closes")
	expect(await wait_until(func() -> bool: return find_label("The host left the match.") != null),
		name + ": the host left message shows")
	expect(not lan.session.is_open(), name + ": the client session is closed")
	await frames(5)


# --- helpers ---

# Host, join, Start match, call the coin, pick so that Player 1 gets host_side, then wait for the step.
# host_deck goes to automated_deck ("" = the host never picks). Returns the versus node, or null.
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
	# A deck during the coin is ignored.
	other.request_deck({"main": "bad"})
	await frames(10)
	expect(not has_kind("deck_note"), name + ": a deck during the coin is ignored")
	versus.choose_side(host_side if versus.coin_winner == 1 else other_side_of(host_side))
	expect(versus.player1_side == host_side, name + ": the host has its side")
	if not await wait_until(func() -> bool: return has_kind("deck_step")):
		expect(false, name + ": the client hears the deck step")
		return null
	expect(versus.deck_step_active and lan.session.lobby, name + ": the step runs in the lobby")
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


func join_to_coin(name: String) -> void:
	expect(other.host_game(TEST_PORT) == OK, name + ": the other side hosts")
	other_joins.clear()
	other_decks.clear()
	director.show_title()
	lan.show_join()
	find_node_named("IpEdit").text = "127.0.0.1"
	await frames(3)
	await click(find_button("Connect"))
	expect(await wait_until(func() -> bool: return other_joins.size() == 1), name + ": the host accepted the client")
	expect(await wait_until(func() -> bool: return lan.room == "client"), name + ": waits in the room")
	other.send_event("start", {})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), name + ": panel after start")
	other.lobby = true
	other.send_event("coin", {"stage": "choosing", "call": 0, "result": 1, "winner": 1})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.coin_page)), name + ": the coin page shows")


func seat_and_leave(name: String, seat: String) -> void:
	other.lobby = false
	other.seat_client(seat)
	other.send_event("seat", {"side": seat})
	expect(await wait_until(func() -> bool: return lan.client_side == seat and not is_instance_valid(lan.deck_page)),
		name + ": the seat closes the deck page")
	expect(not is_instance_valid(lan.coin_page), name + ": the seat closes the coin page")
	lan.back_to_title()
	other.close()
	await frames(5)


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


func too_many_copies() -> Dictionary:
	var deck: Dictionary = Decks.preset("disaster").duplicate(true)
	for i in 3: deck.main[i] = "ember"
	return deck


func unknown_ids() -> Dictionary:
	var deck: Dictionary = Decks.preset("disaster").duplicate(true)
	deck.main[0] = "not_a_card"
	deck.evolutions[0] = "fire_drill"
	return deck


func ten_thousand() -> Dictionary:
	var main: Array = []
	main.resize(10000)
	main.fill("ember")
	return {"main": main, "evolutions": [], "tactics": []}


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
	return count_kind(kind) > 0


func count_kind(kind: String) -> int:
	var count := 0
	for event in other_events:
		if event[0] == kind:
			count += 1
	return count


func last_event(kind: String) -> Dictionary:
	for i in range(other_events.size() - 1, -1, -1):
		if other_events[i][0] == kind:
			return other_events[i][1]
	return {}


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


func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null


func find_label(text: String) -> Label:
	for node in director.content.find_children("*", "Label", true, false):
		if node.text == text:
			return node
	return null


func find_node_named(node_name: String) -> Node:
	return director.content.find_child(node_name, true, false)


func find_in(parent: Node, node_name: String) -> Control:
	return parent.find_child(node_name, true, false) if is_instance_valid(parent) else null
