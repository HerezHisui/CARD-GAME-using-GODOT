# Covers: Sage's Lab kit (leader_kits.gd) through game.plans: start, enemy picks, Eureka, screens, saves, Versus.
# The kit is reached only with game.leader_kit_override and game.plans.set_kit; the const flag stays false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const ALL_LAB := ["nick", "drip", "spark", "fume_hood", "lab_notes"]
const FILLER := {"name":"Filler", "type":"response", "element":"evac", "cost":1, "attack":1, "health":3}

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

# A battle on the player's turn, as leader_robin_smoke builds it, with the whole Lab kit owned.
func fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.set_kit("sage")
	game.plans.auto_save = true
	game.plans.unlocked.assign(ALL_LAB)
	game.plans.tokens = 2
	game.turn = 1
	game.player_hp = 20
	game.player_barrier = 0
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 6
	game.deck.clear()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func card(name: String, lane: int, health: int, side: String = "response", extra: Dictionary = {}) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	var type := "response" if side == "response" else "disaster"
	var data := {"name":name, "type":type, "element":"evac", "cost":1, "attack":2, "health":10}
	data.merge(extra, true)
	result.setup(data)
	result.in_hand = false
	var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
	result.current_slot = slots[lane]
	result.global_position = slots[lane].global_position
	result.card_data.health = health
	return result

func next_round() -> void:
	game.turn += 1
	game.plans.tokens = 2

func eureka_lines() -> int:
	return game.battle_log.filter(func(line): return "Eureka!" in str(line)).size()

func has_popup(unit: Node, text: String) -> bool:
	# Popups live on the board, not on the card; the card keeps a list of its own.
	return unit._live_popups.any(func(label): return is_instance_valid(label) and label.text == text)

func reagents(unit: Node) -> Array:
	return ["burn", "poison", "bleed"].map(func(status): return int(unit.statuses.get(status, 0)))

func click(control: Control) -> void:
	await click_at(control.get_global_rect().get_center())

func click_at(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)

func mouse_away() -> void:
	var move := InputEventMouseMotion.new()
	move.position = Vector2(4, 4)
	root.push_input(move, true)
	await process_frame

# Wait until the camera stops moving (board view), capped at 600 frames.
func camera_still() -> void:
	var last: Transform3D = game.camera.global_transform
	for i in 600:
		await process_frame
		var now: Transform3D = game.camera.global_transform
		if i > 5 and now.is_equal_approx(last): return
		last = now

func run() -> void:
	# The small window size, so real board clicks land and the pick prompt is checked at 1280x720.
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	check_flag_off()
	check_sage_start()
	await check_nick_input()
	check_no_enemies()
	check_eureka()
	check_burn_zero()
	check_eureka_destroys()
	check_ally_never()
	check_two_enemies()
	check_on_hit()
	check_combat_effects()
	check_one_per_round()
	await check_final_boss()
	check_save()
	check_versus()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("leader_sage_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: leader_sage_smoke (%d checks)" % checks)
	quit(0)

# 1. Flag false and no override: Sage's row is off and add_status never makes a Eureka.
func check_flag_off() -> void:
	check(game.leader_kit_override == null, "the override starts as null")
	check(not director.character_available(2), "flag off: the Science Club leader is not available")
	director.selected_character = 2
	director.new_run()
	check(director.selected_character == 0 and game.plans.kit_id() == "", "flag off: falls back to Steve, no kit")
	game.leader_kit_override = "robin"
	check(not director.character_available(2), "Robin's override does not turn Sage on")
	game.leader_kit_override = null
	fixture()
	game.plans.set_kit("")
	var foe = card("Foe", 0, 10, "disaster")
	foe.statuses = {"burn":2, "poison":2}
	foe.add_status("bleed", 2)
	check(reagents(foe) == [2, 2, 2] and foe.card_data.health == 10, "flag off: the three statuses stay")
	check(eureka_lines() == 0 and not has_popup(foe, "EUREKA"), "flag off: no Eureka and no popup")

# 2. Override "sage": the row is on and the run starts with the Lab kit.
func check_sage_start() -> void:
	game.leader_kit_override = "sage"
	check(director.character_available(2), "override: the Science Club leader is available")
	check(not director.character_available(3) and director.character_available(0), "override: other rows as today")
	director.selected_character = 2
	director.new_run()
	check(director.selected_character == 2, "override: the run keeps Sage")
	check(game.plans.kit == "sage" and game.plans.kit_id() == "sage", "override: the run has the Lab kit")
	check(game.plans.unlocked == ["nick", "drip"], "override: start with Nick and Drip")
	check(director.coins == 40, "override: Sage starts with 40 supplies")
	check(game.player_hp == 20 and game.plans.cap() == 2, "override: Sage has 20 HP and a cap of 2")
	check(game.player_run_buffs.has("chemist"), "override: Sage keeps the chemist buff")
	# Units only: Cleanse and Tutor are utilities.
	var units: Array = director.collection.filter(func(item): return not item.get("utility", false))
	var elements: Array = units.map(func(item): return str(item.get("element", "")))
	check(elements.count("douse") == 4 and elements.count("clearance") == 6, "Sage's deck: 4 Douse and 6 Clearance")
	game.leader_kit_override = null

# 3. Nick through real input: P, a click on the tile, a click on an enemy. Exact 2 Bleed, 1 Sample. Esc spends nothing.
func check_nick_input() -> void:
	fixture()
	game.player_run_buffs["chemist"] = 1
	game.plans.tokens = 1
	var foe = card("Foe", 1, 9, "disaster")
	await frames(3)
	await key(KEY_P)
	check(director.screen == "plans" and director.modal.visible, "P opens the Lab screen")
	check(director.content.get_child(0).text == "THE LAB", "the title is THE LAB")
	check(director.content.get_node("Status").text == "SAMPLE 1 / 2", "the status reads SAMPLE 1 / 2")
	var nick: Button = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	check(nick.text == "Nick · 1 Sample" and not nick.disabled, "the Nick tile reads Nick · 1 Sample")
	await click(nick)
	check(not director.modal.visible, "Nick closes the screen")
	check(game.board_input.action.get("title", "") == "Click an enemy unit for Nick.", "Nick asks for an enemy unit")
	check(director.board_prompt_label.text == "Click an enemy unit for Nick.", "the board prompt shows the pick")
	await frames(2)
	var prompt_rect: Rect2 = director.board_prompt.get_global_rect()
	check(root.get_visible_rect().encloses(prompt_rect), "the pick prompt fits at 1280x720")
	check(director.board_prompt_label.get_minimum_size().x <= prompt_rect.size.x, "the pick text fits its box")
	await key(KEY_ESCAPE)
	check(game.board_input.action.is_empty() and not director.modal.visible, "Esc cancels the pick")
	check(game.plans.tokens == 1 and game.plans.committed_round != game.turn, "Esc spends nothing")
	check(int(foe.statuses.get("bleed", 0)) == 0, "Esc gives no Bleed")
	await mouse_away()
	await key(KEY_P)
	nick = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	await click(nick)
	await camera_still()
	# Board coordinates, as the click handler reads them (push_input takes local coordinates).
	var point: Vector2 = game.camera.unproject_position(foe.global_position)
	check(game.card_at_board_position(point) == foe, "the click point is on the enemy unit")
	await click_at(point)
	check(int(foe.statuses.get("bleed", 0)) == 2, "a real click on the enemy gives exactly 2 Bleed, chemist or not")
	check(game.plans.tokens == 0 and game.plans.committed_round == game.turn, "Nick costs 1 Sample")
	check(game.board_input.action.is_empty(), "the pick is over")
	await mouse_away()
	foe.free()
	paused = false

# 4. No enemy units: the three status effects are off.
func check_no_enemies() -> void:
	fixture()
	card("Ally", 0, 5)
	for id in ["nick", "drip", "spark"]:
		check(not game.plans.kit_available(id), "no enemies: %s is off" % id)
	check(not game.plans.use_kit_effect("nick"), "no enemies: Nick is refused")
	check(game.plans.tokens == 2, "no enemies: nothing spent")
	check(game.plans.kit_available("fume_hood"), "no enemies: Fume Hood is on")

# 5. Eureka: Burn and Poison, then Bleed from the kit. The three clear and the unit takes 6, armor ignored.
func check_eureka() -> void:
	fixture()
	var foe = card("Armored Foe", 0, 10, "disaster", {"modifiers":["armored"]})
	check(foe.adjusted_damage(6) == 5, "the armored foe would take 5 from a normal 6")
	foe.statuses = {"burn":1, "poison":1}
	check(game.plans.use_kit_effect("nick", foe), "Nick on the foe")
	check(reagents(foe) == [0, 0, 0], "Eureka clears Burn, Poison and Bleed")
	check(foe.card_data.health == 4, "Eureka deals 6, armor ignored")
	check(eureka_lines() == 1 and has_popup(foe, "EUREKA"), "Eureka logs one line and shows its popup")
	check(game.enemy_hp == 20, "Eureka does not touch the Disaster's HP")

# 6. Burn at 0 in the dictionary does not count.
func check_burn_zero() -> void:
	fixture()
	var foe = card("Foe", 0, 10, "disaster")
	foe.statuses = {"burn":0, "poison":2}
	foe.add_status("bleed", 2)
	check(foe.statuses.has("burn") and reagents(foe) == [0, 2, 2], "Burn at 0: the statuses stay")
	check(foe.card_data.health == 10 and eureka_lines() == 0, "Burn at 0: no Eureka")

# 7. A Eureka that destroys the unit: it goes to the graveyard the normal way, the Disaster's HP is unchanged.
func check_eureka_destroys() -> void:
	fixture()
	var foe = card("Weak Foe", 2, 5, "disaster")
	foe.statuses = {"burn":1, "poison":1}
	foe.add_status("bleed", 1)
	check(not foe.is_alive() and foe.graveyard_recorded, "Eureka destroys the unit and records it")
	check(game.battle_log.any(func(line): return "Destroyed: Weak Foe." in str(line)), "the unit is destroyed as usual")
	check(not foe.is_in_group("cards") and game._get_card_in_slot(game._threat_slots()[2]) == null, "its lane is free")
	check(game.enemy_hp == 20, "the Disaster's HP did not change")

# 8. A Preparedness unit never makes a Eureka.
func check_ally_never() -> void:
	fixture()
	var ally = card("Ally", 0, 10)
	ally.statuses = {"burn":2, "poison":2}
	ally.add_status("bleed", 2)
	check(reagents(ally) == [2, 2, 2] and ally.card_data.health == 10, "an ally keeps all three statuses")
	check(eureka_lines() == 0, "no Eureka on an ally")

# 9. Two enemies: only the one with all three is hit.
func check_two_enemies() -> void:
	fixture()
	var full = card("Full", 0, 10, "disaster")
	var half = card("Half", 1, 10, "disaster")
	full.statuses = {"burn":1, "poison":1}
	half.statuses = {"burn":1}
	full.add_status("bleed", 1)
	half.add_status("bleed", 1)
	check(full.card_data.health == 4 and reagents(full) == [0, 0, 0], "the enemy with all three is hit")
	check(half.card_data.health == 10 and reagents(half) == [1, 0, 1], "the other enemy is not")
	check(eureka_lines() == 1, "one Eureka")

# 10. A card hit that adds the third status fires Eureka too.
func check_on_hit() -> void:
	fixture()
	var attacker = card("Lancet", 0, 5, "response", {"attack":1, "on_hit":{"bleed":1}})
	var foe = card("Foe", 0, 20, "disaster")
	foe.statuses = {"burn":2, "poison":2}
	game.resolve_single_strike(attacker, foe, true)
	check(reagents(foe) == [0, 0, 0] and eureka_lines() == 1, "an on-hit Bleed fires Eureka")
	check(foe.is_alive() and foe.card_data.health <= 14, "the foe took the hit and the 6")
	check(game.enemy_hp == 20, "the Eureka from a hit does not reach the Disaster's HP")

# 11. Fume Hood blocks 3 hero damage; Lab Notes draws 1 at combat start and is off with a full hand.
func check_combat_effects() -> void:
	fixture()
	check(game.plans.use_kit_effect("fume_hood"), "Fume Hood can be armed")
	check(game.plans.armed.size() == 4 and game.plans.armed.kind == "fume_hood", "Fume Hood arms with four keys")
	game.plans.apply_combat()
	check(game.plan_hero_barrier == 3, "Fume Hood sets 3 hero block")
	game._damage_side(true, 5)
	check(game.player_hp == 18, "Fume Hood blocks 3")
	game.plans.finish_combat()
	check(game.plan_hero_barrier == 0, "Fume Hood ends with the combat")
	next_round()
	check(not game.plans.kit_available("lab_notes"), "Lab Notes is off with an empty draw pile")
	game.deck.assign([FILLER.duplicate(), FILLER.duplicate()])
	check(game.plans.use_kit_effect("lab_notes"), "Lab Notes can be armed")
	var before: int = game.get_hand_cards().size()
	game.plans.apply_combat()
	check(game.get_hand_cards().size() == before + 1 and game.deck.size() == 1, "Lab Notes draws 1 at combat start")
	game.plans.finish_combat()
	next_round()
	while game.get_hand_cards().size() < game.HAND_SIZE_MAX: game.add_card_to_hand(FILLER.duplicate())
	check(not game.plans.kit_available("lab_notes"), "Lab Notes is off with a full hand")

# 12. One kit effect per round.
func check_one_per_round() -> void:
	fixture()
	var foe = card("Foe", 0, 20, "disaster")
	check(game.plans.use_kit_effect("drip", foe), "Drip on the foe")
	check(int(foe.statuses.get("poison", 0)) == 2 and game.plans.tokens == 1, "Drip gives 2 Poison for 1 Sample")
	check(not game.plans.kit_available("spark"), "one kit effect per round")
	check(not game.plans.use_kit_effect("spark", foe) and game.plans.tokens == 1, "a second use costs nothing")
	check(int(foe.statuses.get("burn", 0)) == 0, "a second use adds nothing")
	next_round()
	check(game.plans.use_kit_effect("spark", foe) and int(foe.statuses.get("burn", 0)) == 2, "Spark works next round")

# 13. Final boss floor: a pillar with all three takes 6. No error over 120 frames.
func check_final_boss() -> void:
	fixture()
	game.disaster_is_human = false
	game.encounter_kind = "boss"
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	game.final_boss.spawn_unit("west_pillar")
	var pillars: Array = game.final_boss.pillars()
	check(pillars.size() == 1, "a pillar stands")
	if pillars.is_empty(): return
	var pillar: Node = pillars[0]
	var before: int = int(pillar.card_data.health)
	pillar.statuses = {"burn":1, "poison":1}
	pillar.add_status("bleed", 1)
	check(int(pillar.card_data.health) == before - 6 and reagents(pillar) == [0, 0, 0], "a pillar Eureka deals 6")
	check(game.enemy_hp == 34, "the Janitor's HP did not change")
	await frames(120)
	check(game.final_boss.pillars().size() == (1 if before > 6 else 0), "the board is steady after 120 frames")
	game.clear_battle()

func saved_plans() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(director.persistence.save_path()))
	return data.get("plans", {}) if data is Dictionary else {}

# 14a. Save and resume keep kit "sage" and the unlocked list. Sage adds no saved state of its own.
func check_save() -> void:
	fixture()
	director.run_active = true
	game.plans.unlocked.assign(["nick", "drip", "spark"])
	check(director.persistence.checkpoint(), "a Sage battle checkpoints")
	check(saved_plans().get("kit", "") == "sage", "the save holds kit sage")
	game.plans.kit = ""
	game.plans.unlocked.assign(["brace"])
	check(director.persistence.resume(), "the Sage run resumes")
	check(game.plans.kit == "sage", "resume keeps kit sage")
	check(game.plans.unlocked == ["nick", "drip", "spark"], "resume keeps the unlocked list")
	director.close_modal()
	paused = false

# 14b. A Versus match during a Sage run uses today's plans and never fires Eureka.
func check_versus() -> void:
	game.clear_battle()
	game.plans.set_kit("sage")
	game.plans.unlocked.assign(["nick", "drip", "fume_hood"])
	director.start_versus_match()
	check(game.encounter_kind == "versus", "the Versus match started")
	check(game.plans.kit_id() == "", "Versus: no kit in the match")
	check(game.plans.unlocked == ["brace", "coordinate", "medicine"], "Versus: today's three tactics")
	var foe = card("Versus Foe", 3, 10, "disaster")
	foe.statuses = {"burn":1, "poison":1}
	foe.add_status("bleed", 1)
	check(reagents(foe) == [1, 1, 1] and foe.card_data.health == 10, "Versus: no Eureka")
	foe.remove_from_group("cards")
	foe.free()
	director.battle_finished(true)
	check(game.plans.kit == "sage", "after Versus: the run's kit is intact")
	check(game.plans.unlocked == ["nick", "drip", "fume_hood"], "after Versus: the run's unlocked list is intact")
	director.close_modal()
	paused = false
