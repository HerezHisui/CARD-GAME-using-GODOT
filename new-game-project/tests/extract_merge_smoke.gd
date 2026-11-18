# Covers: contingency_rules.try_extract for Emergency Extraction, Kai's Duck and Robin's Second Wind.
# A pin: each case records the full result of one dodge call, so a refactor of the shared steps keeps it.
# Kits are reached only with game.leader_kit_override; every flag stays false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const ALL_DRILL := ["fall_in", "double_time", "lane_swap", "rally", "duck"]
# The tail of a dodge that did nothing: no move, no log, no popup.
const UNTOUCHED := "|evaded false|triggered false|bonus 0|dash -1/0|tokens 0|used false|log |popup "

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

# A battle on the player's turn, as leader_kai_smoke builds it. kit: "" (today's plans), "kai" or "robin".
func fixture(kit: String) -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.disaster_is_human = false
	game.balance_patch_override = null
	game.leader_kit_override = kit if kit != "" else null
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.reset_run()
	game.plans.set_kit(kit)
	if kit == "kai": game.plans.unlocked.assign(ALL_DRILL)
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

func card(name: String, lane: int, health: int, extra: Dictionary = {}) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	var data := {"name":name, "type":"response", "element":"evac", "cost":1, "attack":2, "health":10}
	data.merge(extra, true)
	result.setup(data)
	result.in_hand = false
	result.current_slot = lane_slot(lane)
	result.global_position = lane_slot(lane).global_position
	result.card_data.health = health
	return result

func lane_slot(index: int) -> Node3D:
	return game._response_slots()[index]

# Arm Emergency Extraction with the same four keys arm() builds.
func arm_extract(unit: Node, lane: int) -> void:
	game.plans.armed = {"kind":"extract", "targets":[unit], "destination":lane_slot(lane), "triggered":false}

# One try_extract call and everything it may change, as one line.
func dodge(unit: Node, damage: int) -> String:
	var before: int = game.battle_log.size()
	var saved: bool = game.plans.try_extract(unit, damage)
	var lines: Array = game.battle_log.slice(before)
	var popups: Array = []
	for label in unit._live_popups:
		if is_instance_valid(label): popups.append(label.text)
	return "%s|lane %d|hp %d|evaded %s|triggered %s|bonus %d|dash %d/%d|tokens %d|used %s|log %s|popup %s" % [
		saved, game._response_slots().find(unit.current_slot), int(unit.card_data.health), unit.last_evaded_hit,
		game.plans.armed.get("triggered", false), unit.plan_attack_bonus, int(unit.get_meta("dash_round", -1)),
		int(unit.get_meta("dash_attack", 0)), game.plans.tokens, game.plans.kit_used, " / ".join(lines),
		",".join(popups)]

func pin(actual: String, expected: String, message: String) -> void:
	check(actual == expected, "%s\n  got:  %s\n  want: %s" % [message, actual, expected])

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	check_extract()
	check_extract_balance()
	check_duck()
	check_second_wind()
	game.leader_kit_override = null
	game.balance_patch_override = null
	game.plans.set_kit("")
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("extract_merge_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: extract_merge_smoke (%d checks)" % checks)
	quit(0)

# 1. Emergency Extraction with no kit: the five cases.
func check_extract() -> void:
	var line := "Round 1 | Emergency Extraction saves Runner from a lethal attack."
	fixture("")
	var ally = card("Runner", 0, 2)
	arm_extract(ally, 2)
	pin(dodge(ally, 20), "true|lane 2|hp 2|evaded true|triggered true|bonus 0|dash -1/0|tokens 0|used false|log "
		+ line + "|popup EXTRACTED", "extraction: a lethal hit moves the ally to the empty lane")
	pin(dodge(ally, 20), "false|lane 2|hp 2|evaded true|triggered true|bonus 0|dash -1/0|tokens 0|used false|log |popup "
		+ "EXTRACTED", "extraction: already triggered, no second save")
	fixture("")
	ally = card("Runner", 0, 2)
	arm_extract(ally, 2)
	pin(dodge(ally, 1), "false|lane 0|hp 2" + UNTOUCHED,
		"extraction: a hit that is not lethal does nothing")
	fixture("")
	ally = card("Runner", 0, 2)
	card("Blocker", 2, 5)
	arm_extract(ally, 2)
	pin(dodge(ally, 20), "false|lane 0|hp 2" + UNTOUCHED,
		"extraction: a taken lane does nothing")
	fixture("")
	ally = card("Runner", 0, 2)
	var other = card("Other", 1, 5)
	arm_extract(other, 2)
	pin(dodge(ally, 20), "false|lane 0|hp 2" + UNTOUCHED,
		"extraction: the wrong unit does nothing")

# 1b. The balance patch adds the dash +1 for a unit with relocation_attack; off, it does not.
func check_extract_balance() -> void:
	var line := "Round 1 | Emergency Extraction saves Dasher from a lethal attack."
	for on in [true, false]:
		fixture("")
		game.encounter_kind = "versus"
		game.disaster_is_human = true
		game.balance_patch_override = on
		check(game.balance_enabled() == on, "the balance patch is %s" % on)
		var ally = card("Dasher", 0, 2, {"relocation_attack":1})
		check(int(ally.card_data.get("relocation_attack", 0)) == 1, "the dasher keeps relocation_attack")
		arm_extract(ally, 3)
		var dash := "bonus 1|dash 1/1" if on else "bonus 0|dash -1/0"
		pin(dodge(ally, 20), "true|lane 3|hp 2|evaded true|triggered true|%s|tokens 0|used false|log %s|popup EXTRACTED"
			% [dash, line], "extraction with balance %s" % on)
	game.encounter_kind = "battle"
	game.disaster_is_human = false
	game.balance_patch_override = null

# Arm Duck as a player does, through use_kit_effect, with 1 Tempo that it spends.
func arm_duck(unit: Node, lane: int) -> void:
	game.plans.tokens = 1
	check(game.plans.use_kit_effect("duck", unit, lane_slot(lane)), "Duck arms on %s" % unit.card_data.name)

# 2. Kai's Duck: the same five cases, and the Tempo from the dodge.
func check_duck() -> void:
	var line := "Round 1 | Duck saves Ducker from a lethal attack. / Round 1 | Ducker changes lane: Tempo 1/3."
	fixture("kai")
	var ally = card("Ducker", 0, 4)
	arm_duck(ally, 2)
	pin(dodge(ally, 10), "true|lane 2|hp 4|evaded true|triggered true|bonus 0|dash -1/0|tokens 1|used false|log "
		+ line + "|popup DUCKED", "Duck: a lethal hit moves the unit and gives 1 Tempo")
	pin(dodge(ally, 10), "false|lane 2|hp 4|evaded true|triggered true|bonus 0|dash -1/0|tokens 1|used false|log |popup "
		+ "DUCKED", "Duck: already triggered, no second dodge")
	fixture("kai")
	ally = card("Ducker", 0, 4)
	arm_duck(ally, 2)
	pin(dodge(ally, 1), "false|lane 0|hp 4" + UNTOUCHED,
		"Duck: a hit that is not lethal does nothing")
	fixture("kai")
	ally = card("Ducker", 0, 4)
	arm_duck(ally, 2)
	# The lane fills after Duck is armed.
	card("Blocker", 2, 5)
	pin(dodge(ally, 10), "false|lane 0|hp 4" + UNTOUCHED,
		"Duck: a taken lane does nothing")
	fixture("kai")
	ally = card("Ducker", 0, 4)
	var other = card("Other", 1, 5)
	arm_duck(other, 2)
	pin(dodge(ally, 10), "false|lane 0|hp 4" + UNTOUCHED,
		"Duck: the wrong unit does nothing")

# 3. Robin's Second Wind: one lethal hit leaves 1 HP, the next is not saved.
func check_second_wind() -> void:
	fixture("robin")
	var ally = card("Ally", 0, 4)
	pin(dodge(ally, 10), "true|lane 0|hp 1|evaded false|triggered false|bonus 0|dash -1/0|tokens 0|used true|log "
		+ "Round 1 | Second Wind keeps Ally at 1 HP.|popup SECOND WIND", "Second Wind saves one lethal hit")
	pin(dodge(ally, 10), "false|lane 0|hp 1|evaded false|triggered false|bonus 0|dash -1/0|tokens 0|used true|log "
		+ "|popup SECOND WIND", "Second Wind is spent for the battle")
