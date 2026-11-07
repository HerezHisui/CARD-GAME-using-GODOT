extends SceneTree
## Audit A7. LAN own-hand cards show the seal banner and the remaining rounds, like the local seat.
## Fake views, no network. A sealed hand card counts down by round and clears when the seal ends.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")

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

func card_def(card_name: String, sealed_until: int = 0) -> Dictionary:
	var definition := {"name": card_name, "type": "response", "element": "evac", "cost": 0, "attack": 1,
		"health": 3}
	if sealed_until > 0: definition.locked_until = sealed_until
	return definition

func entry(definition: Dictionary) -> Dictionary:
	return {"definition": definition,
		"runtime": {"max_health": int(definition.health), "statuses": {}, "modifiers": []}}

# Preparedness view: hand h0 is sealed until round 3, h1 is not sealed.
func make_view(round_number: int) -> Dictionary:
	var hint := {"can_play": true, "problem": "", "lanes": [1, 3]}
	return {
		"round": round_number, "first_side": "response", "coin": {}, "side": "preparedness",
		"is_prep_turn": true, "prep_hand": ["h0", "h1"],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {"h0": entry(card_def("Sealed One", 3)), "h1": entry(card_def("Free One"))},
		"hints": [hint, hint],
		"counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
	}

func banner_of(card: Node) -> Label:
	return card._vp.get_child(0).get_node_or_null("SealBanner")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	session = LanSession.new()
	root.add_child(session)
	var panel: Control = LanPrepPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	session.view_received.emit(make_view(1))
	await process_frame
	var sealed: Node = board.hand_cards[0]
	var free: Node = board.hand_cards[1]
	expect(sealed.preview_seal_round == 1, "the hand card gets the host round")
	var banner := banner_of(sealed)
	expect(banner != null and banner.visible and banner.text == "SEALED · 2 ROUNDS", "banner shows 2 rounds")
	expect(banner_of(free) == null or not banner_of(free).visible, "an unsealed card has no banner")
	# Next round: the same card and definition, one round fewer.
	session.view_received.emit(make_view(2))
	await process_frame
	expect(board.hand_cards[0] == sealed, "the same node keeps the hand slot")
	expect(banner.visible and banner.text == "SEALED · 1 ROUND", "banner counts down to 1 round")
	# Seal over.
	session.view_received.emit(make_view(3))
	await process_frame
	expect(not banner.visible, "banner clears when the seal ends")
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("lan_seal_banner_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: lan_seal_banner_smoke (%d checks)" % checks)
	quit(0)
