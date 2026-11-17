extends SceneTree
## Janitor rule: CLOSING TIME and NIGHT SHIFT in boss rooms on floors 1 and 2, reached only through the test override.
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

func cataclysm_row() -> Dictionary:
	return {"id": "midnight_cataclysm", "name": "Midnight Cataclysm", "type": "disaster", "element": "fire",
		"cost_type": "sacrifice", "cost": 3, "attack": 7, "health": 8, "modifier": "fierce"}

# Copies of Midnight Cataclysm across deck, hand and board.
func cataclysm_copies() -> int:
	var total := 0
	for item in game.enemy_evolution_deck + game.enemy_hand:
		if item.get("id", "") == "midnight_cataclysm": total += 1
	if BossRules.on_board(game, "midnight_cataclysm") >= 0: total += 1
	return total

# Real starter cards go into the hand through the game's own draw path. The last one is the newest.
func hand_of(count: int) -> Array:
	var starters: Array = director.character_deck(0)
	for i in count:
		var definition: Dictionary = starters[i].duplicate(true)
		definition.erase("locked_until")
		game.add_card_to_hand(definition)
	return game.get_hand_cards()

func locked(cards: Array, until: int) -> Array:
	return cards.filter(func(card): return int(card.card_data.get("locked_until", 0)) == until)

func sealed_count() -> int:
	return game.get_hand_cards().filter(func(card): return game.is_sealed(card.card_data)).size()

func fresh(override: Variant, floor_number: int = 1) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = floor_number
	game.encounter_kind = "boss"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.turn = 1
	game.enemy_max_hp = 28 if floor_number == 1 else 31
	game.enemy_hp = game.enemy_max_hp
	game._set_phase(game.Phase.PLAYER_PLAY)

func intent_panel() -> Control:
	return director.boss_intent.get_parent()

func label_fits(label: Label) -> bool:
	return label.get_line_count() * label.get_line_height() <= label.size.y

# Base and evolution card counts of a fresh encounter, hand included.
func deck_counts() -> Array:
	var base: int = game.enemy_deck.size() + game.enemy_hand.filter(func(c): return int(c.cost) == 0).size()
	var evolutions: int = game.enemy_evolution_deck.size() \
		+ game.enemy_hand.filter(func(c): return int(c.cost) > 0).size()
	return [base, evolutions]

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.start_character(0)
	Input.warp_mouse(Vector2(4, 4))
	check(not BossRules.JANITOR_ENABLED, "the janitor flag stays false")
	check(not BossRules.GUARDIAN_ENABLED, "the guardian flag stays false")

	# 16. The data parses, the janitor row is whole, and the guardian row is unchanged from the Guardian build.
	var file := FileAccess.open("res://data/bosses.json", FileAccess.READ)
	var json := JSON.new()
	check(file != null and json.parse(file.get_as_text()) == OK, "bosses.json parses")
	var data: Dictionary = json.data if typeof(json.data) == TYPE_DICTIONARY else {}
	var row: Dictionary = data.get("janitor", {})
	check(row.has("rule") and row.has("phases") and row.has("floors"), "janitor row has rule, phases and floors")
	var guardian_text := '{"name": "HALLWAY GUARDIAN", "room": "elite",' \
		+ ' "rule": {"id": "checkpoint", "barrier": 1, "lanes": [0, 1, 2, 3]},' \
		+ ' "phases": [{"name": "PATROL", "hp_at_or_below": 1.0},' \
		+ ' {"name": "LOCKDOWN", "hp_at_or_below": 0.5, "to_hand": "elite_guardian", "stay_on": "elite_guardian"}],' \
		+ ' "replaces_random_modifiers": true}'
	var guardian_row: Variant = JSON.parse_string(guardian_text)
	check(guardian_row is Dictionary and data.get("guardian", {}) == guardian_row,
		"the guardian row is unchanged, key for key")

	# 1. Override null: no rule, no lock over four preparations, intent panel hidden.
	await fresh(null)
	var plain_hand := hand_of(3)
	check(BossRules.boss_id(game) == "", "flag off: no boss rule in a floor 1 boss room")
	for round_number in [1, 2, 3, 4]:
		game.turn = round_number
		game.continue_round()
	check(plain_hand.all(func(card): return not card.card_data.has("locked_until")),
		"flag off: no hand card is locked over four round preparations")
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.board_input.clear()
	await wait_frames(2)
	check(not intent_panel().visible, "flag off: the intent panel stays hidden in a boss room")

	# 2 and 5. Override on, but the wrong room: no rule.
	game.boss_rule_override = "janitor"
	for kind in ["battle", "elite", "versus", "tutorial"]:
		game.encounter_kind = kind
		check(BossRules.boss_id(game) == "", "no janitor rule in a %s room" % kind)
		check(not BossRules.blocks_random_modifiers(game), "random modifiers stay in a %s room" % kind)
	game.encounter_kind = "boss"
	check(BossRules.boss_id(game) == "janitor", "override turns the rule on in a floor 1 boss room")
	game.boss_rule_override = "guardian"
	check(BossRules.boss_id(game) == "", "override guardian in a boss room: no rule")
	game.boss_rule_override = "janitor"
	director.floor_number = 3
	check(BossRules.boss_id(game) == "", "floor 3 is not in the janitor's floors")
	director.floor_number = 1

	# 6. Day Shift: every second round is a lock round.
	await fresh("janitor")
	var day: Array = []
	for round_number in range(1, 7): day.append(BossRules.lock_round(game, round_number))
	check(day == [false, true, false, true, false, true], "day shift lock rounds 1 to 6 (got %s)" % [day])
	check(BossRules.every(game) == 2, "day shift: every 2")

	# 7. Round 2 preparation locks only the newest card, until round 4.
	await fresh("janitor")
	var cards := hand_of(3)
	var log_size: int = game.battle_log.size()
	game.turn = 2
	game.continue_round()
	check(locked(cards, 4).size() == 1 and locked(cards, 4)[0] == cards[2], "only the last card is locked until 4")
	check(not cards[0].card_data.has("locked_until") and not cards[1].card_data.has("locked_until"),
		"the other cards stay open")
	var closing_lines: Array = game.battle_log.slice(log_size).filter(
		func(line): return line.begins_with("Round 2 | CLOSING TIME: ") and line.ends_with(" is locked for 2 rounds."))
	check(closing_lines.size() == 1, "Closing Time is logged once")
	check(game.is_sealed(cards[2].card_data), "the locked card cannot be played in round 2")
	game.turn = 3
	check(game.is_sealed(cards[2].card_data), "the locked card cannot be played in round 3")
	game.turn = 4
	check(not game.is_sealed(cards[2].card_data), "the locked card can be played in round 4")

	# 8. A second preparation in the same round locks nothing more.
	game.turn = 2
	BossRules.prepare_round(game)
	check(sealed_count() == 1 and locked(cards, 4).size() == 1, "second preparation: still one locked card")

	# 9. The newest card is already sealed by something else: the next one from the end is locked.
	await fresh("janitor")
	cards = hand_of(3)
	cards[2].card_data.locked_until = 3
	game.turn = 2
	BossRules.prepare_round(game)
	check(locked(cards, 4).size() == 1 and locked(cards, 4)[0] == cards[1], "the next unsealed card is locked")
	check(int(cards[2].card_data.locked_until) == 3, "the other seal is not changed")

	# 10. An empty hand, and a fully sealed hand: nothing happens.
	await fresh("janitor")
	game.turn = 2
	log_size = game.battle_log.size()
	BossRules.prepare_round(game)
	check(game.battle_log.size() == log_size, "empty hand: no log line")
	cards = hand_of(2)
	for card in cards: card.card_data.locked_until = 9
	log_size = game.battle_log.size()
	BossRules.prepare_round(game)
	check(cards.all(func(card): return int(card.card_data.locked_until) == 9), "sealed hand: no lock changes")
	check(game.battle_log.size() == log_size, "sealed hand: no log line")

	# 11. Phase follows HP.
	await fresh("janitor")
	game.enemy_hp = 15
	check(BossRules.phase(game) == 1, "phase 1 above half HP")
	game.enemy_hp = ceili(28 / 2.0)
	check(BossRules.phase(game) == 2, "phase 2 at half HP")

	# 12. Night Shift moves Midnight Cataclysm from the evolution deck to the hand once.
	await fresh("janitor")
	game.enemy_evolution_deck.append({"id": "flash_flood", "name": "Flash Flood", "cost": 1})
	game.enemy_evolution_deck.append(cataclysm_row())
	game.enemy_hp = 14
	game.turn = 1
	BossRules.prepare_round(game)
	check(game.enemy_hand.any(func(item): return item.get("id", "") == "midnight_cataclysm"),
		"Midnight Cataclysm moves to the hand")
	check(game.enemy_evolution_deck.size() == 1, "other evolutions stay in the deck")
	check(game.battle_log.has("Round 1 | NIGHT SHIFT: Midnight Cataclysm is called."), "Night Shift is logged")
	var hand_size: int = game.enemy_hand.size()
	game.turn = 2
	BossRules.prepare_round(game)
	check(game.enemy_hand.size() == hand_size and cataclysm_copies() == 1, "second preparation moves nothing")
	await fresh("janitor")
	game.enemy_hand.append(cataclysm_row())
	game.enemy_hp = 14
	BossRules.prepare_round(game)
	check(game.enemy_hand.size() == 1 and cataclysm_copies() == 1, "Cataclysm already in hand: no copy")
	await fresh("janitor")
	unit("midnight_cataclysm", 2)
	game.enemy_hp = 14
	BossRules.prepare_round(game)
	check(game.enemy_hand.is_empty() and cataclysm_copies() == 1, "Cataclysm already on board: no copy")

	# 13. Night Shift: floor 1 keeps every second round, floor 2 locks every round.
	await fresh("janitor", 1)
	game.enemy_hp = 14
	var night_one: Array = []
	for round_number in range(1, 7): night_one.append(BossRules.lock_round(game, round_number))
	check(night_one == [false, true, false, true, false, true], "floor 1 night shift (got %s)" % [night_one])
	await fresh("janitor", 2)
	game.enemy_hp = 15
	check(BossRules.phase(game) == 2 and BossRules.every(game) == 1, "floor 2 night shift: every 1")
	check(BossRules.lock_round(game, 3) and BossRules.lock_round(game, 4) and BossRules.lock_round(game, 5),
		"floor 2 night shift: rounds 3, 4 and 5 lock")
	hand_of(5)
	for round_number in [3, 4, 5]:
		game.turn = round_number
		game.continue_round()
	check(sealed_count() == 2, "floor 2 night shift: two cards sealed at once (got %d)" % sealed_count())

	# 14. Random modifiers are off.
	await fresh(null)
	var control := unit("control", 1)
	game.turn = 7
	for i in 20: game._apply_round_modifiers()
	check(not control.modifiers.is_empty(), "flag off: round 7 still adds random modifiers")
	await fresh("janitor")
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
	await fresh("janitor")
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

	# 15. The intent panel shows the rule, and every line fits at 1280 x 720.
	root.size = Vector2i(1280, 720)
	await fresh("janitor")
	game.board_input.clear()
	var label: Label = director.boss_intent
	await wait_frames(2)
	check(intent_panel().visible, "rule on: the intent panel shows")
	check(label.text.contains("CLOSING TIME next round"), "round 1 warns one round early (got '%s')" % label.text)
	check(label_fits(label), "round 1 text fits the panel")
	game.turn = 2
	await wait_frames(2)
	check(label.text.contains("CLOSING TIME: one card is locked. Next lock in 2 rounds."),
		"round 2 says a card is locked (got '%s')" % label.text)
	check(label_fits(label), "round 2 text fits the panel")
	game.enemy_hp = 14
	await wait_frames(2)
	check(label.text.begins_with("NIGHT SHIFT. CLOSING TIME"), "floor 1 night shift prefix (got '%s')" % label.text)
	check(label_fits(label), "floor 1 night shift text fits the panel")
	game.turn = 3
	await wait_frames(2)
	check(label.text.begins_with("NIGHT SHIFT. CLOSING TIME next round"), "floor 1 night shift warning")
	check(label_fits(label), "floor 1 night shift warning fits the panel")
	director.floor_number = 2
	game.enemy_max_hp = 31
	game.enemy_hp = 15
	await wait_frames(2)
	check(label.text == "NIGHT SHIFT: CLOSING TIME every round. Your newest card is locked for 2 rounds.",
		"floor 2 night shift: every round (got '%s')" % label.text)
	check(label_fits(label), "floor 2 night shift text fits the panel")
	check(game._enemy_hp_ui.get_node("Caption").tooltip_text == "", "caption tooltip stays Warden only")
	director.battle_active = false
	await wait_frames(2)
	check(not intent_panel().visible, "the panel hides outside a battle")
	root.size = Vector2i(1440, 900)
	await wait_frames(2)

	# 4. Real boss encounters keep today's HP and deck sizes with the rule on.
	director.battle_active = true
	game.disaster_is_human = false
	for floor_number in [1, 2]:
		director.floor_number = floor_number
		game.boss_rule_override = null
		game.start_encounter(director.character_deck(0), "boss", floor_number, 0)
		var today := deck_counts()
		await wait_frames(2)
		game.boss_rule_override = "janitor"
		game.start_encounter(director.character_deck(0), "boss", floor_number, 0)
		check(BossRules.boss_id(game) == "janitor", "floor %d boss room: rule on" % floor_number)
		check(game.enemy_max_hp == (28 if floor_number == 1 else 31), "floor %d boss HP stays" % floor_number)
		check(deck_counts() == today, "floor %d boss decks stay %s (got %s)" % [floor_number, today, deck_counts()])
		await wait_frames(2)

	# 3. Floor 3: the Warden is there, the Janitor's rule is not, and the panel shows the Warden.
	director.floor_number = 3
	game.boss_rule_override = "janitor"
	game.start_encounter(director.character_deck(0), "boss", 3, 0)
	check(is_instance_valid(game.final_boss), "floor 3 boss room has the Warden")
	check(BossRules.boss_id(game) == "", "floor 3 with the Warden: no janitor rule")
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	game.board_input.clear()
	await wait_frames(2)
	check(not label.text.contains("CLOSING TIME"), "the Warden's intent shows, not Closing Time")
	check(label.text == game.final_boss.intent(), "the panel shows the Warden's intent (got '%s')" % label.text)

	# 17. 120 battle frames with the rule on, after the coin toss.
	director.floor_number = 1
	game.boss_rule_override = "janitor"
	game.start_encounter(director.character_deck(0), "boss", 1, 0)
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	check(game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY],
		"the live boss battle reaches the player turn")
	await wait_frames(120)
	check(BossRules.boss_id(game) == "janitor" and game.encounter_kind == "boss", "rule stays on in the live battle")
	check(game.phase != game.Phase.GAME_OVER and director.battle_active, "the live battle is still running")

	if failures > 0:
		print("BOSS JANITOR: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: boss janitor %d checks" % checks)
	quit(0)
