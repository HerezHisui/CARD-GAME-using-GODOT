extends SceneTree
var failures := 0
var game: Node
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)
func unit(response: bool, lane: int, attack: int, health: int) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"name":"Test unit", "type":"response" if response else "disaster", "element":"evac" if response else "fire", "cost":1, "attack":attack, "health":health})
	card.place_on_slot((game._response_slots() if response else game._threat_slots())[lane])
	return card
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/section3_" + name + ".png")
func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var director = game.run_director
	director.new_run()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	var starter: Array[Dictionary] = []
	game.load_deck_from_json("res://data/starter_deck.json", starter)
	check(starter.size() == 12, "starter remains twelve cards")
	check(starter.filter(func(c): return c.cost == 1).size() == 11, "eleven one-cost starter cards")
	check(starter.filter(func(c): return int(c.cost) in [2, 3] and game.has_special_effect(c)).size() == 1,
		"one higher-cost starter card with an effect")
	game.player_buffs = {"blood_pact":1}
	game.enemy_buffs = {"blood_pact":1}
	var killer := unit(true, 0, 5, 10)
	var victim := unit(false, 0, 0, 1)
	var missed := unit(true, 1, 0, 10)
	var resting := unit(false, 2, 1, 10)
	resting.add_modifier("sluggish")
	game.add_card_to_hand(starter[0])
	check(killer.effective_attack() == 7 and int(killer.statuses.get("bleed", 0)) == 0, "Blood Pact grants two attack without Bleed")
	game.resolve_single_strike(killer, victim, true)
	game.resolve_single_strike(missed, null, true)
	game.resolve_blood_pact()
	check(killer.is_alive(), "a card kill satisfies the pact")
	check(not missed.is_alive(), "hero-only attacks do not satisfy the pact")
	check(not resting.is_alive(), "resting enemy units also pay the pact")
	check(game.get_hand_cards().size() == 1, "hand cards are exempt")
	killer.set_meta("combat_kill", false)
	game.resolve_blood_pact()
	check(not killer.is_alive(), "previous combat kills do not protect a unit")
	var retaliator := unit(true, 2, 0, 10)
	retaliator.card_data.thorns = 3
	var attacker := unit(false, 3, 1, 1)
	game.resolve_single_strike(attacker, retaliator, false)
	game.resolve_blood_pact()
	check(retaliator.is_alive() and not attacker.is_alive(), "retaliation kills satisfy Blood Pact")
	var inspected := unit(true, 3, 2, 5)
	director.inspect_board_card(inspected)
	check(director.screen == "inspect", "board inspection opens")
	check(director.inspected_face.get_parent().get_parent() is HBoxContainer, "description uses a horizontal layout")
	await capture("inspect")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	director._input(release)
	check(director.modal.visible and paused, "releasing inspection keeps it latched")
	director.dismiss_inspection()
	check(not director.modal.visible and not paused, "dismissal resumes battle")
	director.begin_inspect_hold(inspected)
	director._input(release)
	await create_timer(0.4).timeout
	check(not director.modal.visible, "a short press cannot open inspection later")
	game.set_view(game.View.BOARD)
	game._process(0)
	check(game.is_hand_tucked and game.hovered_hand_card == null, "overhead hides hand and disables hover")
	game.set_view(game.View.DESK)
	director.show_debug()
	unlock_debug(director)
	check(director.screen == "debug" and paused, "debug panel pauses a stable player turn")
	var fields = director.content.find_children("*", "SpinBox", true, false)
	check(fields.size() == 9, "debug exposes eight resource fields and a status amount")
	fields[7].value = 2
	await capture("debug")
	fields[2].value = 5
	fields[3].value = 30
	for button in director.content.find_children("*", "Button", true, false):
		if button.text == "Apply values": button.pressed.emit()
	check(game.energy_cap == 5 and game.preparedness == 5, "debug energy is clamped to capacity")
	check(game.plans.tokens == 2, "debug applies bounded Plans")
	director.show_title()
	check(not director.content.find_children("*", "Button", true, false).any(func(b): return b.text == "How to play"), "title no longer offers How to Play")
	await capture("title")
	director.persistence.discard()
	await create_timer(1.0).timeout
	if failures == 0: print("PASS: October 16 section 3 rules, inspection, debug, starter and overhead behavior")
	quit(1 if failures else 0)

func unlock_debug(owner_director: Node = null) -> void:
	var owner: Node = owner_director if owner_director != null else game.run_director
	check(owner.screen == "debug_password", "debug requires password dialog")
	var field: LineEdit = owner.content.get_node("DebugPassword")
	check(field.secret, "debug password is masked")
	field.text = "*****"
	field.text_submitted.emit(field.text)
