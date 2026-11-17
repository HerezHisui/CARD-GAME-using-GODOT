# Covers: Kai's Drill kit (leader_kits.gd) through game.plans: Tempo from lane changes, no banking, the five
# Formations, board picks, saves and Versus.
# The kit is reached only with game.leader_kit_override; the flag stays false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const LeaderKits = preload("res://scripts/leader_kits.gd")
const ALL_DRILL := ["fall_in", "double_time", "lane_swap", "rally", "duck"]

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

# A battle on the player's turn, as leader_sage_smoke builds it, with the whole Drill kit owned.
func fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.set_kit("kai")
	game.plans.auto_save = true
	game.plans.unlocked.assign(ALL_DRILL)
	game.plans.tokens = 0
	game.turn = 1
	game.player_hp = 20
	game.player_barrier = 0
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 3
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

func lane(index: int) -> Node3D:
	return game._response_slots()[index]

func next_round() -> void:
	game.turn += 1

func has_popup(unit: Node, text: String) -> bool:
	return unit._live_popups.any(func(label): return is_instance_valid(label) and label.text == text)

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

# Wait until the camera stops moving (board view), capped at 600 frames.
func camera_still() -> void:
	var last: Transform3D = game.camera.global_transform
	for i in 600:
		await process_frame
		var now: Transform3D = game.camera.global_transform
		if i > 5 and now.is_equal_approx(last): return
		last = now

# A real End Turn, as contingency_plans_smoke plays one: a harmless enemy unit, then wait for the next turn.
func end_turn() -> void:
	game.disaster_is_human = false
	game.player_first = true
	card("Holdout", 3, 30, "disaster", {"attack":0, "health":30, "element":"flood"})
	await game._on_end_turn_pressed()
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY, game.Phase.GAME_OVER]: break
		await process_frame

func saved_lines() -> int:
	return game.battle_log.filter(func(line): return "Saved 2 energy" in str(line)).size()

func run() -> void:
	# The small window size, so real board clicks land and the drag prompt is checked at 1280x720.
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	await check_flag_off()
	check_kai_start()
	await check_no_bank()
	await check_fall_in_input()
	check_cap()
	check_move_card()
	check_lanes()
	check_double_time()
	check_lane_swap()
	check_rally()
	check_duck()
	check_crosswind()
	check_one_per_round()
	check_save()
	check_versus()
	await check_armed_frames()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("leader_kai_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: leader_kai_smoke (%d checks)" % checks)
	quit(0)

# 1. Flag false and no override: the Evacuation Club row is off, a move gives nothing, End Turn banks as today.
func check_flag_off() -> void:
	check(game.leader_kit_override == null, "the override starts as null")
	check(not director.character_available(1), "flag off: the Evacuation Club leader is not available")
	director.selected_character = 1
	director.new_run()
	check(director.selected_character == 0 and game.plans.kit_id() == "", "flag off: falls back to Steve, no kit")
	game.leader_kit_override = "sage"
	check(not director.character_available(1), "Sage's override does not turn Kai on")
	game.leader_kit_override = null
	fixture()
	game.plans.set_kit("")
	var ally = card("Walker", 0, 5)
	game.apply_relocation(ally, lane(2), null)
	check(ally.current_slot == lane(2) and game.plans.tokens == 0, "flag off: a relocation gives no token")
	game.preparedness = 2
	await end_turn()
	check(game.turn == 2 and game.plans.tokens == 1 and saved_lines() == 1, "flag off: End Turn banks as today")

# 2. Override "kai": the row is on and the run starts with the Drill kit.
func check_kai_start() -> void:
	game.leader_kit_override = "kai"
	check(director.character_available(1), "override: the Evacuation Club leader is available")
	check(not director.character_available(2) and not director.character_available(3)
		and director.character_available(0), "override: other rows as today")
	director.selected_character = 1
	director.new_run()
	check(director.selected_character == 1, "override: the run keeps Kai")
	check(game.plans.kit == "kai" and game.plans.kit_id() == "kai", "override: the run has the Drill kit")
	check(game.plans.unlocked == ["fall_in", "double_time"], "override: start with Fall In and Double Time")
	check(director.coins == 35, "override: Kai starts with 35 supplies")
	check(game.player_hp == 20 and game.plans.cap() == 3, "override: Kai has 20 HP and a cap of 3")
	check(game.player_run_buffs.has("marshal"), "override: Kai keeps the marshal buff")
	game.leader_kit_override = null

# 3. End Turn with unused energy saves nothing.
func check_no_bank() -> void:
	fixture()
	game.preparedness = 2
	check(not game.plans.bank_unused_energy() and game.preparedness == 2, "Kai: bank_unused_energy saves nothing")
	await end_turn()
	check(game.turn == 2 and game.plans.tokens == 0 and saved_lines() == 0, "Kai: End Turn saves nothing")

# 4. Fall In through real input: P, a click on the tile, a real drag onto an empty lane. Costs 0, gives 1 Tempo.
func check_fall_in_input() -> void:
	fixture()
	var ally = card("Runner", 0, 5)
	await frames(3)
	await key(KEY_P)
	check(director.screen == "plans" and director.modal.visible, "P opens the Drill screen")
	check(director.content.get_child(0).text == "THE DRILL", "the title is THE DRILL")
	check(director.content.get_node("Status").text == "TEMPO 0 / 3", "the status reads TEMPO 0 / 3")
	check(director.plans_button.get_node("CountLabel").text == "0/3", "the count label reads 0/3")
	var subtitle: Array = director.content.find_children("*", "Label", true, false).filter(
		func(node): return node.text == LeaderKits.kit("kai").subtitle)
	check(subtitle.size() == 1 and subtitle[0].get_line_count() <= 2, "the Drill subtitle fits on one or two lines")
	var list: Node = director.content.get_node("Scroll/List")
	var fall: Button = list.get_child(0).get_node("Box/PickButton")
	check(fall.text == "Fall In · 0 Tempo" and not fall.disabled, "the Fall In tile reads Fall In · 0 Tempo")
	var double: Button = list.get_child(1).get_node("Box/PickButton")
	check(double.disabled, "Double Time is off with 0 Tempo")
	await click(fall)
	check(not director.modal.visible, "Fall In closes the screen")
	check(game.board_input.action.get("kind", "") == "relocate", "Fall In opens a board drag")
	check(game.board_input.action.get("title", "") == "Drag a unit onto an empty lane for Fall In.",
		"the drag prompt names Fall In")
	await camera_still()
	var from: Vector2 = game.camera.unproject_position(ally.global_position)
	var to: Vector2 = game.camera.unproject_position(lane(2).global_position)
	check(game.card_at_board_position(from) == ally, "the press point is on the unit")
	await mouse_move(from)
	await mouse_button(from, true)
	check(ally.is_dragging and ally.is_relocating, "a real press lifts the unit like a relocation")
	for i in 10: await mouse_move(from.lerp(to, (i + 1) / 10.0))
	await frames(10)
	await mouse_button(to, false)
	await frames(2)
	check(ally.current_slot == lane(2) and not ally.is_dragging, "a real drag moves the unit to the empty lane")
	check(game.plans.tokens == 1, "the move gives 1 Tempo")
	check(game.plans.committed_round == game.turn, "Fall In is the round's kit effect, at 0 cost")
	check(game.board_input.action.is_empty(), "the drag is over")
	await mouse_away()
	ally.free()
	paused = false

# 5. Tempo cap: a move at 3 Tempo leaves it at 3.
func check_cap() -> void:
	fixture()
	var ally = card("Capped", 0, 5)
	game.plans.tokens = 3
	game.apply_relocation(ally, lane(1), null)
	check(ally.current_slot == lane(1) and game.plans.tokens == 3, "a move at 3 Tempo leaves it at 3")

# 6. A move card gives Tempo and leaves the round's kit effect free.
func check_move_card() -> void:
	fixture()
	var ally = card("Rescued", 0, 5)
	var route = card("Route", 1, 3)
	route.card_data = director.catalog_card("evacuation").duplicate(true)
	check(route.card_data.get("effect", "") == "move_ally", "Evacuation Route is a move card")
	game.begin_move_effect(route)
	game.select_moving_ally(ally)
	game.complete_move_effect(lane(3))
	check(ally.current_slot == lane(3) and game.plans.tokens == 1, "Evacuation Route gives 1 Tempo")
	check(game.plans.committed_round != game.turn and game.plans.kit_available("fall_in"),
		"the move card does not use the round's kit effect")

# 7. Full lanes, one unit, empty board.
func check_lanes() -> void:
	fixture()
	game.plans.tokens = 3
	game.preparedness = 1
	for id in ["fall_in", "lane_swap", "rally", "duck"]:
		check(not game.plans.kit_available(id), "empty board: %s is off" % id)
	check(game.plans.kit_available("double_time"), "empty board: Double Time can be on")
	var only = card("Only", 1, 5)
	check(not game.plans.kit_available("lane_swap"), "one unit: Lane Swap is off")
	check(game.plans.kit_available("fall_in") and game.plans.kit_available("rally")
		and game.plans.kit_available("duck"), "one unit: Fall In, Rally and Duck are on")
	for i in [0, 2, 3]: card("Full %d" % i, i, 5)
	check(not game.plans.kit_available("fall_in") and not game.plans.kit_available("duck"),
		"full lanes: Fall In and Duck are off")
	check(game.plans.kit_available("lane_swap"), "full lanes: Lane Swap is on")
	check(not game.plans.use_kit_effect("fall_in", only, lane(2)) and game.plans.tokens == 3,
		"full lanes: Fall In is refused and costs nothing")

# 8. Double Time: off at full energy, returns 2 up to the cap, costs 2 Tempo.
func check_double_time() -> void:
	fixture()
	game.plans.tokens = 3
	check(not game.plans.kit_available("double_time"), "Double Time is off at full energy")
	game.preparedness = 1
	check(game.plans.use_kit_effect("double_time") and game.preparedness == 3, "Double Time returns 2 energy")
	check(game.plans.tokens == 1, "Double Time costs 2 Tempo")
	next_round()
	game.plans.tokens = 2
	game.preparedness = 2
	check(game.plans.use_kit_effect("double_time") and game.preparedness == 3, "Double Time never passes the cap")

# 9. Lane Swap: two neighbours trade lanes through two board picks; costs 1 Tempo and gives none back.
func check_lane_swap() -> void:
	fixture()
	game.plans.tokens = 2
	var left = card("Left", 0, 5)
	var right = card("Right", 1, 5)
	var far = card("Far", 3, 5)
	check(not game.plans.use_kit_effect("lane_swap", left, far) and game.plans.tokens == 2,
		"Lane Swap refuses units that are not neighbours")
	director.begin_tactic("lane_swap")
	check(game.board_input.action.get("kind", "") == "pick" and far not in game.board_input.action.cards,
		"the first pick offers only units with a neighbour")
	game.board_input.click_card(left)
	check(game.board_input.action.get("cards", []) == [right], "the second pick offers the neighbours")
	game.board_input.cancel()
	check(game.plans.tokens == 2 and game.plans.committed_round != game.turn and left.current_slot == lane(0),
		"Esc at the second pick spends nothing")
	director.begin_tactic("lane_swap")
	game.board_input.click_card(left)
	game.board_input.click_card(right)
	check(left.current_slot == lane(1) and right.current_slot == lane(0), "the two units trade lanes")
	check(game.plans.tokens == 1, "Lane Swap costs 1 Tempo and gives none back")
	check(game.board_input.action.is_empty(), "the picks are over")

# 10. Rally: the unit and each direct neighbour get +1 before and in combat; an empty lane breaks the link.
func check_rally() -> void:
	fixture()
	game.plans.tokens = 2
	var left = card("Left", 0, 5)
	var center = card("Center", 1, 5)
	var past_gap = card("Past gap", 3, 5)
	check(game.plans.use_kit_effect("rally", center), "Rally can be armed on one unit")
	check(game.plans.armed.size() == 4 and game.plans.armed.kind == "rally" and game.plans.armed.targets == [center],
		"Rally arms with the same four keys and its unit")
	check(game.plans.tokens == 0, "Rally costs 2 Tempo")
	game.plans.preview_attack()
	check(left.plan_attack_bonus == 1 and center.plan_attack_bonus == 1 and past_gap.plan_attack_bonus == 0,
		"Rally shows +1 on the unit and its neighbour before combat; the lane past a gap gets none")
	game.plans.apply_combat()
	check(left.effective_attack() == 3 and center.effective_attack() == 3 and past_gap.effective_attack() == 2,
		"Rally deals its +1 in combat")
	game.plans.finish_combat()
	check(left.effective_attack() == 2 and center.effective_attack() == 2, "Rally ends with the combat")

# 11. Duck: a lethal attack hit moves the unit to its lane and gives 1 Tempo; a non-lethal hit does not.
func check_duck() -> void:
	fixture()
	game.plans.tokens = 1
	var ally = card("Ducker", 0, 4)
	check(not game.plans.use_kit_effect("duck", ally, lane(0)), "Duck refuses a lane that is taken")
	check(game.plans.use_kit_effect("duck", ally, lane(2)), "Duck can be armed with a unit and an empty lane")
	check(game.plans.armed.targets == [ally] and game.plans.armed.destination == lane(2) and game.plans.tokens == 0,
		"Duck keeps its unit and lane and costs 1 Tempo")
	game.plans.apply_combat()
	ally.take_damage(1)
	check(ally.card_data.health == 3 and ally.current_slot == lane(0) and game.plans.tokens == 0,
		"a non-lethal hit does not trigger Duck")
	ally.take_damage(10)
	check(ally.is_alive() and ally.card_data.health == 3 and ally.current_slot == lane(2), "Duck dodges the lethal hit")
	check(game.plans.tokens == 1 and has_popup(ally, "DUCKED") and game.plans.armed.triggered,
		"the dodge gives 1 Tempo and shows DUCKED")
	ally.take_damage(10)
	check(not ally.is_alive(), "Duck works only once")
	game.plans.finish_combat()

# 12. A Disaster unit moved by Crosswind gives no Tempo.
func check_crosswind() -> void:
	fixture()
	var foe = card("Blown", 0, 5, "disaster")
	game.apply_relocation(foe, game._threat_slots()[2], null)
	check(foe.current_slot == game._threat_slots()[2] and game.plans.tokens == 0, "an enemy unit's move gives no Tempo")

# 13. One kit effect per round, and Tempo is 0 at the start of the next battle.
func check_one_per_round() -> void:
	fixture()
	game.plans.tokens = 3
	game.preparedness = 1
	var ally = card("Busy", 0, 5)
	check(game.plans.use_kit_effect("double_time"), "the first kit effect this round works")
	check(not game.plans.kit_available("fall_in") and not game.plans.use_kit_effect("fall_in", ally, lane(1)),
		"a second kit effect in the same round is refused")
	check(ally.current_slot == lane(0) and game.plans.tokens == 1, "the refused effect costs nothing")
	game.clear_battle()
	check(game.plans.tokens == 0 and game.plans.kit == "kai", "Tempo is 0 at the start of the next battle")

func saved_plans() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(director.persistence.save_path()))
	return data.get("plans", {}) if data is Dictionary else {}

# 14a. Save and resume with Duck armed keeps the unit, the lane and the Tempo.
func check_save() -> void:
	fixture()
	director.run_active = true
	game.plans.tokens = 3
	var ally = card("Saved", 1, 4)
	check(game.plans.use_kit_effect("duck", ally, lane(3)), "Duck armed before the save")
	check(director.persistence.checkpoint(), "a Kai battle checkpoints")
	check(saved_plans().get("kit", "") == "kai", "the save holds the kit")
	game.plans.armed.clear()
	game.plans.tokens = 0
	game.plans.kit = ""
	check(director.persistence.resume(), "the Kai run resumes")
	var unit = game._get_card_in_slot(lane(1))
	check(game.plans.kit == "kai" and game.plans.tokens == 2, "resume keeps the kit and the Tempo")
	check(game.plans.armed.get("kind", "") == "duck" and game.plans.armed.targets.size() == 1
		and unit != null and game.plans.armed.targets[0] == unit, "resume keeps Duck on its one unit")
	check(game.plans.armed.destination == lane(3), "resume keeps Duck's lane")
	game.plans.finish_combat()
	director.close_modal()
	paused = false

# 14b. A Versus match during a Kai run uses today's plans: a move gives nothing and End Turn banks as today.
func check_versus() -> void:
	game.clear_battle()
	game.plans.set_kit("kai")
	game.plans.unlocked.assign(["fall_in", "double_time", "duck"])
	director.start_versus_match()
	check(game.encounter_kind == "versus", "the Versus match started")
	check(game.plans.kit_id() == "" and game.plans.cap() == 2, "Versus: no kit in the match")
	check(game.plans.unlocked == ["brace", "coordinate", "medicine"], "Versus: today's three tactics")
	var ally = card("Visitor", 0, 5)
	game.plans.tokens = 0
	game.apply_relocation(ally, lane(2), null)
	check(ally.current_slot == lane(2) and game.plans.tokens == 0, "Versus: a move gives no Tempo")
	game.preparedness = 2
	game.plans.saved_round = -1
	check(game.plans.bank_unused_energy() and game.plans.tokens == 1, "Versus: End Turn banks energy as today")
	ally.free()
	director.battle_finished(true)
	check(game.plans.kit == "kai", "after Versus: the run's kit is intact")
	check(game.plans.unlocked == ["fall_in", "double_time", "duck"], "after Versus: the run's unlocked list is intact")
	director.close_modal()
	paused = false

# 15. Rally armed for 120 battle frames: preview_attack runs every frame without an error.
func check_armed_frames() -> void:
	fixture()
	game.disaster_is_human = false
	game.plans.tokens = 2
	var left = card("Steady", 0, 5)
	var right = card("Ready", 1, 5)
	check(game.plans.use_kit_effect("rally", left), "Rally armed for the frame check")
	for i in 120: await process_frame
	check(game.plans.armed.get("kind", "") == "rally" and left.plan_attack_bonus == 1 and right.plan_attack_bonus == 1,
		"Rally stays armed and shows +1 over 120 frames")
	game.plans.finish_combat()
