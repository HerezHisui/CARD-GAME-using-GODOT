extends SceneTree
## Hallway Guardian rule: CHECKPOINT and LOCKDOWN in elite rooms, reached only through the test override.
const BossRules = preload("res://scripts/boss_rules.gd")
var game: Node
var director: Node
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func wait_frames(count: int) -> void:
	for i in mini(count, 600): await process_frame

func unit(id: String, lane: int) -> Node:
	var data := {"id": id, "name": id.capitalize(), "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 5}
	var slot: Node3D = game._threat_slots()[lane]
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup(data)
	result.in_hand = false
	result.current_slot = slot
	result.global_position = slot.global_position + Vector3(0, 0.02, 0)
	result._set_overlay(false)
	return result

func barrier(card: Node) -> int:
	return int(card.statuses.get("barrier", 0))

func guardian_row() -> Dictionary:
	return {"id": "elite_guardian", "name": "Hallway Guardian", "type": "disaster", "element": "fire",
		"cost_type": "sacrifice", "cost": 2, "attack": 5, "health": 5, "modifier": "armored"}

# Copies of the Guardian card across deck, hand and board.
func guardian_copies() -> int:
	var total := 0
	for item in game.enemy_evolution_deck + game.enemy_hand:
		if item.get("id", "") == "elite_guardian": total += 1
	if BossRules.on_board(game, "elite_guardian") >= 0: total += 1
	return total

func fresh(override: Variant) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.encounter_kind = "elite"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.turn = 1
	game.enemy_max_hp = 24
	game.enemy_hp = 24
	game._set_phase(game.Phase.PLAYER_PLAY)

func intent_panel() -> Control:
	return director.boss_intent.get_parent()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.start_character(0)
	Input.warp_mouse(Vector2(4, 4))
	check(not BossRules.GUARDIAN_ENABLED, "the guardian flag stays false")

	# 14. The data row parses and every lane is on the board.
	var file := FileAccess.open("res://data/bosses.json", FileAccess.READ)
	var json := JSON.new()
	check(file != null and json.parse(file.get_as_text()) == OK, "bosses.json parses")
	var row: Dictionary = json.data.get("guardian", {}) if typeof(json.data) == TYPE_DICTIONARY else {}
	check(row.has("rule") and row.has("phases"), "guardian row has rule and phases")
	var lanes: Array = row.get("rule", {}).get("lanes", [])
	check(not lanes.is_empty() and lanes.all(func(lane): return int(lane) >= 0 and int(lane) <= 3),
		"every checkpoint lane is 0 to 3")
	check(BossRules.rows().has("guardian"), "the guardian row is read")

	# 1. Override null: no rule, no Barrier over three preparations, intent panel hidden.
	await fresh(null)
	var plain := unit("plain", 0)
	var plain_two := unit("plain_two", 1)
	var plain_three := unit("plain_three", 2)
	check(BossRules.boss_id(game) == "", "flag off: no boss rule")
	for round_number in [1, 2, 3]:
		game.turn = round_number
		game.continue_round()
	check(barrier(plain) == 0 and barrier(plain_two) == 0 and barrier(plain_three) == 0,
		"flag off: no unit gains Barrier over three round preparations")
	game._set_phase(game.Phase.PLAYER_PLAY)
	await wait_frames(2)
	check(not intent_panel().visible, "flag off: the intent panel stays hidden in an elite room")

	# 2. Override on, but not an elite room: no rule.
	game.boss_rule_override = "guardian"
	for kind in ["battle", "boss", "versus", "tutorial"]:
		game.encounter_kind = kind
		check(BossRules.boss_id(game) == "", "no rule in a %s room" % kind)
		check(not BossRules.blocks_random_modifiers(game), "random modifiers stay in a %s room" % kind)
	game.encounter_kind = "elite"
	check(BossRules.boss_id(game) == "guardian", "override turns the rule on in an elite room")
	game.boss_rule_override = "janitor"
	check(BossRules.boss_id(game) == "", "another boss id does not turn the guardian on")

	# 4. The checkpoint walks lane by lane.
	await fresh("guardian")
	var walked: Array = []
	for round_number in range(1, 7):
		game.turn = round_number
		walked.append(BossRules.checkpoint_lane(game))
	check(walked == [0, 1, 2, 3, 0, 1], "checkpoint lanes for rounds 1 to 6 (got %s)" % [walked])

	# 5. The unit in the checkpoint lane gains Barrier 1 through the real round preparation.
	await fresh("guardian")
	var first := unit("first", 0)
	var second := unit("second", 1)
	game.turn = 1
	game.continue_round()
	check(barrier(first) == 1, "checkpoint unit gains Barrier 1")
	check(barrier(second) == 0, "a unit in another lane gains nothing")
	check(game.battle_log.any(func(line): return line.contains("gains 1 Barrier")), "Barrier is logged")

	# 6. No stacking: a unit that still has Barrier keeps Barrier 1.
	BossRules.prepare_round(game)
	game.turn = 5
	game.continue_round()
	check(barrier(first) == 1, "Barrier never stacks above 1")

	# 7. An empty checkpoint lane does nothing.
	game.turn = 3
	var log_size: int = game.battle_log.size()
	BossRules.prepare_round(game)
	check(barrier(first) == 1 and barrier(second) == 0, "empty checkpoint lane changes no unit")
	check(game.battle_log.size() == log_size, "empty checkpoint lane logs nothing")

	# 8. Phase follows HP.
	await fresh("guardian")
	game.enemy_hp = 13
	check(BossRules.phase(game) == 1, "phase 1 above half HP")
	game.enemy_hp = ceili(24 / 2.0)
	check(BossRules.phase(game) == 2, "phase 2 at half HP")
	game.enemy_hp = 1
	check(BossRules.phase(game) == 2, "phase 2 near zero HP")
	game.enemy_max_hp = 27
	game.enemy_hp = 14
	check(BossRules.phase(game) == 1, "floor 2: 14 of 27 is above half")
	game.enemy_hp = 13
	check(BossRules.phase(game) == 2, "floor 2: 13 of 27 is at or below half")

	# 9. Lockdown moves the Guardian card from the evolution deck to the hand once.
	await fresh("guardian")
	game.enemy_evolution_deck.append({"id": "flash_flood", "name": "Flash Flood", "cost": 1})
	game.enemy_evolution_deck.append(guardian_row())
	game.enemy_hp = 12
	BossRules.prepare_round(game)
	check(game.enemy_hand.any(func(item): return item.get("id", "") == "elite_guardian"), "Guardian moves to the hand")
	check(not game.enemy_evolution_deck.any(func(item): return item.get("id", "") == "elite_guardian"),
		"Guardian leaves the evolution deck")
	check(game.enemy_evolution_deck.size() == 1, "other evolutions stay in the deck")
	check(game.battle_log.any(func(line): return line.contains("LOCKDOWN: the Hallway Guardian is called.")),
		"Lockdown is logged")
	var hand_size: int = game.enemy_hand.size()
	game.turn = 2
	BossRules.prepare_round(game)
	check(game.enemy_hand.size() == hand_size and guardian_copies() == 1, "second preparation moves nothing")

	# 10. Already in the hand, or already on the board: nothing moves, no copy appears.
	await fresh("guardian")
	game.enemy_hand.append(guardian_row())
	game.enemy_hp = 12
	BossRules.prepare_round(game)
	check(game.enemy_hand.size() == 1 and guardian_copies() == 1, "Guardian already in hand: no copy")
	await fresh("guardian")
	var guard := unit("elite_guardian", 2)
	game.enemy_hp = 12
	BossRules.prepare_round(game)
	check(game.enemy_hand.is_empty() and guardian_copies() == 1, "Guardian already on board: no copy")

	# 11. Lockdown keeps the checkpoint on the Guardian's lane until it is destroyed.
	var stayed: Array = []
	for round_number in range(1, 7):
		game.turn = round_number
		stayed.append(BossRules.checkpoint_lane(game))
	check(stayed == [2, 2, 2, 2, 2, 2], "checkpoint stays on the Guardian lane (got %s)" % [stayed])
	check(barrier(guard) == 1, "the Guardian gets the checkpoint Barrier")
	guard.card_data.health = 0
	game.turn = 1
	check(BossRules.checkpoint_lane(game) == 0, "destroyed Guardian: the checkpoint walks again")
	game.turn = 4
	check(BossRules.checkpoint_lane(game) == 3, "destroyed Guardian: lane follows the round")

	# 12. Random modifiers are off.
	await fresh(null)
	var control := unit("control", 1)
	game.turn = 7
	for i in 20: game._apply_round_modifiers()
	check(not control.modifiers.is_empty(), "flag off: round 7 still adds random modifiers")
	await fresh("guardian")
	var target := unit("target", 1)
	game.turn = 7
	for i in 20: game._apply_round_modifiers()
	check(target.modifiers.is_empty(), "rule on: round 7 adds no random modifier")
	var defs: Array = []
	game.load_deck_from_json("res://data/disaster_deck.json", defs)
	var base: Dictionary = {}
	for item in defs:
		if int(item.cost) == 0 and not item.has("modifier"):
			base = item
			break
	check(not base.is_empty(), "a plain base card exists")
	await fresh("guardian")
	game.turn = 4
	var slot: Node3D = game._threat_slots()[0]
	var plays := 0
	var clean := 0
	for i in 8:
		var done := [false]
		var play := func() -> void:
			await game.disaster_play_base(base.duplicate(true), slot)
			done[0] = true
		play.call()
		for frame in 600:
			if done[0]: break
			await process_frame
		var played = game._get_card_in_slot(slot)
		if done[0] and played != null:
			plays += 1
			if played.modifiers.is_empty(): clean += 1
			played.remove_from_group("cards")
			played.queue_free()
		game._set_phase(game.Phase.PLAYER_PLAY)
		await process_frame
	check(plays == 8 and clean == 8, "eight base cards at round 4 have no modifier (%d of %d)" % [clean, plays])

	# 13. The intent panel shows the rule.
	await fresh("guardian")
	game.turn = 2
	game.board_input.clear()
	await wait_frames(2)
	var label: Label = director.boss_intent
	check(intent_panel().visible, "rule on: the intent panel shows")
	check(label.text.contains("CHECKPOINT") and label.text.contains("lane 2") and label.text.contains("Next: lane 3"),
		"phase 1 names this lane and the next, 1 to 4 (got '%s')" % label.text)
	check(label.get_line_count() * label.get_line_height() <= label.size.y, "phase 1 text fits the panel")
	check(game._enemy_hp_ui.get_node("Caption").tooltip_text == "", "caption tooltip stays Warden only")
	game.enemy_hp = 12
	await wait_frames(2)
	check(intent_panel().visible and label.text.contains("LOCKDOWN") and label.text.contains("is called"),
		"phase 2 shows Lockdown (got '%s')" % label.text)
	check(label.get_line_count() * label.get_line_height() <= label.size.y, "phase 2 text fits the panel")
	unit("elite_guardian", 3)
	await wait_frames(2)
	check(label.text.contains("LOCKDOWN") and label.text.contains("lane 4"),
		"phase 2 with the Guardian names its lane (got '%s')" % label.text)
	director.battle_active = false
	await wait_frames(2)
	check(not intent_panel().visible, "the panel hides outside a battle")

	# 3. A real elite encounter with the rule on keeps today's numbers.
	director.battle_active = true
	game.boss_rule_override = "guardian"
	game.disaster_is_human = false
	game.start_encounter(director.character_deck(0), "elite", 1, 0)
	var base_count: int = game.enemy_deck.size() + game.enemy_hand.filter(func(c): return int(c.cost) == 0).size()
	var evolution_count: int = game.enemy_evolution_deck.size() \
		+ game.enemy_hand.filter(func(c): return int(c.cost) > 0).size()
	check(game.enemy_max_hp == 24, "elite floor 1 HP stays 24")
	check(base_count == 21 and evolution_count == 14,
		"elite deck stays 21 base and 14 evolutions (got %d and %d)" % [base_count, evolution_count])

	# 15. 120 battle frames with the rule on, after the coin toss.
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	check(game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY],
		"the live elite battle reaches the player turn")
	await wait_frames(120)
	check(BossRules.boss_id(game) == "guardian" and game.encounter_kind == "elite", "rule stays on in the live battle")
	check(game.phase != game.Phase.GAME_OVER and director.battle_active, "the live battle is still running")

	if failures > 0:
		print("BOSS GUARDIAN: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: boss guardian %d checks" % checks)
	quit(0)
