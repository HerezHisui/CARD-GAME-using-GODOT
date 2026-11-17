extends RefCounted
## Boss rules read from data/bosses.json. Static functions only: no instance and no state.
## The lane comes from the round, the phase from HP, and "moved once" from where the card is.
## So nothing has to be saved and Continue needs no change.

const UI = preload("res://scripts/ui_theme.gd")
const PATH := "res://data/bosses.json"
## Off until it is play-tested. Tests turn it on with game.boss_rule_override.
const GUARDIAN_ENABLED := false

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

## A String override picks one boss id. Otherwise the boss's own flag decides.
static func on(id: String, override: Variant) -> bool:
	if override is String: return id == override
	if id == "guardian": return GUARDIAN_ENABLED
	return false

## The boss rule for this fight, or "" when none is on. Elite rooms only.
static func boss_id(game: Node) -> String:
	if game.encounter_kind != "elite" or not on("guardian", game.boss_rule_override): return ""
	return "guardian" if rows().has("guardian") else ""

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
	var step: Dictionary = row.phases[phase(game) - 1]
	# Lockdown: the checkpoint stays on the signature card while it lives.
	if step.has("stay_on"):
		var lane := on_board(game, str(step.stay_on))
		if lane >= 0: return lane
	var lanes: Array = row.rule.lanes
	return int(lanes[posmod(int(game.turn) - 1, lanes.size())])

## Round preparation: Lockdown calls the signature card, then the checkpoint unit gains Barrier.
static func prepare_round(game: Node) -> void:
	var id := boss_id(game)
	if id == "": return
	var row: Dictionary = rows()[id]
	var step: Dictionary = row.phases[phase(game) - 1]
	# The card moves only while it is still in the evolution deck, so it moves once.
	# The hand limits of enemy_draw_evolutions do not apply here.
	if step.has("to_hand"):
		for i in game.enemy_evolution_deck.size():
			if str(game.enemy_evolution_deck[i].get("id", "")) == str(step.to_hand):
				game.enemy_hand.append(game.enemy_evolution_deck[i])
				game.enemy_evolution_deck.remove_at(i)
				game.log_event("LOCKDOWN: the Hallway Guardian is called.")
				break
	# A unit that already has Barrier gets nothing, so the rule never stacks.
	var card = game._get_card_in_slot(game._threat_slots()[checkpoint_lane(game)])
	if card != null and card.is_alive() and int(card.statuses.get("barrier", 0)) <= 0:
		card.add_status("barrier", int(row.rule.barrier))
		card.spawn_popup("CHECKPOINT", UI.GOLD)

## The intent panel line. Lanes are shown 1 to 4.
static func intent(game: Node) -> String:
	var id := boss_id(game)
	if id == "": return ""
	var row: Dictionary = rows()[id]
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
