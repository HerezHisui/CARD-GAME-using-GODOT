extends Node
## A telegraphed encounter inspired by the reference's three-phase structure.
const BossRules = preload("res://scripts/boss_rules.gd")
## The Warden's numbers and names in one place. Same keys and values as the "warden" row of data/bosses.json.
## Used while BossRules.WARDEN_DATA_ENABLED is false.
const DEFAULTS := {
	"name": "MIDNIGHT WARDEN", "room": "boss", "floors": [3],
	"units": {
		"night_watch": {"name": "Night Watch", "role": "guard", "lane": 1,
			"attack": 1, "health": 4, "counter": "brace"},
		"hall_monitor": {"name": "Hall Monitor", "role": "guard", "lane": 2,
			"attack": 1, "health": 4, "counter": "evac"},
		"shackle": {"name": "Emergency Shackle", "role": "shackle", "lane": 3,
			"attack": 0, "health": 3, "counter": "evac"},
		"west_pillar": {"name": "West Circuit Pillar", "role": "pillar", "lane": 0,
			"attack": 0, "health": 5, "counter": "brace"},
		"east_pillar": {"name": "East Circuit Pillar", "role": "pillar", "lane": 3,
			"attack": 0, "health": 5, "counter": "evac"},
		"shield_guardian": {"name": "Shield Guardian", "role": "taunt", "lane": 1,
			"attack": 0, "health": 4, "counter": "brace"},
	},
	"opening": ["night_watch", "hall_monitor"],
	"guards": {"damage": 1, "on_boss_damaged": "Night Watch", "on_response": "Hall Monitor", "response_every": 2},
	"shield_at": 0.5,
	"empty_lane_cap": 2,
	"moves": {
		"shackle": {"every": 2, "unit": "shackle"},
		"blade_rush": {"lanes": [0, 2], "damage": 1, "bleed": 1},
		"punishment": {"lane": 1, "damage": 3, "damage_with_shackle": 4, "healing_reduced": 2},
		"shield_pulse": {"damage": 1, "spawn": ["west_pillar", "east_pillar", "shield_guardian"]},
		"lights_out": {"lock_rounds": 2, "bleed": 1, "lanes": [0, 2], "damage": 2},
	},
	"pillars": {"echo_from": "pillar0", "heal_from": "pillar3", "heal": 1},
	"static_echo": {"hand_full_damage": 1, "unresolved_damage": 1, "card": {"id": "static_echo",
		"name": "Static Echo", "type": "response", "element": "douse", "cost": 0, "utility": true,
		"effect": "draw", "draw_count": 1, "curse": true}},
	# Stored whole. A number changed above must be changed in its text too.
	"intents": {
		"pulse_next": "PHASE 2: next round, Shield Pulse (1 to all units) + two 5-HP pillars. Boss shielded.",
		"pillars": "PHASE 2: break both pillars. Guardian draws attacks; AoE and Ignore Taunt bypass it."
			+ " Static Echo costs 1 HP.",
		"phase_3": "PHASE 3: seal one hand card for 2 rounds; all units +1 Bleed, lanes 1 and 3 take 2 damage.",
		"phase_1_even": "PHASE 1: summon Shackle; Punishment hits lane 2 for 3 (4 with Shackle),"
			+ " healing reduced for 2 rounds.",
		"phase_1_odd": "PHASE 1: Blade Rush hits lanes 1 and 3 for 1 + Bleed; Punishment hits lane 2 for 3"
			+ " (4 if Shackle survives), healing reduced for 2 rounds.",
	},
}
var game: Node
var stage := 1
var changed_round := -1
var pillars_spawned := false
var pulse_resolved := false
var last_resolved_round := -1
var last_prepared_round := -1
var responses_played := 0
# The rules this fight reads. Picked on first use and never saved, because a Continue skips setup().
var loaded_rules: Dictionary = {}

## The Warden's numbers: his data row when it is on, else DEFAULTS.
func rules() -> Dictionary:
	if loaded_rules.is_empty():
		var row := BossRules.warden_row()
		if BossRules.on("warden", game.boss_rule_override) and not row.is_empty(): loaded_rules = whole_numbers(row)
		else: loaded_rules = DEFAULTS
	return loaded_rules

# JSON numbers are floats. Whole ones become int, so both sources give the same values.
static func whole_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = whole_numbers(value[key])
		return result
	if value is Array: return value.map(func(item): return whole_numbers(item))
	if value is float and value == floorf(value): return int(value)
	return value

func setup(manager: Node) -> void:
	game = manager
	game.enemy_deck.clear()
	game.enemy_hand.clear()
	game.enemy_evolution_deck.clear()
	for key in rules().opening: spawn_unit(key)

func spawn(title: String, role: String, lane: int, attack: int, health: int, counter: String) -> Node:
	var slot: Node3D = game._threat_slots()[lane]
	var previous = game._get_card_in_slot(slot)
	if previous:
		game.record_graveyard(previous, "Reclaimed")
		previous.remove_from_group("cards")
		previous.current_slot = null
		previous.queue_free()
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	# Brace beats Earthquake and Evac beats Typhoon, so Night Watch is Earthquake and Hall Monitor is Typhoon.
	var element := "earthquake" if counter == "brace" else "typhoon"
	card.setup({"id":role + str(lane), "name":title, "type":"disaster", "element":element, "cost_type":"sacrifice", "cost":0, "attack":attack, "health":health, "boss_role":role})
	card.in_hand = false
	card.current_slot = slot
	card.global_position = slot.global_position + Vector3(0, 0.02, 0)
	card._set_overlay(false)
	card._refresh_face()
	return card

# One unit of the rules by key, through spawn().
func spawn_unit(key: String) -> Node:
	var unit: Dictionary = rules().units[key]
	return spawn(unit.name, unit.role, unit.lane, unit.attack, unit.health, unit.counter)

# A living guard by name hits the Response tile across from it for 1.
func guard_hit(guard_name: String) -> void:
	var damage: int = rules().guards.damage
	for slot in game._threat_slots():
		var guard = game._get_card_in_slot(slot)
		if guard == null or not guard.is_alive() or guard.card_data.get("name", "") != guard_name: continue
		var target = game._get_card_in_slot(game._response_slots()[game._threat_slots().find(slot)])
		if target != null and target.is_alive():
			game.log_event("%s strikes %s for %d." % [guard_name, target.card_data.name, damage])
			target.take_damage(damage)

# Night Watch: the player damaged the Janitor.
func on_janitor_damaged() -> void:
	guard_hit(rules().guards.on_boss_damaged)

# Hall Monitor: every second Response card the player plays.
func on_response_played() -> void:
	responses_played += 1
	if responses_played % int(rules().guards.response_every) == 0: guard_hit(rules().guards.on_response)

func accept_damage(amount: int) -> int:
	if stage == 2: return 0
	if stage == 1:
		var threshold := ceili(game.enemy_max_hp * float(rules().shield_at))
		var accepted := mini(amount, maxi(0, game.enemy_hp - threshold))
		if game.enemy_hp - accepted <= threshold:
			stage = 2
			game.log_event("Warden enters the shielded pillar phase; pulse is announced for next round.")
			changed_round = game.turn
		return accepted
	return amount

func pillars() -> Array:
	return game._threat_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null and card.is_alive() and card.card_data.get("boss_role", "") == "pillar")

func has_pillar(id: String) -> bool:
	return pillars().any(func(card): return card.card_data.get("id", "") == id)

static func pillar_description(data: Dictionary) -> String:
	if data.get("boss_role", "") != "pillar": return ""
	var timing := "Once at round preparation, starting the round after spawning. Stops when this pillar leaves play. "
	match str(data.get("id", "")):
		"pillar0":
			return timing + "Add 1 additional Static Echo to your hand. If full, lose 1 HP instead."
		"pillar3":
			return timing + "Heal a living Shield Guardian by 1 HP, up to its maximum. Never revives it."
	return ""

func guardian() -> Node:
	for slot in game._threat_slots():
		var card = game._get_card_in_slot(slot)
		if card and card.is_alive() and card.card_data.get("boss_role", "") == "taunt": return card
	return null

func redirect_target(attacker: Node, target: Node) -> Node:
	if stage != 2 or target == null or target.card_data.get("boss_role", "") != "pillar" or (attacker.plan_ignore_taunt or attacker.card_data.get("ignore_taunt", false)): return target
	var guard := guardian()
	return guard if guard else target

func on_card_destroyed(card: Node) -> void:
	if stage != 2 or card.card_data.get("boss_role", "") != "pillar": return
	# One predictable recoil discard, rather than deleting the entire player's hand.
	var hand: Array = game.get_hand_cards().filter(func(unit): return not unit.card_data.get("curse", false))
	if not hand.is_empty():
		var discard = hand[hand.size() - 1]
		game.record_graveyard(discard, "Pillar recoil")
		game.hand.erase(discard)
		discard.in_hand = false
		discard.remove_from_group("cards")
		discard.queue_free()
		game.arrange_hand_centered()
	if pillars_spawned and pillars().all(func(pillar): return pillar == card):
		stage = 3
		changed_round = game.turn

func prepare_round() -> void:
	if last_prepared_round == game.turn: return
	last_prepared_round = game.turn
	if stage == 2 and pillars_spawned:
		var support: Dictionary = rules().pillars
		add_static_echo()
		if has_pillar(support.echo_from): add_static_echo()
		var guard := guardian()
		if has_pillar(support.heal_from) and guard != null and guard.card_data.health < guard.max_health:
			guard.heal(support.heal)
	if stage == 3:
		var targets: Array = game.get_hand_cards().filter(func(card): return not game.is_sealed(card.card_data))
		if not targets.is_empty():
			var target = targets[targets.size() - 1]
			target.card_data.locked_until = game.turn + int(rules().moves.lights_out.lock_rounds)
			target._refresh_face()

func add_static_echo() -> void:
	var echo: Dictionary = rules().static_echo
	if game.get_hand_cards().size() < game.HAND_SIZE_MAX: game.add_card_to_hand(echo.card)
	else: game._damage_side(true, echo.hand_full_damage, true)

func settle_curses() -> void:
	for card in game.get_hand_cards():
		if card.card_data.get("curse", false):
			game._damage_side(true, rules().static_echo.unresolved_damage, true)
			game.record_graveyard(card, "Unresolved curse")
			game.hand.erase(card)
			card.in_hand = false
			card.remove_from_group("cards")
			card.queue_free()
	game.arrange_hand_centered()

func intent() -> String:
	var texts: Dictionary = rules().intents
	if stage == 2:
		if not pulse_resolved: return texts.pulse_next
		return texts.pillars
	if stage == 3: return texts.phase_3
	if game.turn % int(rules().moves.shackle.every) == 0: return texts.phase_1_even
	return texts.phase_1_odd

func hit_lane(index: int, damage: int, bleed: int = 0, reduced_healing: bool = false) -> void:
	var card = game._get_card_in_slot(game._response_slots()[index])
	if card:
		card.take_damage(damage)
		if card.is_alive() and not card.last_evaded_hit:
			if bleed > 0: card.add_status("bleed", bleed)
			if reduced_healing: card.add_status("healing_reduced", rules().moves.punishment.healing_reduced)
	else: game._damage_side(true, mini(damage, rules().empty_lane_cap))

func resolve_intent() -> void:
	if last_resolved_round == game.turn: return
	last_resolved_round = game.turn
	if is_instance_valid(game.opponent_hand): game.opponent_hand.character.warden_pattern()
	game.log_event("Warden pattern: " + intent())
	settle_curses()
	if game._check_game_over(): return
	var moves: Dictionary = rules().moves
	if stage == 2:
		if not pulse_resolved and game.turn > changed_round:
			for slot in game._response_slots():
				var card = game._get_card_in_slot(slot)
				if card: card.take_damage(moves.shield_pulse.damage)
			# West pillar, east pillar, then the Shield Guardian: the order of the list.
			for key in moves.shield_pulse.spawn: spawn_unit(key)
			pillars_spawned = true
			pulse_resolved = true
			# Support begins next round, even if preparation is requested again after the pulse.
			last_prepared_round = game.turn
		return
	if stage == 3:
		if game.turn == changed_round: return # Give a full response turn before the new pattern.
		for slot in game._response_slots():
			var card = game._get_card_in_slot(slot)
			if card: card.add_status("bleed", moves.lights_out.bleed)
		for lane in moves.lights_out.lanes: hit_lane(lane, moves.lights_out.damage)
	else:
		if game.turn % int(moves.shackle.every) == 0:
			spawn_unit(moves.shackle.unit)
		else:
			for lane in moves.blade_rush.lanes: hit_lane(lane, moves.blade_rush.damage, moves.blade_rush.bleed)
		var shackled: bool = game._threat_slots().any(func(slot):
			var card = game._get_card_in_slot(slot)
			return card != null and card.card_data.get("boss_role", "") == "shackle"
		)
		var punishment: Dictionary = moves.punishment
		hit_lane(punishment.lane, punishment.damage_with_shackle if shackled else punishment.damage, 0, true)
	game._check_game_over()
