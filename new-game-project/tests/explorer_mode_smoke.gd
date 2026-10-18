extends SceneTree
var game: Node
var director: Node
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)
func fixture() -> void:
	paused = false
	game.clear_battle()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.player_hp = game.hero_max_hp()
	game.enemy_hp = 20
func unit(side: String, element: String, lane: int, health: int) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":side, "name":side, "type":side, "element":element, "cost":1, "attack":2, "health":health})
	card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	return card
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/unified_" + name + ".png")
func run() -> void:
	root.size = Vector2i(1366, 768)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.discard()
	director.show_title()
	check(director.content.find_child("RunModeChoice", true, false) == null, "title has no mode selector")
	await create_timer(0.3).timeout
	await capture("title")
	director.new_run()
	check(game.player_hp == 20 and game.hero_max_hp() == 20, "Steve starts at 20/20")
	fixture()
	for i in 4: game._damage_side(true, 1)
	check(game.player_hp == 16, "four one-point hits cost four HP")
	game.player_barrier = 4
	game._damage_side(true, 4)
	check(game.player_hp == 16 and game.player_barrier == 0, "barrier blocks ordinary damage")
	game.player_barrier = 4
	game._damage_side(true, 4, true)
	check(game.player_hp == 12 and game.player_barrier == 4, "bypass damage retains standard rules")
	game.player_barrier = 0
	game.player_buffs.damage_taken = 1
	game._damage_side(true, 4)
	check(game.player_hp == 6, "vulnerability still increases damage once")
	game.player_buffs.clear()
	game.player_hp = 19
	check(director.healing_gain(7) == 1, "healing preview caps at twenty")
	director.coins = 100
	director.buy_heal()
	check(game.player_hp == 20, "shop healing caps at twenty")
	director.screen = ""
	director.modal.hide()
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	director._input(key)
	unlock_debug()
	check(director.screen == "debug" and paused, "F3 still opens debug during the player turn")
	var fields = director.content.find_children("*", "SpinBox", true, false)
	check(fields[0].max_value == 20, "debug HP respects twenty HP")
	await capture("debug")
	fields[0].value = 18
	fields[2].value = 7
	fields[3].value = 6
	fields[6].value = 123
	for button in director.content.find_children("*", "Button", true, false):
		if button.text == "Apply values": button.pressed.emit()
	check(game.player_hp == 18 and game.preparedness == 6 and director.coins == 123, "debug HP, energy and supplies still apply")
	director.close_modal()
	game.deck.assign(director.collection.duplicate(true))
	game.draw_cards(3)
	game.turn = 3
	director.floor_number = 1
	game.encounter_kind = "battle"
	check(director.persistence.checkpoint(), "stable battle checkpoints save")
	var saved: Dictionary = director.persistence.read_save()
	check(not saved.game.has("explorer_mode") and not saved.game.has("explorer_damage_remainder"), "new saves omit mode state")
	var expected_deck: Array = saved.game.deck.duplicate(true)
	var expected_hand: Array = game.get_hand_cards().map(func(card): return card.card_data.duplicate(true))
	for hp in [27, 12, 0]:
		saved.game.player_hp = hp
		saved.game.explorer_mode = true
		saved.game.explorer_damage_remainder = 2
		write_save(saved)
		check(director.persistence.resume(), "legacy save resumes")
		check(game.player_hp == mini(20, hp), "legacy HP clamps without healing or resurrection")
		check(game.deck == expected_deck and game.get_hand_cards().map(func(card): return card.card_data) == expected_hand, "Continue preserves deck and hand order")
		check(director.floor_number == 1 and game.turn == 3, "Continue preserves floor and round")
		check(director.collection == saved.director.collection and director.rooms == saved.director.rooms, "Continue preserves collection and map")
		game.tension = 10
		check(game.enemy_action_limit() == 1, "resumed round three has one action")
		game.turn = 4
		check(game.enemy_action_limit() == 2, "resumed round four has two actions")
	saved.game.erase("explorer_mode")
	saved.game.erase("explorer_damage_remainder")
	saved.game.player_hp = 18
	write_save(saved)
	check(director.persistence.resume() and game.player_hp == 18, "old ordinary save retains injured HP")
	game._damage_side(true, 1)
	check(game.player_hp == 17, "obsolete mode keys leave no fractional reduction")
	check(director.persistence.checkpoint(), "resumed legacy run checkpoints")
	var migrated: Dictionary = director.persistence.read_save()
	check(not migrated.game.has("explorer_mode") and not migrated.game.has("explorer_damage_remainder"), "migrated saves omit obsolete mode keys")
	director.show_title()
	await create_timer(0.3).timeout
	check(director.content.find_child("RunModeChoice", true, false) == null, "Continue title has no mode selector")
	for control in director.content.find_children("*", "Button", true, false):
		check(root.get_visible_rect().encloses(control.get_global_rect()), "saved-run title controls remain on screen")
	for label in director.content.find_children("*", "Label", true, false):
		check(not "EXPLORER" in label.text.to_upper() and label.text != "STANDARD", "title has no mode badge")
	await capture("saved_title")
	fixture()
	game._damage_side(true, 4)
	check(game.player_hp == 16, "hero damage is unchanged")
	var blocker = unit("response", "brace", 0, 10)
	var threat = unit("disaster", "fire", 0, 10)
	var before = int(blocker.card_data.health)
	game.resolve_attack(blocker, threat, true)
	check(int(blocker.card_data.health) == before, "a surviving defender does not automatically counterattack")
	game.resolve_attack(threat, blocker, false)
	check(int(blocker.card_data.health) == before - 4 and game.player_hp == 16, "ordinary advantageous second-phase attack occurs once and does not spill into hero HP")
	blocker.card_data.health = 1
	game.resolve_single_strike(threat, blocker, false)
	check(game.player_hp == 16, "overkill against a weak blocker does not hit the hero")
	game.resolve_single_strike(threat, null, false)
	check(game.player_hp == 14, "an unblocked hit uses raw attack, not a remembered type multiplier")
	var enemy_before: int = game.enemy_hp
	game._damage_side(false, 4)
	check(game.enemy_hp == enemy_before - 4, "enemy hero damage is unchanged")
	game.presentation.automated_choice = 0
	for floor_number in [1, 2, 3]:
		fixture()
		director.floor_number = floor_number
		game.start_encounter(director.collection, "boss" if floor_number == 3 else "battle", floor_number, 0)
		for i in 100:
			if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
			await create_timer(0.1).timeout
		if game.phase == game.Phase.PLAYER_DRAW:
			game._on_draw_button_pressed()
		check(game.can_player_act() and game.player_hp == 20 and game.hero_max_hp() == 20, "unified mode reaches floor " + str(floor_number))
		if floor_number == 3:
			check(is_instance_valid(game.final_boss), "Midnight Warden remains accessible")
			game._damage_side(true, 4, true)
			check(game.player_hp == 16, "Warden bypass damage uses standard rules")
	await capture("warden")
	director.new_run()
	check(game.player_hp == 20, "subsequent runs reset to twenty HP")
	director.persistence.discard()
	if failures: quit(1)
	else:
		print("PASS: unified title, standard damage, barriers, healing, legacy saves, round resume, F3 and floors 1-3/Warden")
		quit()

func write_save(saved: Dictionary) -> void:
	var file := FileAccess.open(director.persistence.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()

func unlock_debug(owner_director: Node = null) -> void:
	var owner: Node = owner_director if owner_director != null else game.run_director
	check(owner.screen == "debug_password", "debug requires password dialog")
	var field: LineEdit = owner.content.get_node("DebugPassword")
	check(field.secret, "debug password is masked")
	field.text = "*****"
	field.text_submitted.emit(field.text)
