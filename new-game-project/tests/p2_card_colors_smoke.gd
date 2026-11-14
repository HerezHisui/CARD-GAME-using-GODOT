extends SceneTree
## p2-colors: the LAN client (Player 2) draws its hand cards with the same colour as the host.
## The host never greys a hand card it cannot play. At the start of a P2 turn the host is still busy,
## so every hint says "cannot play". The client used to grey all its cards then.
## Headless has no pixels, so this compares the colour each card face is drawn with (the sprite tint).

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const TOLERANCE := 0.02

var failures := 0
var checks := 0
var game: Node
var session: Node


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int) -> void:
	for i in count: await process_frame


func unit(card_name: String, card_type: String) -> Dictionary:
	return {"name": card_name, "type": card_type, "element": "evac" if card_type == "response" else "fire",
		"cost": 1, "attack": 2, "health": 4, "tension_cost": 1}


func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition, "runtime": {"max_health": int(definition.health), "statuses": {},
		"modifiers": []}}


## The first view of a P2 turn: the seat's turn, but every hint says "cannot play" yet.
func turn_start_view(seat: String) -> Dictionary:
	var card_type := "response" if seat == "preparedness" else "disaster"
	var view := {
		"match_id": "colors", "round": 1, "first_side": "response", "coin": {}, "phase": "play",
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 1, "resource_cap": 3},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 3},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {"h0": entry(unit("Hand Zero", card_type)), "h1": entry(unit("Hand One", card_type))},
	}
	if seat == "preparedness":
		view.side = "preparedness"
		view.turn_side = "preparedness"
		view.is_prep_turn = true
		view.prep_hand = ["h0", "h1"]
		view.hints = [{"can_play": false, "problem": "busy", "lanes": []},
			{"can_play": false, "problem": "busy", "lanes": []}]
		view.counts = {"disaster_hand": 3, "disaster_draw": 9, "response_draw": 8}
		view.energy = 1
		view.energy_cap = 3
		view.plan_tokens = 0
		view.armed = ""
		view.tactics = []
	else:
		view.turn_side = "disaster"
		view.is_disaster_turn = true
		view.disaster_hand = ["h0", "h1"]
		var hint := {"can_use": false, "problem": "busy", "needs_target": false, "lanes": [], "sacrifices": [],
			"targets": []}
		view.hints = [hint, hint.duplicate()]
		view.counts = {"response_hand": 3, "response_draw": 9, "disaster_draw": 8}
		view.actions_left = 3
	return view


## Mean of the three colour channels.
func mean(color: Color) -> float:
	return (color.r + color.g + color.b) / 3.0


func close_to(a: Color, b: Color) -> bool:
	return absf(mean(a) - mean(b)) <= TOLERANCE and absf(a.s - b.s) <= TOLERANCE


## The host's own hand card, on its own turn, with too little Energy to play it.
func host_tint() -> Color:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.set_seats("local", "remote")
	game.preparedness = 0
	game.add_card_to_hand({"id": "c_host", "name": "Host Card", "type": "response", "element": "evac",
		"cost": 2, "attack": 1, "health": 3})
	game._set_phase(game.Phase.PLAYER_PLAY)
	await frames(5)
	var cards: Array = game.get_hand_cards()
	expect(cards.size() == 1, "host: one hand card")
	var tint: Color = cards[0].art_sprite.modulate if cards.size() == 1 else Color.BLACK
	game.clear_battle()
	game.set_seats("local", "local")
	return tint


func check_seat(seat: String, host: Color) -> void:
	var panel: Control = LanPrepPanel.new() if seat == "preparedness" else LanClientPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, seat, cover)
	session.view_received.emit(turn_start_view(seat))
	await frames(5)
	expect(board._my_turn(), seat + ": it is this seat's turn")
	expect(board.hand_cards.size() == 2, seat + ": two hand cards")
	for card: Node3D in board.hand_cards:
		var tint: Color = card.art_sprite.modulate
		expect(close_to(tint, host), "%s: %s has the host's colour (client %s, host %s)" % [seat,
			card.card_data.name, tint, host])
	board.free()
	cover.free()
	panel.free()
	await frames(2)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.run_director.persistence.enabled = false
	await process_frame
	var host := await host_tint()
	expect(close_to(host, Color.WHITE), "host: a card it cannot play keeps its full colour")
	session = LanSession.new()
	root.add_child(session)
	await check_seat("preparedness", host)
	await check_seat("disaster", host)
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("p2_card_colors_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_card_colors_smoke (%d checks)" % checks)
	quit(0)
