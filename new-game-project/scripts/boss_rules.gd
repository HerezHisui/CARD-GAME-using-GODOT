extends RefCounted
## Boss rules read from data/bosses.json. Static functions only: no instance and no state.
## The lane comes from the round, the phase from HP, and "moved once" from where the card is.
## So nothing has to be saved and Continue needs no change.

const UI = preload("res://scripts/ui_theme.gd")
const PATH := "res://data/bosses.json"
## Off until it is play-tested. Tests turn it on with game.boss_rule_override.
const GUARDIAN_ENABLED := false
## The Janitor's CLOSING TIME. Off until it is play-tested, the same way.
const JANITOR_ENABLED := false
## The Midnight Warden reads his numbers from his row. Off until it is play-tested, the same way.
const WARDEN_DATA_ENABLED := false

# The parsed file, read once. null until the first read.
static var _rows: Variant = null

## All boss rows. {} when the file is missing or broken.
static func rows() -> Dictionary:
	if _rows == null:
		_rows = {}
		var file := FileAccess.open(PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
				_rows = json.data
	return _rows

## The Midnight Warden's row. {} when it is missing. boss_id() never returns "warden".
static func warden_row() -> Dictionary:
	return rows().get("warden", {})

## A String override picks one boss id. Otherwise the boss's own flag decides.
static func on(id: String, override: Variant) -> bool:
	if override is String: return id == override
	if id == "guardian": return GUARDIAN_ENABLED
	if id == "janitor": return JANITOR_ENABLED
	if id == "warden": return WARDEN_DATA_ENABLED
	return false

## The boss rule for this fight, or "" when none is on.
## The Guardian: elite rooms only. The Janitor: boss rooms on its floors, never with the Warden.
static func boss_id(game: Node) -> String:
	if game.encounter_kind == "elite" and on("guardian", game.boss_rule_override):
		return "guardian" if rows().has("guardian") else ""
	if game.encounter_kind != "boss" or is_instance_valid(game.final_boss): return ""
	if not on("janitor", game.boss_rule_override) or not rows().has("janitor"): return ""
	# JSON numbers are floats, so compare as int.
	var floor_number := int(game.run_director.floor_number)
	for item in rows().janitor.get("floors", []):
		if int(item) == floor_number: return "janitor"
	return ""

## Phase number, 1 first: the last row whose hp_at_or_below is at or above the HP share.
static func phase(game: Node) -> int:
	var id := boss_id(game)
	if id == "": return 0
	var share := float(game.enemy_hp) / maxi(1, int(game.enemy_max_hp))
	var phases: Array = rows()[id].phases
	var result := 1
	for i in phases.size():
		if float(phases[i].hp_at_or_below) >= share: result = i + 1
	return result

## Lane index of a living Disaster card with this id, or -1.
static func on_board(game: Node, card_id: String) -> int:
	if boss_id(game) == "": return -1
	var slots: Array = game._threat_slots()
	for i in slots.size():
		var card = game._get_card_in_slot(slots[i])
		if card != null and card.is_alive() and str(card.card_data.get("id", "")) == card_id: return i
	return -1

## This round's checkpoint lane (0 to 3), or -1 when no rule is on.
static func checkpoint_lane(game: Node) -> int:
	var id := boss_id(game)
	if id == "": return -1
	var row: Dictionary = rows()[id]
	# Only the checkpoint rule has lanes.
	if str(row.rule.get("id", "")) != "checkpoint": return -1
	var step: Dictionary = row.phases[phase(game) - 1]
	# Lockdown: the checkpoint stays on the signature card while it lives.
	if step.has("stay_on"):
		var lane := on_board(game, str(step.stay_on))
		if lane >= 0: return lane
	var lanes: Array = row.rule.lanes
	return int(lanes[posmod(int(game.turn) - 1, lanes.size())])

## Rounds between two Closing Time locks: the phase's value for this floor, else the rule's. 0 for other rules.
static func every(game: Node) -> int:
	var id := boss_id(game)
	if id == "": return 0
	var row: Dictionary = rows()[id]
	var step: Dictionary = row.phases[phase(game) - 1]
	var by_floor: Dictionary = step.get("every_by_floor", {})
	var key := str(game.run_director.floor_number)
	if by_floor.has(key): return int(by_floor[key])
	return int(row.rule.get("every", 0))

## True when Closing Time locks a card in this round.
static func lock_round(game: Node, round_number: int) -> bool:
	var gap := every(game)
	return gap > 0 and round_number % gap == 0

## Round preparation: Lockdown calls the signature card, then the checkpoint unit gains Barrier.
## For the Janitor: Night Shift calls Midnight Cataclysm, then Closing Time locks a hand card.
static func prepare_round(game: Node) -> void:
	var id := boss_id(game)
	if id == "": return
	var row: Dictionary = rows()[id]
	var rule_id := str(row.rule.get("id", ""))
	var step: Dictionary = row.phases[phase(game) - 1]
	var called := "LOCKDOWN: the Hallway Guardian is called."
	if rule_id == "closing_time": called = "NIGHT SHIFT: Midnight Cataclysm is called."
	# The card moves only while it is still in the evolution deck, so it moves once.
	# The hand limits of enemy_draw_evolutions do not apply here.
	if step.has("to_hand"):
		for i in game.enemy_evolution_deck.size():
			if str(game.enemy_evolution_deck[i].get("id", "")) == str(step.to_hand):
				game.enemy_hand.append(game.enemy_evolution_deck[i])
				game.enemy_evolution_deck.remove_at(i)
				game.log_event(called)
				break
	if rule_id == "closing_time":
		closing_time(game, row)
		return
	# A unit that already has Barrier gets nothing, so the rule never stacks.
	var card = game._get_card_in_slot(game._threat_slots()[checkpoint_lane(game)])
	if card != null and card.is_alive() and int(card.statuses.get("barrier", 0)) <= 0:
		card.add_status("barrier", int(row.rule.barrier))
		card.spawn_popup("CHECKPOINT", UI.GOLD)

## Closing Time: on a lock round the newest hand card that is not sealed is locked, like final_boss.gd stage 3.
static func closing_time(game: Node, row: Dictionary) -> void:
	if not lock_round(game, int(game.turn)): return
	var lock_rounds := int(row.rule.lock_rounds)
	var until := int(game.turn) + lock_rounds
	var cards: Array = game.get_hand_cards()
	# Only this step, in this round, writes exactly this number. So a second run does nothing.
	if cards.any(func(card): return int(card.card_data.get("locked_until", 0)) == until): return
	var targets: Array = cards.filter(func(card): return not game.is_sealed(card.card_data))
	if targets.is_empty(): return
	# "newest" is the last card in the hand.
	var target = targets[targets.size() - 1]
	target.card_data.locked_until = until
	# card_3d shows a Janitor lock with its own icon, not the seal icon.
	target.card_data["lock_source"] = "janitor"
	# A later seal by anything else changes locked_until, so the card shows the seal look again.
	target.card_data["janitor_until"] = until
	target._refresh_face()
	game.log_event("CLOSING TIME: %s is locked for %d rounds." % [str(target.card_data.get("name", "A card")),
		lock_rounds])

## The Janitor's intent line. Numbers come from the row.
static func closing_intent(game: Node, row: Dictionary) -> String:
	var step: Dictionary = row.phases[phase(game) - 1]
	var lock_rounds := int(row.rule.lock_rounds)
	var gap := every(game)
	if gap == 1:
		return "%s: CLOSING TIME every round. Your newest card is locked for %d rounds." % [step.name, lock_rounds]
	# Night Shift on a floor without "every round" names the phase in front.
	var prefix := "%s. " % step.name if phase(game) > 1 else ""
	var turn := int(game.turn)
	if lock_round(game, turn):
		# closing_time writes exactly turn + lock_rounds. No such card means nothing was locked.
		var until := turn + lock_rounds
		var cards: Array = game.get_hand_cards()
		if not cards.any(func(card): return int(card.card_data.get("locked_until", 0)) == until):
			return prefix + "CLOSING TIME: nothing to lock. Next lock in %d rounds." % gap
		return prefix + "CLOSING TIME: one card is locked. Next lock in %d rounds." % gap
	var wait := gap - turn % gap
	if wait == 1:
		return prefix + "CLOSING TIME next round: your newest card is locked for %d rounds." % lock_rounds
	return prefix + "CLOSING TIME in %d rounds: your newest card is locked for %d rounds." % [wait, lock_rounds]

## The intent panel line. Lanes are shown 1 to 4.
static func intent(game: Node) -> String:
	var id := boss_id(game)
	if id == "": return ""
	var row: Dictionary = rows()[id]
	if str(row.rule.get("id", "")) == "closing_time": return closing_intent(game, row)
	var step: Dictionary = row.phases[phase(game) - 1]
	var lane := checkpoint_lane(game) + 1
	if phase(game) == 1:
		var lanes: Array = row.rule.lanes
		var next := int(lanes[posmod(int(game.turn), lanes.size())]) + 1
		return "CHECKPOINT: lane %d. Next: lane %d. The Disaster unit there gains Barrier %d." \
			% [lane, next, int(row.rule.barrier)]
	if on_board(game, str(step.get("stay_on", ""))) < 0:
		return "LOCKDOWN: the Hallway Guardian is called. CHECKPOINT: lane %d." % lane
	return "LOCKDOWN: CHECKPOINT stays on the Hallway Guardian, lane %d." % lane

## True when the boss rule turns off the two random modifier rolls.
static func blocks_random_modifiers(game: Node) -> bool:
	var id := boss_id(game)
	return id != "" and bool(rows()[id].get("replaces_random_modifiers", false))
