extends SceneTree
## The Midnight Warden plays one fixed, scripted fight. Every step is written down and hashed.
## PINNED was taken from final_boss.gd before its numbers moved to data, so it must never change.
const BOSS_FIELDS: Array = preload("res://scripts/run_save.gd").BOSS_FIELDS
const BossRules = preload("res://scripts/boss_rules.gd")
const DEFAULTS: Dictionary = preload("res://scripts/final_boss.gd").DEFAULTS
const PINNED := "e912990a797ffce073dc8a9b8be6c3d8746052d4aefc0f896fa521478995b2a5"
var game: Node
var director: Node
var boss: Node
var failures := 0
var entries: Array = []
var log_mark := 0
# True when the last fight read the data row. DEFAULTS is a const, so it is read-only.
var used_row := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

# Waits in frames, never on the clock.
func wait_frames(count: int) -> void:
	for i in mini(count, 600):
		await process_frame

# A plain Response unit: no evade, no random effect.
func place(title: String, lane: int) -> Node:
	var slot: Node3D = game._response_slots()[lane]
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup({"name": title, "type": "response", "element": "brace", "cost": 1, "attack": 1, "health": 20})
	result.in_hand = false
	result.current_slot = slot
	result.global_position = slot.global_position + Vector3(0, 0.02, 0)
	result._set_overlay(false)
	return result

# The card in one slot, or null.
func unit(slot: Node3D) -> Variant:
	var card = game._get_card_in_slot(slot)
	if card == null: return null
	var data: Dictionary = card.card_data
	return [data.get("name"), data.get("id"), data.get("element"), data.get("attack"), data.get("health"),
		card.max_health, data.get("boss_role"), card.statuses.duplicate(true), card.modifiers.duplicate(true)]

# One entry per step: intent, saved boss fields, both HPs, all eight slots, the hand and the new log lines.
func step(title: String) -> void:
	var fields := {}
	for field in BOSS_FIELDS: fields[field] = boss.get(field)
	var lanes: Array = []
	for slot in game._threat_slots() + game._response_slots(): lanes.append(unit(slot))
	var hand: Array = []
	for card in game.get_hand_cards():
		hand.append([card.card_data.get("name"), card.card_data.get("curse"), card.card_data.get("locked_until")])
	entries.append({"step": title, "intent": boss.intent(), "boss": fields, "player_hp": game.player_hp,
		"enemy_hp": game.enemy_hp, "lanes": lanes, "hand": hand, "log": game.battle_log.slice(log_mark)})
	log_mark = game.battle_log.size()

func pillar(id: String) -> Node:
	for card in boss.pillars():
		if card.card_data.get("id", "") == id: return card
	return null

# The whole scripted fight. Returns the digest of its entries.
func fight(override: Variant) -> String:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.encounter_kind = "boss"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 1
	game.energy_cap = 10
	game.preparedness = 10
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game.player_hp = 20
	seed(20261117)
	entries = []
	log_mark = game.battle_log.size()
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	boss = game.final_boss
	boss.setup(game)
	step("setup: both guards")
	# Round 1: phase 1, odd round.
	var left := place("Left", 0)
	var middle := place("Middle", 1)
	place("Right", 2)
	step("round 1: three Response units, lane 4 empty")
	boss.prepare_round()
	step("round 1: prepare does nothing in phase 1")
	game._damage_side(false, 3)
	step("round 1: boss damaged, Night Watch answers")
	boss.on_response_played()
	step("round 1: first Response card, no answer")
	boss.on_response_played()
	step("round 1: second Response card, Hall Monitor answers")
	boss.resolve_intent()
	step("round 1: Blade Rush and Punishment for 3")
	boss.resolve_intent()
	step("round 1: second resolve does nothing")
	# Round 2: even round, the Shackle.
	game.turn = 2
	boss.prepare_round()
	step("round 2: prepare")
	boss.resolve_intent()
	step("round 2: Shackle and Punishment for 4")
	# Round 3: Punishment into an empty lane, then the shield.
	game.turn = 3
	middle.take_damage(99)
	step("round 3: middle unit destroyed")
	boss.resolve_intent()
	step("round 3: Blade Rush, Punishment 4 into an empty lane")
	game._damage_side(false, 100)
	step("round 3: damage past half thrown away, shield up")
	game._damage_side(false, 5)
	step("round 3: shielded boss takes nothing")
	# Round 4: Shield Pulse and the three spawns.
	game.turn = 4
	boss.prepare_round()
	step("round 4: prepare, no pillars yet")
	place("Middle Two", 1)
	step("round 4: new middle unit")
	boss.resolve_intent()
	step("round 4: Shield Pulse, west pillar, east pillar, Shield Guardian")
	boss.prepare_round()
	step("round 4: prepare again, support waits a round")
	boss.guardian().take_damage(2)
	step("round 4: Shield Guardian hit for 2")
	# Round 5: two Echoes, the heal, a redirect, unresolved Echoes.
	game.turn = 5
	boss.prepare_round()
	step("round 5: two Echoes, east pillar heals the Guardian")
	boss.prepare_round()
	step("round 5: second prepare does nothing")
	var west := pillar("pillar0")
	var east := pillar("pillar3")
	step("round 5: attack on west pillar goes to " + str(boss.redirect_target(left, west).card_data.name))
	boss.resolve_intent()
	step("round 5: unresolved Echoes cost HP")
	boss.resolve_intent()
	step("round 5: second resolve does nothing")
	# Round 6: an Echo into a full hand, the west pillar falls.
	game.turn = 6
	for i in 7:
		game.add_card_to_hand({"name": "Plain %d" % i, "type": "response", "element": "brace", "cost": 1,
			"attack": 1, "health": 2})
	step("round 6: hand of seven")
	boss.prepare_round()
	step("round 6: Echo fills the hand, second Echo costs 1 HP")
	west.take_damage(99)
	step("round 6: west pillar destroyed, recoil discard")
	boss.resolve_intent()
	step("round 6: unresolved Echo costs HP")
	# Round 7: the east pillar falls, phase 3 waits a round.
	game.turn = 7
	boss.prepare_round()
	step("round 7: one Echo only")
	east.take_damage(99)
	step("round 7: both pillars destroyed, phase 3")
	boss.resolve_intent()
	step("round 7: phase 3 gives a full response round")
	# Rounds 8 and 9: phase 3.
	game.turn = 8
	left.take_damage(99)
	step("round 8: left unit destroyed")
	boss.prepare_round()
	step("round 8: phase 3 lock")
	boss.prepare_round()
	step("round 8: second prepare does nothing")
	boss.resolve_intent()
	step("round 8: Bleed to all, lanes 1 and 3 take 2, lane 1 empty")
	boss.resolve_intent()
	step("round 8: second resolve does nothing")
	game.turn = 9
	boss.prepare_round()
	step("round 9: phase 3 lock on the next card")
	boss.resolve_intent()
	step("round 9: phase 3 again")
	check(game.battle_log.size() < 300, "the log never dropped a line")
	var digest := JSON.stringify(entries, "", true).sha256_text()
	used_row = not boss.rules().is_read_only()
	# Leave the fixture clean, so the fight can run again.
	game.clear_battle()
	await wait_frames(2)
	return digest

# Walks both values. A JSON number 1.0 and an int 1 count as equal.
func same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers: return float(a) == float(b)
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not same(a[i], b[i]): return false
		return true
	return a == b

# A clean board on round 1 with no boss yet.
func fresh(override: Variant) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.encounter_kind = "boss"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 1
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game.player_hp = 20

# The intent panel shows the Warden's own text, and no boss rule takes the fight.
func panel_check(override: Variant) -> void:
	await fresh(override)
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	game.board_input.clear()
	await wait_frames(2)
	var label: Label = director.boss_intent
	check(BossRules.boss_id(game) == "", "override %s: boss_id stays empty for the Warden" % str(override))
	check(label.get_parent().visible and label.text == DEFAULTS.intents.phase_1_odd,
		"override %s: the intent panel shows the Warden's text (got '%s')" % [str(override), label.text])
	game.clear_battle()
	await wait_frames(2)

# A Continue: the script is made the way run_save.gd does it, with no setup(), then phase 3 is applied.
func continue_check(override: Variant) -> void:
	await fresh(override)
	game.turn = 8
	for i in 3:
		game.add_card_to_hand({"name": "Kept %d" % i, "type": "response", "element": "brace", "cost": 1,
			"attack": 1, "health": 2})
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.game = game
	# Saved fields come back from JSON, so numbers are floats here, as in a real save.
	var saved: Dictionary = JSON.parse_string('{"stage": 3, "changed_round": 7, "pillars_spawned": true,'
		+ ' "pulse_resolved": true, "last_resolved_round": 7, "last_prepared_round": 7}')
	for key in BOSS_FIELDS:
		if saved.has(key): game.final_boss.set(key, saved[key])
	game.final_boss.prepare_round()
	var hand: Array = game.get_hand_cards()
	var newest = hand[hand.size() - 1]
	check(int(newest.card_data.get("locked_until", 0)) == 10 and game.is_sealed(newest.card_data),
		"override %s: after a Continue the newest card is locked for 2 rounds" % str(override))
	check(game.final_boss.rules().is_read_only() == (override == null),
		"override %s: the Continue reads the right source" % str(override))
	game.clear_battle()
	await wait_frames(2)

# One entry per line, so a mismatch can be diffed.
func save_trace(suffix: String) -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/notes/warden-parity-trace-%s.txt" % suffix)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	for entry in entries: file.store_line(JSON.stringify(entry, "", true))

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	paused = false
	var digest: String = await fight(null)
	print("warden_parity_smoke digest " + digest)
	if PINNED == "": save_trace("old")
	else:
		check(digest == PINNED, "the fight matches the code before the move")
		if digest != PINNED: save_trace("new")
	check(not used_row, "override null: the Warden reads DEFAULTS")
	# The same fight, read from the data row.
	var row_digest: String = await fight("warden")
	print("warden_parity_smoke digest with override warden " + row_digest)
	check(row_digest == PINNED, "override warden: the fight matches the code before the move")
	if row_digest != PINNED: save_trace("new-warden")
	check(used_row, "override warden: the Warden reads the data row")
	check(not BossRules.WARDEN_DATA_ENABLED, "the warden data flag stays false")
	check(not BossRules.warden_row().is_empty() and same(DEFAULTS, BossRules.warden_row()),
		"DEFAULTS and the warden row are equal, key for key")
	await panel_check("warden")
	await continue_check(null)
	await continue_check("warden")
	if failures > 0:
		quit(1)
		return
	print("PASS: warden_parity_smoke")
	quit(0)
