# Covers: Robin's Aid kit (leader_kits.gd) through game.plans: start, effects, Second Wind, screens, saves, Versus.
# The kit is reached only with game.leader_kit_override; the const flag stays false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const ALL_AID := ["patch_up", "cover", "clean_up", "rescue", "safe_room"]

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

# A battle on the player's turn, as contingency_plans_smoke builds it, with the whole Aid kit owned.
func fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.auto_save = true
	game.plans.unlocked.assign(ALL_AID)
	game.plans.tokens = 2
	game.turn = 1
	game.player_hp = 20
	game.player_barrier = 0
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 6
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func card(name: String, lane: int, health: int, side: String = "response") -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	var type := "response" if side == "response" else "disaster"
	result.setup({"name":name, "type":type, "element":"evac", "cost":1, "attack":2, "health":10})
	result.in_hand = false
	var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
	result.current_slot = slots[lane]
	result.card_data.health = health
	return result

# A unit that was destroyed this battle, in the graveyard.
func destroyed(name: String) -> void:
	var unit = card(name, 3, 10)
	game.record_graveyard(unit, "Destroyed")
	unit.remove_from_group("cards")
	unit.free()

func next_round() -> void:
	game.turn += 1
	game.plans.tokens = 2

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
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

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	check_flag_off()
	check_robin_start()
	check_patch_up()
	check_cover()
	check_clean_up()
	check_rescue()
	check_safe_room()
	check_second_wind()
	check_empty_board()
	await check_plans_screen()
	check_reward()
	check_save()
	check_versus()
	await check_armed_frames()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("leader_robin_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: leader_robin_smoke (%d checks)" % checks)
	quit(0)

# 1. Flag false and no override: Robin's row is off and a run falls back to Steve with today's plans.
func check_flag_off() -> void:
	check(game.leader_kit_override == null, "the override starts as null")
	check(not director.character_available(3), "flag off: the Safety Club leader is not available")
	director.selected_character = 3
	director.new_run()
	check(director.selected_character == 0, "flag off: new_run falls back to character 0")
	check(game.plans.kit_id() == "" and game.plans.kit == "", "flag off: no kit")
	check(game.plans.unlocked == ["brace", "coordinate"], "flag off: today's start tactics")
	check(director.coins == 35 and game.plans.cap() == 2, "flag off: today's supplies and cap")

# 2. Override "robin": the row is on and the run starts with the Aid kit.
func check_robin_start() -> void:
	game.leader_kit_override = "robin"
	check(director.character_available(3), "override: the Safety Club leader is available")
	check(not director.character_available(1) and director.character_available(0), "override: other rows as today")
	director.selected_character = 3
	director.new_run()
	check(director.selected_character == 3, "override: the run keeps Robin")
	check(game.plans.kit == "robin" and game.plans.kit_id() == "robin", "override: the run has the Aid kit")
	check(game.plans.unlocked == ["patch_up", "cover"], "override: start with Patch Up and Cover")
	check(director.coins == 30, "override: Robin starts with 30 supplies")
	check(game.player_hp == 20, "override: Robin has 20 HP")
	check(game.plans.definition("brace").is_empty(), "kit on: plan ids are not kit effects")
	check(game.plans.definition("patch_up").name == "Patch Up", "kit on: definition reads the kit")

# 3 and 4. Patch Up heals the weakest ally, leftmost on a tie, costs 1 Aid, once per round.
func check_patch_up() -> void:
	fixture()
	var left = card("Left", 0, 6)
	var middle = card("Middle", 1, 4)
	var right = card("Right", 2, 4)
	game.plans.tokens = 1
	check(game.plans.weakest() == middle, "weakest: lowest health, leftmost on a tie")
	check(game.plans.use_kit_effect("patch_up"), "Patch Up can be used")
	check(middle.card_data.health == 7 and right.card_data.health == 4 and left.card_data.health == 6,
		"Patch Up heals the leftmost of the weakest allies by 3")
	check(game.plans.tokens == 0 and game.plans.committed_round == game.turn, "Patch Up costs 1 Aid")
	game.plans.tokens = 2
	check(not game.plans.kit_available("patch_up"), "one kit effect per round")
	check(not game.plans.use_kit_effect("patch_up") and game.plans.tokens == 2 and right.card_data.health == 4,
		"a second use in the same round is refused and costs nothing")
	next_round()
	left.card_data.health = 8
	middle.card_data.health = 8
	right.card_data.health = 3
	check(game.plans.use_kit_effect("patch_up") and right.card_data.health == 6,
		"Patch Up finds a weakest ally on the right")
	check(game.plans.tokens == 1, "the next round Patch Up costs 1 Aid again")

# 5. Cover picks its unit when combat starts, not when it is pressed.
func check_cover() -> void:
	fixture()
	var first = card("First", 0, 4)
	var second = card("Second", 1, 7)
	check(game.plans.use_kit_effect("cover"), "Cover can be armed")
	check(game.plans.armed.size() == 4 and game.plans.armed.kind == "cover" and game.plans.armed.targets.is_empty(),
		"Cover arms with the same four keys as a plan")
	check(game.plans.tokens == 1, "Cover costs 1 Aid")
	second.card_data.health = 2
	game.plans.apply_combat()
	check(second.planned_guard == 2 and first.planned_guard == 0, "Cover goes to the weakest ally at combat start")
	second.take_damage(3)
	check(second.card_data.health == 1 and second.planned_guard == 0, "Cover blocks 2 from the next hit")
	game.plans.finish_combat()
	check(game.plans.armed.is_empty(), "the armed Aid clears after combat")
	fixture()
	var gone = card("Gone", 0, 5)
	check(game.plans.use_kit_effect("cover"), "Cover can be armed with one ally")
	gone.card_data.health = 0
	game.plans.apply_combat()
	check(game.battle_log.any(func(line): return "Aid expired: no unit to cover." in str(line)),
		"Cover with no unit at combat start is spent with a log line")
	game.plans.finish_combat()

# 6. Clean Up is off with no bad status and clears all four when used.
func check_clean_up() -> void:
	fixture()
	var low = card("Low", 0, 2)
	var sick = card("Sick", 1, 5)
	check(not game.plans.kit_available("clean_up"), "Clean Up is off with no status on any ally")
	sick.statuses = {"burn":2, "poison":1, "bleed":1, "healing_reduced":2}
	check(game.plans.weakest(true) == sick, "Clean Up looks only at allies with a status")
	check(game.plans.use_kit_effect("clean_up"), "Clean Up can be used")
	for status in ["burn", "poison", "bleed", "healing_reduced"]:
		check(int(sick.statuses.get(status, 0)) == 0, "Clean Up clears " + status)
	check(sick.card_data.health == 8 and low.card_data.health == 2, "Clean Up heals that unit 3")
	check(game.plans.tokens == 1, "Clean Up costs 1 Aid")

# 7. Rescue: off with an empty graveyard or a full hand; returns the last destroyed unit once.
func check_rescue() -> void:
	fixture()
	check(not game.plans.kit_available("rescue"), "Rescue is off with an empty graveyard")
	destroyed("First Lost")
	destroyed("Last Lost")
	for i in game.HAND_SIZE_MAX:
		game.add_card_to_hand({"name":"Filler", "type":"response", "element":"evac", "cost":1, "attack":1, "health":3})
	check(game.get_hand_cards().size() == game.HAND_SIZE_MAX, "the hand is full")
	check(not game.plans.kit_available("rescue"), "Rescue is off with a full hand")
	for filler in game.get_hand_cards():
		game.hand.erase(filler)
		filler.remove_from_group("cards")
		filler.free()
	game.plans.tokens = 1
	check(not game.plans.kit_available("rescue"), "Rescue needs 2 Aid")
	game.plans.tokens = 2
	check(game.plans.use_kit_effect("rescue"), "Rescue can be used")
	var hand: Array = game.get_hand_cards()
	check(hand.size() == 1 and hand[0].card_data.name == "Last Lost", "Rescue returns the last destroyed unit to the hand")
	check(game.plans.tokens == 0, "Rescue costs 2 Aid")
	check(not game.recoverable_units().any(func(entry): return entry.name == "Last Lost"),
		"the rescued unit cannot be rescued again")
	next_round()
	check(game.plans.use_kit_effect("rescue"), "Rescue works again next round")
	check(game.get_hand_cards().any(func(unit): return unit.card_data.name == "First Lost"), "the next unit returns")
	next_round()
	check(not game.plans.kit_available("rescue"), "Rescue is off when every unit is back")

# 8. Safe Room blocks 3 hero damage in that combat only.
func check_safe_room() -> void:
	fixture()
	check(game.plans.use_kit_effect("safe_room"), "Safe Room can be armed with no ally")
	game.plans.apply_combat()
	check(game.plan_hero_barrier == 3, "Safe Room sets 3 hero block")
	game._damage_side(true, 5)
	check(game.player_hp == 18, "Safe Room reduces hero damage by 3")
	game.plans.finish_combat()
	check(game.plan_hero_barrier == 0, "Safe Room ends with the combat")

# 9. Second Wind: one lethal attack hit leaves the ally at 1. Status damage and enemies are never saved.
func check_second_wind() -> void:
	fixture()
	var ally = card("Ally", 0, 4)
	ally.take_damage(10)
	check(ally.is_alive() and ally.card_data.health == 1, "Second Wind leaves the ally at 1 health")
	check(game.plans.kit_used, "Second Wind is spent")
	ally.take_damage(10)
	check(not ally.is_alive(), "the next lethal hit destroys the ally")
	fixture()
	var burning = card("Burning", 1, 2)
	burning.statuses = {"burn":3}
	burning.status_upkeep()
	check(not burning.is_alive(), "Burn at upkeep still destroys the ally")
	check(not game.plans.kit_used, "Burn does not spend Second Wind")
	var foe = card("Foe", 0, 3, "disaster")
	foe.take_damage(10)
	check(not foe.is_alive() and not game.plans.kit_used, "an enemy unit is never saved")
	fixture()
	check(not game.plans.kit_used, "Second Wind comes back each battle")

# 10. Empty board: the weakest-unit effects are off, Rescue and Safe Room follow their own rules.
func check_empty_board() -> void:
	fixture()
	for id in ["patch_up", "cover", "clean_up"]:
		check(not game.plans.kit_available(id), "empty board: %s is off" % id)
	check(not game.plans.kit_available("rescue"), "empty board: Rescue is off with nothing destroyed")
	check(game.plans.kit_available("safe_room"), "empty board: Safe Room is on")
	destroyed("Lost")
	check(game.plans.kit_available("rescue"), "empty board: Rescue is on with a destroyed unit")

# 11. The Aid screen through real input: P opens it, a click uses Patch Up, Esc closes it.
func check_plans_screen() -> void:
	fixture()
	game.plans.unlocked.assign(["patch_up", "cover"])
	game.plans.tokens = 1
	var hurt = card("Hurt", 0, 5)
	await frames(3)
	await key(KEY_P)
	check(director.screen == "plans" and director.modal.visible, "P opens the Aid screen")
	check(director.content.get_child(0).text == "AID KIT", "the title is AID KIT")
	check(director.content.get_node("Status").text == "AID 1 / 2", "the status reads AID 1 / 2")
	var list: Node = director.content.get_node("Scroll/List")
	var patch: Button = list.get_child(0).get_node("Box/PickButton")
	check(patch.text == "Patch Up · 1 Aid" and not patch.disabled, "the Patch Up tile reads Patch Up · 1 Aid")
	check(director.plans_button.get_node("CountLabel").text == "1/2", "the count label reads 1/2")
	await click(patch)
	check(hurt.card_data.health == 8, "a real click on Patch Up heals the weakest unit")
	check(director.screen != "plans" and not director.modal.visible, "Patch Up closes the screen")
	await key(KEY_P)
	check(director.screen == "plans", "P opens the Aid screen again")
	patch = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	check(patch.disabled, "Patch Up is off after a use this round")
	await key(KEY_ESCAPE)
	check(director.screen != "plans" and not director.modal.visible, "Esc closes the Aid screen")
	await mouse_away()
	hurt.free()
	paused = false

# 12. The reward screen offers only kit effects the run does not own yet.
func check_reward() -> void:
	game.clear_battle()
	game.encounter_kind = "elite"
	director.battle_active = false
	director.screen = ""
	game.plans.unlocked.assign(["patch_up", "cover"])
	director.show_contingency_reward("cards")
	check(director.screen == "contingency_reward", "the reward screen opens with a kit")
	var words: Array = director.content.find_children("*", "Label", true, false).map(func(node): return node.text)
	check("NEW AID" in words and "Add one to your kit for this run." in words, "the reward words come from the kit")
	var tiles: Array = director.content.find_children("PickButton", "Button", true, false).map(
		func(node): return node.text)
	check(tiles.size() == 3 and tiles.all(func(title): return title.ends_with(" Aid")), "reward tiles name the Aid cost")
	var offered: Array = director.buff_choices.map(func(row): return row.id)
	offered.sort()
	check(offered == ["clean_up", "rescue", "safe_room"], "only kit effects not owned are offered")
	director.select_contingency_reward("rescue")
	check(game.plans.unlocked == ["patch_up", "cover", "rescue"], "picking one adds it to the kit")
	director.screen = ""
	game.plans.unlocked.assign(ALL_AID)
	director.show_contingency_reward("cards")
	check(director.screen != "contingency_reward", "a full kit skips the reward screen")
	director.close_modal()

func saved_plans() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(director.persistence.save_path()))
	return data.get("plans", {}) if data is Dictionary else {}

# 13. Save and resume keep the kit; a save with no kit has no kit key.
func check_save() -> void:
	fixture()
	director.run_active = true
	game.plans.unlocked.assign(["patch_up", "cover", "clean_up"])
	game.plans.kit_used = true
	check(director.persistence.checkpoint(), "a Robin battle checkpoints")
	check(saved_plans().get("kit", "") == "robin" and saved_plans().get("kit_used", false) == true,
		"the save holds kit and kit_used")
	game.plans.kit = ""
	game.plans.kit_used = false
	game.plans.unlocked.assign(["brace"])
	check(director.persistence.resume(), "the Robin run resumes")
	check(game.plans.kit == "robin" and game.plans.kit_used, "resume keeps kit and kit_used")
	check(game.plans.unlocked == ["patch_up", "cover", "clean_up"], "resume keeps the unlocked list")
	game.plans.set_kit("")
	check(director.persistence.checkpoint(), "a run with no kit checkpoints")
	check(not saved_plans().has("kit") and not saved_plans().has("kit_used"), "a save with no kit has no kit key")
	game.plans.set_kit("robin")
	director.close_modal()
	paused = false

# 14. A Versus match during a Robin run uses today's plans and leaves the run's kit alone.
func check_versus() -> void:
	game.clear_battle()
	game.plans.set_kit("robin")
	game.plans.unlocked.assign(["patch_up", "cover", "safe_room"])
	director.start_versus_match()
	check(game.encounter_kind == "versus", "the Versus match started")
	check(game.plans.kit_id() == "", "Versus: no kit in the match")
	check(game.plans.unlocked == ["brace", "coordinate", "medicine"], "Versus: today's three tactics")
	check(game.plans.definition("brace").name == "Brace" and game.plans.cap() == 2, "Versus: today's plan rules")
	director.battle_finished(true)
	check(game.plans.kit == "robin", "after Versus: the run's kit is intact")
	check(game.plans.unlocked == ["patch_up", "cover", "safe_room"], "after Versus: the run's unlocked list is intact")
	director.close_modal()
	paused = false

# 15. A combat effect armed for 120 battle frames: preview_attack runs every frame without an error.
func check_armed_frames() -> void:
	fixture()
	game.disaster_is_human = false
	game.plans.set_kit("robin")
	game.plans.unlocked.assign(ALL_AID)
	var ally = card("Steady", 0, 5)
	check(game.plans.use_kit_effect("cover"), "Cover armed for the frame check")
	for i in 120: await process_frame
	check(game.plans.armed.get("kind", "") == "cover" and ally.plan_attack_bonus == 0,
		"Cover stays armed and adds no attack over 120 frames")
	game.plans.finish_combat()
