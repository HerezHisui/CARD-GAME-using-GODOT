extends SceneTree
## P2 lists: the battle log, the own deck list and the own graveyard go to a LAN seat only when it asks
## (lan_session.ask_list). The host filters the log per seat and answers with the asking seat's own cards, so
## the other seat's private names never leave the host. The client opens the lists with L, D, G and the
## graveyard button. Also the host's lane_notes: the conditional ability and Blood Pact inspect lines.

const LanSession = preload("res://scripts/lan_session.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

const TEST_PORT := 24801
# Only the Preparedness seat may see these. "Unit PrepHandSecret" is a hand card, the others deck and graveyard.
const PREP_SECRETS := ["PrepHandSecret", "PrepDeckSecret", "PrepGraveSecret"]
# Only the Disaster seat may see these.
const DISASTER_SECRETS := ["DisDeckSecret", "DisGraveSecret"]

var failures := 0
var checks := 0
var game: Node
var director: Node
var host: Node
var client: Node
var client_joined := false
var answers: Array = []  # [kind, items] from the host, in order
var unlock_name := ""  # the Plan the test unlocks: private to Preparedness


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not check.call() and Time.get_ticks_msec() - start < 10000:
		await process_frame
	return check.call()


func unit(id: String) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": 1, "attack": 1,
		"health": 10}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0, "attack": 1,
		"health": 10}


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	game.presentation.automated_choice = 0
	await process_frame
	fixture()
	check_seat_log()
	check_seat_lists()
	check_lane_notes()
	await check_wire()
	await check_client()
	game.player_buffs.clear()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("%s: lan_lists_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)


# A Versus board with a secret in each private zone and three log lines: one public, two private.
func fixture() -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.set_seats("remote", "local")
	game.turn = 2
	game.versus_master = {"preparedness": [unit("PrepDeckSecret")], "disaster": [threat("DisDeckSecret")]}
	var fallen := unit("PrepGraveSecret")
	fallen.merge({"graveyard_reason": "Destroyed", "graveyard_round": 2})
	game.player_graveyard.append(fallen)
	var burned := threat("DisGraveSecret")
	burned.merge({"graveyard_reason": "Sacrificed", "graveyard_round": 1})
	game.disaster_graveyard.append(burned)
	game.log_event("Public test line.")
	# The real callers: a card into the Preparedness hand and a Plan unlock.
	game.add_card_to_hand(unit("PrepHandSecret"))
	unlock_name = str(game.plans.definition("extract").name)
	game.plans.unlock("extract")


func check_seat_log() -> void:
	var prep: Array = LanView.seat_log(game, "preparedness")
	var disaster: Array = LanView.seat_log(game, "disaster")
	var prep_text := "\n".join(prep)
	var disaster_text := "\n".join(disaster)
	expect(prep.size() == disaster.size() and prep.size() == game.battle_log.size(), "one line per host line")
	expect(prep_text.contains("Public test line.") and disaster_text.contains("Public test line."),
		"a public line goes to both seats")
	expect(prep_text.contains("Response receives Unit PrepHandSecret."), "Preparedness reads its own draw")
	expect(disaster_text.contains("Round 2 | Response draws a card."), "Disaster reads the public draw words")
	expect(prep_text.contains(unlock_name), "Preparedness reads its own Plan unlock")
	expect(not disaster_text.contains(unlock_name) and disaster_text.contains("Preparedness unlocks a contingency."),
		"Disaster reads the public unlock words")
	expect("\n".join(game.battle_log).contains("PrepHandSecret"), "the local battle log keeps the full line")
	for word in PREP_SECRETS:
		expect(not disaster_text.contains(word), "the Disaster log hides " + word)
	# A line with no privacy tag (restored from a save) is left out of both seat logs.
	game.battle_log.push_front("Round 1 | Untagged PrepHandSecret line")
	expect(not "\n".join(LanView.seat_log(game, "disaster")).contains("Untagged"), "an untagged line is left out")
	expect(not "\n".join(LanView.seat_log(game, "preparedness")).contains("Untagged"), "for both seats")
	game.battle_log.pop_front()


func check_seat_lists() -> void:
	var prep_deck: Array = LanView.seat_list(game, "preparedness", "deck")
	var prep_grave: Array = LanView.seat_list(game, "preparedness", "grave")
	var disaster_deck: Array = LanView.seat_list(game, "disaster", "deck")
	var disaster_grave: Array = LanView.seat_list(game, "disaster", "grave")
	expect(prep_deck.size() == 1 and prep_deck[0].name == "Unit PrepDeckSecret", "Preparedness deck list")
	expect(prep_grave.size() == 1 and prep_grave[0].graveyard_reason == "Destroyed", "Preparedness graveyard list")
	expect(disaster_deck.size() == 1 and disaster_deck[0].name == "Threat DisDeckSecret", "Disaster deck list")
	expect(disaster_grave.size() == 1 and disaster_grave[0].name == "Threat DisGraveSecret", "Disaster graveyard")
	prep_deck[0].name = "changed"
	expect(game.versus_master.preparedness[0].name == "Unit PrepDeckSecret", "the lists are copies")
	expect(LanView.seat_list(game, "", "deck").is_empty(), "no seat, no list")
	expect(LanView.seat_list(game, "disaster", "zones").is_empty(), "an unknown kind is empty")
	for kind in ["log", "deck", "grave"]:
		check_private(LanView.seat_list(game, "disaster", kind), "disaster", "local " + kind)
		check_private(LanView.seat_list(game, "preparedness", kind), "preparedness", "local " + kind)


# What a seat received never names a private card of the other seat.
func check_private(items: Array, seat: String, label: String) -> void:
	var text := JSON.stringify(items)
	var forbidden: Array = PREP_SECRETS if seat == "disaster" else DISASTER_SECRETS
	for word in forbidden:
		expect(not text.contains(word), "%s: the %s seat never gets %s" % [label, seat, word])
	if seat == "disaster": expect(not text.contains(unlock_name), label + ": no Preparedness Plan name")


func put(definition: Dictionary, slot: Node3D) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.current_slot = slot
	card.in_hand = false
	return card


# The host's notes for the lane cards: Blood Pact (a buff), and the conditional ability (balance on, local seats).
func check_lane_notes() -> void:
	game.set_seats("local", "local")
	game.disaster_is_human = true
	game.balance_patch_override = true
	var hunter := threat("Hunter")
	hunter["condition"] = {"subject": "target", "status": "burn", "threshold": 1}
	var foe := put(hunter, game._threat_slots()[1])
	var ally := put(unit("Ally"), game._response_slots()[1])
	ally.statuses["burn"] = 2
	game.player_buffs["blood_pact"] = 1
	var notes: Dictionary = LanView.lane_notes(game)
	expect(notes.response.size() == 4 and notes.disaster.size() == 4, "one note per lane")
	expect(notes.response[1].get("blood_pact", false), "Blood Pact on the Preparedness lane card")
	expect(not notes.disaster[1].has("blood_pact"), "no Blood Pact on the Disaster card")
	expect(notes.disaster[1].get("condition", false) == true, "the conditional ability is active")
	expect(notes.response[0].is_empty(), "an empty lane has an empty note")
	ally.statuses["burn"] = 0
	expect(LanView.lane_notes(game).disaster[1].get("condition", true) == false, "the conditional ability is off")
	expect(LanView.build(game, "disaster").has("lane_notes") and LanView.build_prep(game).has("lane_notes"),
		"both views carry the lane notes")
	foe.free()
	ally.free()
	game.player_buffs.clear()
	game.balance_patch_override = null
	game.set_seats("remote", "local")


func make_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = LanSession.new()
	session.name = "LanSession"
	holder.add_child(session)
	return session


# Over a loopback link: each seat asks for every list and gets only its own cards.
func check_wire() -> void:
	host = make_side("Host")
	host.game = game
	expect(host.host_game(TEST_PORT) == OK, "host listens")
	client = make_side("Client")
	client.joined_host.connect(func() -> void: client_joined = true)
	client.list_received.connect(func(kind: String, items: Array) -> void: answers.append([kind, items]))
	client.join_game("127.0.0.1", TEST_PORT)
	expect(await wait_until(func() -> bool: return client_joined and host.disaster_peer != 0), "client joins")
	for seat in ["disaster", "preparedness"]:
		host.seat_client(seat)
		for kind in ["log", "deck", "grave", "zones"]:
			answers.clear()
			client.request_list(kind)
			var answered: bool = await wait_until(func() -> bool: return not answers.is_empty())
			expect(answered, "%s gets an answer: %s" % [seat, kind])
			if answers.is_empty(): continue
			expect(answers[0][0] == kind, "the answer names the kind")
			check_private(answers[0][1], seat, "wire " + kind)
			if kind == "zones": expect(answers[0][1].is_empty(), "an unknown kind gets an empty list")
		answers.clear()
		client.request_list("deck")
		await wait_until(func() -> bool: return not answers.is_empty())
		var own := "PrepDeckSecret" if seat == "preparedness" else "DisDeckSecret"
		expect(not answers.is_empty() and JSON.stringify(answers[0][1]).contains(own), seat + ": its own deck arrives")
	# A local call has sender 0, which is no seat. The lobby answers nothing either.
	answers.clear()
	host.ask_list("deck")
	host.lobby = true
	client.request_list("deck")
	await frames(20)
	expect(answers.is_empty(), "no answer to a local call or during the lobby")
	host.lobby = false
	host.close()
	client.close()
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await frames()


func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": {},
		"modifiers": [], "planned_guard": 0}}


func client_view() -> Dictionary:
	var empty := {}
	return {
		"round": 2, "first_side": "response", "coin": {}, "side": "preparedness", "phase": "play",
		"turn_side": "preparedness", "is_prep_turn": true, "prep_hand": [],
		"sides": {"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4}},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["t", "", "", ""]},
		"cards": {"a": entry(unit("Ally")), "t": entry(threat("Foe"))}, "hints": [],
		"counts": {"disaster_hand": 2, "disaster_draw": 9, "response_draw": 8, "response_graveyard": 1},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
		"lane_notes": {"response": [{"blood_pact": true, "condition": true}, empty, empty, empty],
			"disaster": [empty, empty, empty, empty]},
	}


# The client board: L, D, G and the graveyard button ask; the answer opens the list; Esc or the key closes it.
func check_client() -> void:
	var session: Node = LanSession.new()
	root.add_child(session)
	var panel := LanPrepPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	director.visible = false
	var board: Node = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, director, session, panel, "preparedness", cover)
	session.view_received.emit(client_view())
	await frames(5)
	var combat: String = board._combat_text(board.lane_cards.response[0])
	expect(combat.contains("Blood Pact: defeat a card this turn or die"), "inspect: the Blood Pact line")
	expect(combat.contains("Conditional ability: ACTIVE"), "inspect: the conditional ability line")
	expect(not board._combat_text(board.lane_cards.disaster[0]).contains("Blood Pact"), "inspect: no line on the foe")
	await key(KEY_L)
	expect(board.list_wanted == "log" and not is_instance_valid(board.list_overlay), "L asks the host for the log")
	session.list_received.emit("deck", [unit("Wrong")])
	expect(not is_instance_valid(board.list_overlay), "an answer of another kind is dropped")
	session.list_received.emit("log", ["Round 2 | Line A"])
	expect(is_instance_valid(board.list_overlay) and board.list_overlay.name == "List_log", "the log opens")
	if is_instance_valid(board.list_overlay):
		var text: RichTextLabel = board.list_overlay.find_child("LogText", true, false)
		expect(text != null and text.text.contains("Line A"), "the log text shows")
	await key(KEY_L)
	expect(not is_instance_valid(board.list_overlay) and board.list_wanted == "", "L again closes it")
	await key(KEY_D)
	session.list_received.emit("deck", [unit("Deck A")])
	var grid: Node = board.list_overlay.find_child("ListGrid", true, false) if is_instance_valid(board.list_overlay) \
		else null
	expect(grid != null and grid.get_child_count() == 1, "D lists the deck")
	await key(KEY_G)
	var fallen := unit("Fallen")
	fallen.merge({"graveyard_reason": "Destroyed", "graveyard_round": 2})
	session.list_received.emit("grave", [fallen])
	await frames()
	expect(is_instance_valid(board.list_overlay) and board.list_overlay.name == "List_grave", "G switches lists")
	if is_instance_valid(board.list_overlay):
		var captions: Array = board.list_overlay.find_children("*", "Label", true, false).filter(
			func(label: Label) -> bool: return label.text == "Destroyed · round 2")
		expect(captions.size() == 1, "the graveyard caption shows the reason and round")
	await key(KEY_ESCAPE)
	expect(not is_instance_valid(board.list_overlay), "Esc closes the list")
	await key(KEY_L)
	await key(KEY_ESCAPE)
	session.list_received.emit("log", ["Round 2 | Late"])
	expect(not is_instance_valid(board.list_overlay), "a late answer after Esc opens nothing")
	board.prep_grave.pressed.emit()
	expect(board.list_wanted == "grave", "the graveyard button asks for the graveyard")
	board.close_list()
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.visible = true
	await frames()
