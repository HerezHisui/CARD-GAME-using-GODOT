extends SceneTree
var game: Node
var director: Node
var failed_checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed_checks += 1
		push_error("FAILED: " + message)
		quit(1)
		assert(value, message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.turn = 1
	game.encounter_kind = "battle"
	game.player_hp = 20
	game.enemy_hp = 20
	game.preparedness = 10
	game.energy_cap = 10
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func card(data: Dictionary, slot: Node3D = null) -> Node:
	var node = game.Card3DScene.instantiate()
	game.add_child(node)
	node.add_to_group("cards")
	node.setup(data)
	if slot:
		node.current_slot = slot
		node.in_hand = false
	else:
		node.reparent(game.hand_parent())
		game.hand.append(node)
		game.arrange_hand_centered()
	return node

func data(name: String, side: String = "response") -> Dictionary:
	return {"id":name, "name":name, "type":side, "element":"brace" if side == "response" else "earthquake", "cost":1 if side == "response" else 0, "attack":1, "health":4}

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	fixture()
	game.set_process(false)
	var left = card(data("Left"))
	var right = card(data("Right"))
	var rest: Transform3D = game.hand_container.global_transform * Transform3D(right.get_meta("hand_basis"), right.get_meta("hand_pos"))
	var mouse: Vector2 = game.camera.unproject_position(rest.origin)
	check(game.card_at_hand_position(mouse) == right, "topmost resting footprint wins overlapping hand picking")
	game.update_hand_hover(mouse)
	check(right.is_hovered and not left.is_hovered, "only one card rises")
	if right._tween: right._tween.kill()
	right.position = right.get_meta("hand_pos") + right.HOVER_LIFT
	for i in range(60): game.update_hand_hover(mouse)
	check(right.is_hovered and game.hovered_hand_card == right, "lift does not change hit region or flicker")
	await capture("stable_hover")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = game.camera.unproject_position(right.global_position)
	check(game.card_at_hand_position(press.position) == right, "raised face remains clickable above its resting footprint")
	game._unhandled_input(press)
	left._on_mouse_entered()
	game.update_hand_hover(game.camera.unproject_position(left.global_position))
	check(right.is_dragging and game.dragged_hand_card == right and not left.is_hovered and not right.is_hovered, "hover is suppressed while carrying a card")
	left._start_drag()
	check(not left.is_dragging, "only one card can be dragged")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	right._input(cancel)
	check(not right.is_dragging and game.dragged_hand_card == null and right.get_parent() == game.hand_parent(), "right-click cancellation restores hand and releases hover lock")
	game.update_hand_hover(mouse)
	check(game.hovered_hand_card != null, "hover resumes after cancellation")
	director.show_deck()
	check(game.hovered_hand_card == null and not left.is_hovered and not right.is_hovered, "opening UI clears hovered cards")
	director.close_modal()
	fixture()
	var doomed = card(data("Destroyed"), game._response_slots()[0])
	doomed.take_damage(99)
	check(game.player_graveyard.size() == 1 and game.player_graveyard[0].graveyard_reason == "Destroyed", "destroyed unit enters response graveyard")
	game.record_graveyard(doomed, "Destroyed")
	check(game.player_graveyard.size() == 1, "same node never enters graveyard twice")
	var second = card(data("Destroyed"), game._response_slots()[1])
	second.take_damage(99)
	check(game.player_graveyard.size() == 2, "separate copies are tracked separately")
	var sacrifice = card(data("Sacrifice", "disaster"), game._threat_slots()[0])
	await sacrifice.sacrifice_dissolve()
	check(game.enemy_graveyard.size() == 1 and game.enemy_graveyard[0].graveyard_reason == "Sacrificed", "evolution sacrifice enters Janitor graveyard")
	var spell_data := data("Cache")
	spell_data.utility = true
	spell_data.effect = "draw"
	var spell = card(spell_data)
	game.deck.append(data("Drawn"))
	check(game.try_utility(spell, game._response_slots()[3]), "cast utility succeeds")
	check(game.player_graveyard.size() == 3 and game.player_graveyard[2].graveyard_reason == "Cast", "cast spell enters graveyard")
	game.enemy_utility({"id":"Tax", "name":"Tax", "type":"disaster", "element":"flood", "cost":0, "attack":0, "health":1, "utility":true, "effect":"tax"})
	check(game.enemy_graveyard.size() == 2, "enemy spell enters its own graveyard")
	var failed := data("Failed Exit")
	failed.utility = true
	failed.effect = "move"
	var failed_spell = card(failed)
	check(not game.try_utility(failed_spell, game._response_slots()[3]) and game.player_graveyard.size() == 3, "failed spell remains in hand, outside graveyard")
	director.show_deck()
	director.show_graveyard()
	check(paused and director.viewed_cards.size() == 3, "graveyard pauses and displays response history")
	director.change_sort(0, false)
	director.reverse_sort(false)
	await capture("response_graveyard")
	director.deck_cards(game.enemy_graveyard)
	check(director.viewed_cards.size() == 2, "Janitor graveyard can be viewed")
	await capture("janitor_graveyard")
	director.close_modal()
	check(not paused, "closing graveyard resumes battle")
	game.clear_battle(true)
	check(game.player_graveyard.size() == 3, "end-of-boss cleanup preserves graveyard for results")
	game.clear_battle()
	check(game.player_graveyard.is_empty() and game.enemy_graveyard.is_empty(), "new encounter clears both graveyards")
	fixture()
	game.tension = 10
	check(game.enemy_action_limit() == 2, "regular encounters play two actions")
	game.enemy_buffs.energy = 10
	check(game.enemy_action_limit() == 4, "regular adaptation action cap is four")
	game.encounter_kind = "boss"
	check(game.enemy_action_limit() == 5, "boss action cap unchanged")
	fixture()
	game.turn = 2
	game.tension = 3
	for i in range(4): card(data("Small", "disaster"), game._threat_slots()[i])
	game.enemy_hand.append({"name":"Evolution", "type":"disaster", "element":"earthquake", "cost":1, "attack":6, "health":7})
	await game._enemy_turn()
	check(game.enemy_graveyard.is_empty() and game.enemy_hand.size() == 1, "regular AI does not rush early evolutions")
	game.turn = 3
	game.tension = 3
	await game._enemy_turn()
	check(game.enemy_graveyard.size() == 1 and game.enemy_hand.is_empty(), "regular AI can still make worthwhile later evolutions")
	game.start_encounter(director.character_deck(0), "battle", 1, 0)
	check(game.enemy_max_hp == 18 and game.enemy_deck.size() + game.enemy_hand.filter(func(card): return int(card.cost) == 0).size() == 18, "normal health and reserve nerfs")
	check(game.enemy_evolution_deck.size() + game.enemy_hand.filter(func(card): return int(card.cost) > 0).size() <= 8 and game.enemy_evolution_deck.all(func(d): return int(d.cost) <= 2), "normal reserves exclude apex evolutions")
	if failed_checks > 0:
		quit(1)
		return
	print("PASS: stable single-card hover/picking, drag suppression/cancel, modal reset, deaths/duplicates/sacrifices/spells/failures, separate sortable graveyards/reset, regular action/health/deck/evolution nerfs")
	quit(0)
