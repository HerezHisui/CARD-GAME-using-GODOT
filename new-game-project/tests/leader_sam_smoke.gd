# Covers: Sam's Last Bell kit (leader_kits.gd) through game.plans: the Bell bank, the skip, Cram, Borrow Notes,
# Excuse Slip, the reward, saves and Versus. Character 0 with the flag off must play exactly as today.
# The kit is reached only with game.leader_kit_override and game.plans.set_kit; the flag stays false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const LeaderKits = preload("res://scripts/leader_kits.gd")
const ALL_BELL := ["cram", "borrow_notes", "excuse_slip"]
const FILLER := {"name":"Filler", "type":"response", "element":"evac", "cost":1, "attack":1, "health":3}

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

# A battle on the player's turn, as leader_kai_smoke builds it. kit_id "" keeps the run's plans as they are.
func fixture(kit_id := "sam") -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	if kit_id != "":
		game.plans.set_kit(kit_id)
		game.plans.unlocked.assign(ALL_BELL)
	game.plans.auto_save = true
	game.plans.tokens = 0
	game.turn = 1
	game.player_hp = 20
	game.player_barrier = 0
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 3
	game.deck.assign([FILLER.duplicate(), FILLER.duplicate()])
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

func hand_size() -> int:
	return game.get_hand_cards().size()

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	await mouse_move(point)
	await mouse_button(point, true)
	await mouse_button(point, false)
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)

# A real mouse move: the viewport and the Input singleton both see it, as in a window.
# push_input takes board coordinates; the Input singleton takes window coordinates.
func mouse_move(point: Vector2) -> void:
	var window := InputEventMouseMotion.new()
	window.position = root.get_final_transform() * point
	window.global_position = window.position
	Input.parse_input_event(window)
	Input.flush_buffered_events()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await process_frame

func mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
	await process_frame

func mouse_away() -> void:
	await mouse_move(Vector2(4, 4))

# A real End Turn: one enemy unit in lane 3 (attack 0 is harmless), then wait for the next turn, capped at 600.
func end_turn(enemy_attack := 0) -> void:
	game.disaster_is_human = false
	game.player_first = true
	card("Holdout", 3, 30, "disaster", {"attack":enemy_attack, "health":30, "element":"flood"})
	await game._on_end_turn_pressed()
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY, game.Phase.GAME_OVER]: break
		await process_frame

func log_count(text: String) -> int:
	return game.battle_log.filter(func(line): return text in str(line)).size()

func run() -> void:
	# The small window size, so real clicks land at 1280x720.
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	await check_flag_off()
	check_sam_start()
	await check_bank()
	await check_skip()
	check_not_skip()
	check_skip_edges()
	await check_cram_input()
	check_combat_effects()
	check_one_per_round()
	check_reward()
	check_save()
	check_versus()
	await check_frames_above_cap()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("leader_sam_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: leader_sam_smoke (%d checks)" % checks)
	quit(0)

# 1. Flag false and no override: character 0 plays exactly as today.
func check_flag_off() -> void:
	check(not LeaderKits.SAM_ENABLED, "the Sam flag is off")
	check(game.leader_kit_override == null, "the override starts as null")
	check(director.CHARACTERS[0].name == "Steve · Student", "character 0 keeps its name")
	check(director.character_available(0), "character 0 is available as today")
	director.selected_character = 0
	director.new_run()
	check(director.selected_character == 0, "the run keeps character 0")
	check(game.plans.kit == "" and game.plans.kit_id() == "", "flag off: character 0 has no kit")
	check(game.plans.unlocked == ["brace", "coordinate"], "flag off: today's two tactics")
	check(game.plans.cap() == 2 and director.coins == 35, "flag off: cap 2 and 35 supplies")
	check(game.player_run_buffs.has("cadet"), "flag off: the cadet buff")
	check(game.get_node("HUD/TopBar/PlayerHealth/Caption").text == "Steve · Student", "flag off: the caption")
	fixture("")
	game.preparedness = 2
	await end_turn()
	check(game.turn == 2 and game.plans.tokens == 1 and log_count("Saved 2 energy for a Plan token") == 1,
		"flag off: End Turn with 2 unused energy gives 1 token as today")
	check(log_count("in the Bell") == 0 and log_count("skips the turn") == 0, "flag off: no Bell and no skip")

# 2. Override "sam": character 0 starts with the Last Bell kit and today's sheet.
func check_sam_start() -> void:
	game.leader_kit_override = "sam"
	check(director.character_available(0), "override: character 0 is available")
	check(not director.character_available(1) and not director.character_available(2)
		and not director.character_available(3), "override: the other leaders stay off")
	director.selected_character = 0
	director.new_run()
	check(game.plans.kit == "sam" and game.plans.kit_id() == "sam", "override: the run has the Last Bell kit")
	check(game.plans.unlocked == ["cram", "borrow_notes"], "override: start with Cram and Borrow Notes")
	check(director.coins == 35 and game.player_hp == 20, "override: 35 supplies and 20 HP")
	check(game.plans.cap() == 4, "override: the Bell holds 4")
	check(game.player_run_buffs.has("cadet"), "override: Sam keeps the cadet buff")
	check(director.collection.size() == 12, "override: the same 12-card deck")
	game.leader_kit_override = null

# 3. End Turn banks all unused energy 1 for 1. The Bell never passes 4.
func check_bank() -> void:
	fixture()
	game.preparedness = 2
	check(game.plans.bank_unused_energy(), "the Bell saves energy")
	check(game.plans.tokens == 2 and game.preparedness == 0, "2 unused energy: Bell 2, energy 0")
	check(log_count("Saved 2 energy in the Bell (2/4).") == 1, "the save log line")
	check(not game.plans.bank_unused_energy() and game.plans.tokens == 2, "the Bell saves once per round")
	next_round()
	game.preparedness = 2
	game.plans.tokens = 3
	check(game.plans.bank_unused_energy() and game.plans.tokens == 4 and game.preparedness == 1,
		"Bell 3 with 2 unused: Bell 4, the rest is not saved")
	next_round()
	game.preparedness = 2
	check(not game.plans.bank_unused_energy() and game.plans.tokens == 4, "a full Bell saves nothing")
	fixture()
	game.preparedness = 2
	await end_turn()
	check(game.turn == 2 and game.plans.tokens == 2, "a real End Turn with 2 unused energy: Bell 2")
	check(log_count("skips the turn") == 0, "2 of 3 energy is not a skip")

# 4. Skip: End Turn at full energy with no kit effect used draws 1 and blocks 3 hero damage this combat.
func check_skip() -> void:
	fixture()
	var before := hand_size()
	game.plans.bank_unused_energy()
	check(hand_size() == before + 1 and game.deck.size() == 1, "a skip draws 1")
	check(game.plan_hero_barrier == 3, "a skip blocks 3")
	check(game.plans.tokens == 3 and game.preparedness == 0, "a skip still saves all the energy")
	check(log_count("Sam skips the turn: draw 1, block 3.") == 1, "the skip log line")
	game._damage_side(true, 5)
	check(game.player_hp == 18, "the skip block takes 3 off a hero hit")
	game.plans.finish_combat()
	check(game.plan_hero_barrier == 0, "the block is 0 after combat")
	# A real round: an enemy unit with 2 attack in an empty lane hits the hero in combat.
	fixture()
	await end_turn(2)
	check(game.turn == 2 and game.player_hp == 20, "a real skip round: the block takes the 2 hero damage")
	check(game.plan_hero_barrier == 0, "a real skip round: the block is 0 after combat")
	fixture()
	game.preparedness = 2
	await end_turn(2)
	check(game.turn == 2 and game.player_hp == 18, "a real round that is not a skip: the hero takes 2")

# 5-7. What breaks a skip: energy spent or a kit effect. A 0-cost card does not.
func check_not_skip() -> void:
	fixture()
	card("Played", 0, 5)
	game.preparedness = 2
	var before := hand_size()
	game.plans.bank_unused_energy()
	check(hand_size() == before and game.plan_hero_barrier == 0, "a unit played (energy below the cap): no skip")
	fixture()
	game.plans.tokens = 2
	check(game.plans.use_kit_effect("borrow_notes"), "Borrow Notes armed")
	before = hand_size()
	game.plans.bank_unused_energy()
	check(hand_size() == before and game.plan_hero_barrier == 0, "a kit effect used this round: no skip")
	game.plans.finish_combat()
	fixture()
	card("Free", 0, 5, "response", {"cost":0})
	before = hand_size()
	game.plans.bank_unused_energy()
	check(hand_size() == before + 1 and game.plan_hero_barrier == 3,
		"a 0-cost card with energy still full is a skip (the stated rule)")
	game.plans.finish_combat()

# 8. Skip with a full hand or an empty draw pile: no card, the block still applies.
func check_skip_edges() -> void:
	fixture()
	while hand_size() < game.HAND_SIZE_MAX: game.add_card_to_hand(FILLER.duplicate())
	game.plans.bank_unused_energy()
	check(hand_size() == game.HAND_SIZE_MAX and game.deck.size() == 2, "a full hand: no draw")
	check(game.plan_hero_barrier == 3, "a full hand: the block applies")
	fixture()
	game.deck.clear()
	var before := hand_size()
	game.plans.bank_unused_energy()
	check(hand_size() == before and game.plan_hero_barrier == 3, "an empty draw pile: no draw, the block applies")
	game.plans.finish_combat()

# 9. Cram through real input: P, a real click on the tile. It takes all the Bell that fits under 7.
func check_cram_input() -> void:
	fixture()
	game.energy_cap = 4
	game.preparedness = 2
	game.plans.tokens = 3
	await frames(3)
	await key(KEY_P)
	check(director.screen == "plans" and director.modal.visible, "P opens the Bell screen")
	check(director.content.get_child(0).text == "LAST BELL", "the title is LAST BELL")
	check(director.content.get_node("Status").text == "BELL 3 / 4", "the status reads BELL 3 / 4")
	check(director.plans_button.get_node("CountLabel").text == "3/4", "the count label reads 3/4")
	var list: Node = director.content.get_node("Scroll/List")
	var cram: Button = list.get_child(0).get_node("Box/PickButton")
	check(cram.text == "Cram · all Bell" and not cram.disabled, "the Cram tile reads Cram · all Bell")
	var notes: Button = list.get_child(1).get_node("Box/PickButton")
	check(notes.text == "Borrow Notes · 2 Bell", "the other tiles keep the cost and charge")
	await click(cram)
	check(game.preparedness == 5 and game.plans.tokens == 0, "Cram at 2 energy with Bell 3: energy 5, Bell 0")
	check(not director.modal.visible, "Cram closes the screen")
	await frames(2)
	check(director.prep.get_parent().get_node("Value").text == "5 / 4", "the energy text reads 5 / 4")
	next_round()
	game.preparedness = 6
	game.plans.tokens = 3
	await key(KEY_P)
	cram = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	await click(cram)
	check(game.preparedness == 7 and game.plans.tokens == 2, "Cram at 6 energy with Bell 3: energy 7, Bell 2")
	next_round()
	await key(KEY_P)
	cram = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	check(cram.disabled, "at 7 energy the Cram tile is off")
	await key(KEY_ESCAPE)
	check(not director.modal.visible, "Esc closes the Bell screen")
	next_round()
	game.preparedness = 3
	game.plans.tokens = 0
	check(not game.plans.kit_available("cram"), "Cram is off with an empty Bell")
	await mouse_away()
	paused = false

# 10. Borrow Notes and Excuse Slip fire at combat start. Excuse Slip and a skip block 3, not 6.
func check_combat_effects() -> void:
	fixture()
	game.plans.tokens = 2
	check(game.plans.use_kit_effect("borrow_notes"), "Borrow Notes can be armed with no unit")
	check(game.plans.armed.size() == 4 and game.plans.tokens == 0, "Borrow Notes arms with four keys and costs 2")
	var before := hand_size()
	game.plans.apply_combat()
	check(hand_size() == before + 1, "Borrow Notes draws 1 at combat start")
	game.plans.finish_combat()
	fixture()
	game.plans.tokens = 2
	check(game.plans.use_kit_effect("excuse_slip"), "Excuse Slip can be armed with no unit")
	game.plans.apply_combat()
	check(game.plan_hero_barrier == 3, "Excuse Slip blocks 3")
	game.plans.finish_combat()
	check(game.plan_hero_barrier == 0, "Excuse Slip ends with the combat")
	# A kit effect breaks a skip, so this pair cannot meet in play. Force it to prove the block is set, not added.
	fixture()
	game.plans.tokens = 2
	game.plans.use_kit_effect("excuse_slip")
	game.plans.committed_round = -1
	game.plans.bank_unused_energy()
	check(game.plan_hero_barrier == 3, "the skip sets 3")
	game.plans.apply_combat()
	check(game.plan_hero_barrier == 3, "Excuse Slip plus a skip blocks 3, not 6")
	game.plans.finish_combat()

# 11. One kit effect per round.
func check_one_per_round() -> void:
	fixture()
	game.plans.tokens = 4
	game.preparedness = 1
	check(game.plans.use_kit_effect("borrow_notes"), "the first kit effect this round works")
	check(not game.plans.kit_available("cram") and not game.plans.use_kit_effect("cram"),
		"a second kit effect in the same round is refused")
	check(game.plans.tokens == 2 and game.preparedness == 1, "the refused effect costs nothing")
	# Combat ends the armed effect; the next round frees the kit again.
	game.plans.finish_combat()
	next_round()
	check(game.plans.kit_available("cram"), "the next round frees the kit again")

# 12. Reward: Excuse Slip is offered once, then the reward screen is skipped.
func check_reward() -> void:
	game.clear_battle()
	game.encounter_kind = "elite"
	director.battle_active = false
	director.screen = ""
	game.plans.set_kit("sam")
	director.show_contingency_reward("cards")
	check(director.screen == "contingency_reward", "the reward screen opens with one effect locked")
	var words: Array = director.content.find_children("*", "Label", true, false).map(func(node): return node.text)
	check("NEW EXCUSE" in words and "Add it to your kit for this run." in words, "the reward words come from the kit")
	var tiles: Array = director.content.find_children("PickButton", "Button", true, false).map(
		func(node): return node.text)
	check(tiles == ["Excuse Slip · 2 Bell"], "only Excuse Slip is offered")
	director.select_contingency_reward("excuse_slip")
	check(game.plans.unlocked == ALL_BELL, "picking it completes the kit")
	director.screen = ""
	director.show_contingency_reward("cards")
	check(director.screen != "contingency_reward", "the next elite reward moves on without a screen")
	director.close_modal()

func saved_plans() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(director.persistence.save_path()))
	return data.get("plans", {}) if data is Dictionary else {}

# 13a. Save and resume keep Bell 4, the kit and the unlocked list.
func check_save() -> void:
	fixture()
	director.run_active = true
	game.plans.tokens = 4
	check(director.persistence.checkpoint(), "a Sam battle checkpoints")
	check(saved_plans().get("kit", "") == "sam" and int(saved_plans().get("tokens", 0)) == 4,
		"the save holds the kit and Bell 4")
	game.plans.kit = ""
	game.plans.tokens = 0
	game.plans.unlocked.assign(["brace"])
	check(director.persistence.resume(), "the Sam run resumes")
	check(game.plans.kit == "sam" and game.plans.tokens == 4, "resume keeps the kit and Bell 4")
	check(game.plans.unlocked == ALL_BELL, "resume keeps the unlocked list")
	director.close_modal()
	paused = false

# 13b. A Versus match during a Sam run uses today's plans and today's bank, and never skips.
func check_versus() -> void:
	game.clear_battle()
	game.plans.set_kit("sam")
	game.plans.unlocked.assign(ALL_BELL)
	director.start_versus_match()
	check(game.encounter_kind == "versus", "the Versus match started")
	check(game.plans.kit_id() == "" and game.plans.cap() == 2, "Versus: no kit in the match")
	check(game.plans.unlocked == ["brace", "coordinate", "medicine"], "Versus: today's three tactics")
	game.plans.tokens = 0
	game.preparedness = 3
	game.plans.saved_round = -1
	var before := hand_size()
	check(game.plans.bank_unused_energy() and game.plans.tokens == 1 and game.preparedness == 1,
		"Versus: 2 energy for 1 token as today")
	check(hand_size() == before and game.plan_hero_barrier == 0, "Versus: a full-energy End Turn does not draw or block")
	next_round()
	game.plans.tokens = 2
	game.preparedness = 3
	check(not game.plans.bank_unused_energy() and game.plans.tokens == 2, "Versus: today's bank stops at 2")
	director.battle_finished(true)
	check(game.plans.kit == "sam", "after Versus: the run's kit is intact")
	check(game.plans.unlocked == ALL_BELL, "after Versus: the run's unlocked list is intact")
	director.close_modal()
	paused = false

# 14. Energy above the cap for 120 battle frames: the gauge, the pips and the text draw without an error.
func check_frames_above_cap() -> void:
	fixture()
	game.disaster_is_human = false
	game.energy_cap = 4
	game.preparedness = 6
	game.plans.tokens = 2
	check(game.plans.use_kit_effect("borrow_notes"), "Borrow Notes armed for the frame check")
	for i in 120: await process_frame
	check(game.preparedness == 6, "energy above the cap is not clamped")
	check(director.prep.get_parent().get_node("Value").text == "6 / 4", "the energy text reads 6 / 4")
	check(director.plans_button.get_node("CountLabel").text == "0/4", "the count label reads 0/4")
	game.plans.finish_combat()
