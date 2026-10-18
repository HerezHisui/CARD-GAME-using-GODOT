extends SceneTree

var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	director.modal.hide()
	director.screen = ""
	director.battle_active = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 40
	game.player_first = true
	game.preparedness = 5
	game.energy_cap = 5
	game._set_phase(game.Phase.PLAYER_PLAY)

func unit(side: String = "response", lane: int = -1, data: Dictionary = {}) -> Node:
	var definition := {"id":"fixture", "name":"Fixture", "type":side, "element":"brace",
		"cost":1, "attack":2, "health":8}
	definition.merge(data, true)
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition)
	if lane >= 0:
		card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func placement() -> void:
	fixture()
	for view in [game.DESK_VIEW, game.BOARD_VIEW]:
		game._apply_view(view)
		for slot in game._response_slots():
			var point: Vector2 = game.camera.unproject_position(slot.global_position)
			check(game.slot_at_screen_position(point) == slot, "visible lane center selects the same lane")
	check(game.slot_at_screen_position(Vector2(-1000, -1000)) == null, "outside board rejects placement")

func draw_choice() -> void:
	fixture()
	var definition := {"id":"pick", "name":"Pick", "type":"response", "element":"evac",
		"cost":1, "attack":1, "health":1}
	game.deck.assign([definition])
	game._set_phase(game.Phase.PLAYER_DRAW)
	game._on_draw_button_pressed()
	check(director.modal.visible and director.screen == "choice", "draw opens the deck picker")
	check(game.preparedness == 5, "opening picker is free")
	director.close_modal()
	check(game.deck.size() == 1 and game.preparedness == 5, "cancel preserves draw and energy")
	game._on_draw_button_pressed()
	game.complete_draw_choice(definition)
	check(game.deck.is_empty() and game.get_hand_cards().size() == 1, "chosen card enters hand")
	check(game.preparedness == 4, "picking costs exactly one energy")
	game.complete_draw_choice(definition)
	check(game.preparedness == 4, "duplicate picker callback cannot charge again")
	grouped_draw_choice(definition)

func grouped_draw_choice(definition: Dictionary) -> void:
	fixture()
	var copies: Array[Dictionary] = []
	for serial in range(3):
		var copy := definition.duplicate(true)
		copy.acquired = serial
		copies.append(copy)
	var upgraded := definition.duplicate(true)
	upgraded.attack = 4
	upgraded.acquired = 3
	var costly := definition.duplicate(true)
	costly.cost = 3
	costly.acquired = 4
	var sealed := definition.duplicate(true)
	sealed.locked_until = game.turn + 1
	sealed.acquired = 5
	game.deck.assign(copies + [upgraded, costly, sealed])
	var before: Array = game.deck.duplicate(true)
	game._set_phase(game.Phase.PLAYER_DRAW)
	game._on_draw_button_pressed()
	var choices: Array = director.content.find_children("*", "Button", true, false).filter(func(button):
		return button.text.begins_with("Choose"))
	check(choices.size() == 3, "draw groups identical copies while keeping stat and cost variants separate")
	var grouped: Array = choices.filter(func(button): return button.text == "Choose · x3")
	check(grouped.size() == 1, "three copies with different acquisition numbers share one counted tile")
	check(game.deck == before and game.preparedness == 5, "grouping preserves deck order, definitions and energy")
	director.close_modal()
	check(game.deck == before and game.preparedness == 5, "canceling a grouped picker changes nothing")
	game._on_draw_button_pressed()
	grouped = director.content.find_children("*", "Button", true, false).filter(func(button):
		return button.text == "Choose · x3")
	if grouped.size() == 1:
		grouped[0].pressed.emit()
		check(game.get_hand_cards().size() == 1 and game.preparedness == 4,
			"a grouped tile still draws exactly one card for one energy")
		var drawn: Dictionary = game.get_hand_cards()[0].card_data
		check(drawn.acquired in [0, 1, 2], "the drawn card is an original member of the selected group")
		var remaining := before.filter(func(card): return card.acquired != drawn.acquired)
		check(game.deck == remaining, "only that represented copy is removed; other cards keep their order")
	fixture()
	director.choose_card("OTHER CHOICE", copies, func(_card): pass, director.close_modal)
	choices = director.content.find_children("*", "Button", true, false).filter(func(button):
		return button.text == "Choose")
	check(choices.size() == 3, "non-draw choice screens keep individual tiles and their callbacks")
	director.close_modal()

func plan_display() -> void:
	fixture()
	var ally := unit("response", 0)
	game.plans.tokens = 1
	director.begin_tactic("coordinate")
	ally._on_mouse_entered()
	check(ally.plan_attack_bonus == 0 and ally.card_data.health == 8, "target hover has no gameplay effect")
	game.board_input.click_card(ally)
	check(ally.plan_attack_bonus == 0, "arming does not apply a combat bonus early")
	game._set_phase(game.Phase.COMBAT)
	game.plans.apply_combat()
	check(ally._atk_label.text == "3", "plan attack displays synchronously")
	check(ally.art_sprite.modulate == Color.WHITE, "positive plan does not flash damage red")
	game.plans.finish_combat()
	check(ally._atk_label.text == "2", "expired plan displays synchronously")

func board_inspection() -> void:
	fixture()
	game._apply_view(game.BOARD_VIEW)
	game._set_phase(game.Phase.COMBAT)
	if game.camera_tween: game.camera_tween.kill()
	game._apply_view(game.BOARD_VIEW)
	var ally := unit("response", 0)
	await create_timer(0.5).timeout
	var point: Vector2 = game.camera.unproject_position(ally.global_position)
	check(game.card_at_board_position(point) == ally, "overhead picker finds a board card during combat")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await create_timer(0.4).timeout
	check(director.screen == "inspect", "overhead board hold opens inspection during combat")
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	director.close_modal()

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	placement()
	draw_choice()
	plan_display()
	await board_inspection()
	game.clear_battle()
	print("OCT18 CARD LOGIC: %d failures" % failures)
	quit(1 if failures else 0)
