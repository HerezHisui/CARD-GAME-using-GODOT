extends SceneTree
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func has_text(parent: Node, text: String) -> bool:
	for control in parent.find_children("*", "Control", true, false):
		if control is Label or control is Button or control is RichTextLabel:
			if text.to_lower() in control.text.to_lower(): return true
	return false

func battle() -> void:
	paused = false
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.new_run()
	director.show_map()
	check(not has_text(director.content, "rooms cleared"), "room count removed")
	check(not has_text(director.content, "DESTINATION"), "destination removed")
	check(not has_text(director.content, "SCHOOL OPERATIONS"), "school operations removed")
	director.show_menu()
	check(not has_text(director.content, "Armored reduces"), "menu explanations removed")
	check(not has_text(director.content, "JANITOR RUN"), "Janitor buff headings removed")
	check(not has_text(director.content, "Combat log"), "menu log removed")
	check(has_text(director.content, "Adaptations:"), "battle buff heading renamed")
	check(has_text(director.content, "Augmentations:"), "run buff heading renamed")
	director.show_deck()
	check(not has_text(director.content, "Response Graveyard"), "graveyard absent outside combat")
	check(has_text(director.content, "DECK"), "deck uses short heading")
	var original_collection: Array = director.collection.duplicate(true)
	director.collection.assign([{"name":"Composition fixture", "element":"evac", "utility":true}])
	var strip: String = director.status_text()
	check("HP 20/20" in strip and "Supplies 35" in strip, "status includes health and supplies")
	check("Evac 1" in strip and "Douse 0" in strip and "Utility 1" in strip, "composition shows present and absent types")
	director.coins += 5
	check("Supplies 40" in director.status_text(), "status tracks supply changes")
	director.collection.assign(original_collection)
	battle()
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	var ally = game.Card3DScene.instantiate()
	game.add_child(ally)
	ally.add_to_group("cards")
	ally.setup({"name":"UI fixture", "type":"response", "element":"evac", "cost":1,
		"attack":2, "health":5, "modifier":"armored", "effect":"rally_all"})
	ally.place_on_slot(game._response_slots()[0])
	ally.add_status("burn", 3)
	check(ally._status_row.has_node("Burn"), "status has an icon")
	check(ally._status_row.has_node("Armored"), "modifier has an icon")
	for i in 30: ally._add_effect_icon("fixture_%d" % i)
	check(ally._status_row.get_child_count() == 20, "effect grid has two bounded rows")
	check(ally._status_row.has_node("More"), "overflow has an indicator")
	director.inspect_board_card(ally)
	check(not has_text(director.content, "CARD INSPECTION"), "inspection heading removed")
	check(not has_text(director.content, "Click the card"), "inspection instructions removed")
	check(has_text(director.inspection_dossier, "Armored:"), "inspection retains modifier rules")
	check(has_text(director.inspection_dossier, "Burn 3:"), "inspection retains status rules and stacks")
	director.close_modal()
	game.set_view(game.View.DESK)
	game.apply_formation_effect(ally)
	check(game.in_board_view, "formation ability opens overhead")
	game.set_view(game.View.DESK)
	game.board_input.pick("Pick", [ally], func(_card): pass, Callable())
	check(game.in_board_view, "board selection opens overhead")
	game.board_input.cancel()
	check(not director.root.has_node("CombatLogButton"), "HUD log removed")
	director.show_battle_log()
	check(director.modal.visible and director.screen == "log", "L opens the combat log")
	director.show_battle_log()
	check(not director.modal.visible, "L closes the combat log")
	director.show_plans()
	check(not has_text(director.content, "Auto-save 2 energy"), "autosave indicator removed")
	director.close_modal()
	game._set_phase(game.Phase.PLAYER_DRAW, "Old instruction")
	check(game._phase_label.text == "Pick a card to draw", "draw instruction is concise")
	check(game.presentation.draw_reminder.visible, "draw phase starts reminder")
	await create_timer(0.20).timeout
	check(game.presentation.draw_reminder.modulate.a > 0.1, "reminder visibly pulses")
	game.add_card_to_hand({"name":"Draw fixture", "type":"response", "element":"evac",
		"cost":1, "attack":1, "health":1})
	game.deck.assign([director.collection[0].duplicate(true)])
	game.preparedness = 3
	var hand_size: int = game.get_hand_cards().size()
	game._on_draw_button_pressed()
	check(director.modal.visible and director.screen == "choice", "turn draw opens the deck picker")
	game.complete_draw_choice(game.deck[0])
	check(game.get_hand_cards().size() == hand_size + 1 and game.preparedness == 3, "picked draw is free")
	check(game.phase == game.Phase.PLAYER_PLAY, "draw completes")
	check(not game.presentation.draw_reminder.visible, "drawing stops reminder")
	game._set_phase(game.Phase.PLAYER_DRAW)
	check(game.presentation.draw_reminder.visible, "next draw phase restarts reminder")
	game._set_phase(game.Phase.GAME_OVER)
	check(not game.presentation.draw_reminder.visible, "leaving draw phase clears reminder")
	var hover_button: Button = director.menu_button
	hover_button.disabled = false
	hover_button.mouse_entered.emit()
	var fill := hover_button.get_theme_stylebox("normal") as StyleBoxFlat
	check(fill.bg_color != director.UI.ACTION, "hover color does not swap instantly")
	await create_timer(0.20).timeout
	check(fill.bg_color.is_equal_approx(director.UI.ACTION), "hover reaches red")
	hover_button.mouse_exited.emit()
	await create_timer(0.20).timeout
	check(fill.bg_color.is_equal_approx(director.UI.BACKGROUND), "exit returns to black")
	battle()
	game.plans.tokens = 2
	var energy: int = game.preparedness
	director.begin_tactic("brace")
	check(not game.board_input.action.is_empty(), "target tactic waits for a board click")
	check(game.plans.tokens == 2, "selection does not spend a Plan")
	await escape()
	check(game.board_input.action.is_empty(), "Esc cancels target selection")
	check(game.plans.tokens == 2 and game.preparedness == energy, "cancel preserves resources")
	check(game.plans.armed.is_empty(), "cancel does not arm a tactic")
	game.plans.unlock("extract")
	director.begin_tactic("extract")
	game.board_input.click_card(ally)
	check(game.board_input.action.get("kind") == "place", "extraction selects its destination on board")
	await escape()
	check(game.plans.tokens == 2 and game.plans.armed.is_empty(), "second-stage cancel preserves resources")
	director.begin_tactic("extract")
	game.board_input.click_card(ally)
	game.board_input.choose_slot(game._response_slots()[1])
	check(game.plans.tokens == 1, "confirming destination spends exactly one Plan")
	check(game.plans.armed.get("destination") == game._response_slots()[1], "confirmed extraction retains target")
	game.plans.reset()
	var utility = game.Card3DScene.instantiate()
	game.hand_container.add_child(utility)
	utility.add_to_group("cards")
	utility.setup({"name":"Target fixture", "type":"response", "element":"evac", "utility":true,
		"cost":1, "attack":0, "health":1, "effect":"rally"})
	utility.in_hand = true
	game.hand.append(utility)
	game.preparedness = 3
	check(game.try_utility(utility, game._response_slots()[2]), "target utility begins selection")
	await escape()
	check(game.preparedness == 3 and is_instance_valid(utility) and utility.in_hand, "utility cancel keeps card and energy")
	check(game.pending_utility == null and game.board_input.action.is_empty(), "utility cancel clears pending state")
	director.persistence.discard()
	print("OCT18 UI: %d failures" % failures)
	quit(1 if failures else 0)
