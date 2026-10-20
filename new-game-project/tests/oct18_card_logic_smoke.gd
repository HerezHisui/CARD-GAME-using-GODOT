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

func plan_display() -> void:
	fixture()
	var ally := unit("response", 0)
	game.plans.tokens = 1
	director.begin_tactic("coordinate")
	ally._on_mouse_entered()
	check(ally.plan_attack_bonus == 0 and ally.card_data.health == 8, "target hover has no gameplay effect")
	game.board_input.click_card(ally)
	check(ally.plan_attack_bonus == 1 and ally._atk_label.text == "3", "arming shows the plan attack right away")
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
