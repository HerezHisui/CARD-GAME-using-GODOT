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
			if text in control.text: return true
	return false

func battle() -> void:
	paused = false
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)

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
	director.show_deck()
	check(not has_text(director.content, "Response Graveyard"), "graveyard absent outside combat")
	check(has_text(director.content, "DECK"), "deck uses short heading")
	battle()
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	var ally = game.Card3DScene.instantiate()
	game.add_child(ally)
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
	director.show_plans()
	check(not has_text(director.content, "Auto-save 2 energy"), "autosave indicator removed")
	director.close_modal()
	game._set_phase(game.Phase.PLAYER_DRAW, "Old instruction")
	check(game._phase_label.text == "Pick a card to draw", "draw instruction is concise")
	director.persistence.discard()
	print("OCT18 UI: %d failures" % failures)
	quit(1 if failures else 0)
