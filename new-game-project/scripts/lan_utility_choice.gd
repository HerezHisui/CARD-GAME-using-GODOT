extends RefCounted
## Host-side pending pick for a remote Preparedness utility card or the Emergency Extraction tactic.
## Only used with LAN_PREP_UTILITIES. The host builds the legal handles and the client names one of them.
## Nothing is spent until the last pick works. Old encounters, old choices and wrong stages are refused.
## A handle is a lane (ally, field, destination), never a snapshot id.
## The private lists (deck, graveyard, Disaster hand) use a position in this choice's own list as the handle.
## Their candidates go only to the Preparedness view while the choice is open. The Disaster hand is sent blind,
## unless a Scout reveal is on (then the Tax cards are named).
## Messages (Preparedness client to host), all checked here:
##   {kind:"utility_pick", encounter:i, choice:i, stage:"ally", handle:i}
##   {kind:"utility_cancel", encounter:i, choice:i}

# Utility effects that open a pick on a lane, and the ones that pick from a private list.
const LANE_UTILITIES := ["rally", "cleanse", "seal", "move"]
# tutor: own deck. recover: own graveyard. tax: the Disaster hand, blind (no faces ever leave the host).
const LIST_UTILITIES := ["tutor", "recover", "tax"]
const LIST_STAGES := ["deck", "grave", "hand"]

var game: Node
var kind := ""  # "utility" (a hand card), "tactic" (Emergency Extraction) or "relocation" (a played unit), "" = none
var effect := ""  # the utility effect, or the tactic id
var source: Node  # utility only: the hand card that is not paid for yet
var encounter := -1  # game.encounter_serial when the choice began
var choice := 0  # goes up with every new choice, so an old pick cannot hit a new one
var stage := ""  # "ally", "field" or "destination"
var ally_lane := -1  # two-step picks: the ally chosen in the first step
var handles: Array = []  # the legal handles of this stage
# List stages: the host-side entries behind the handles. A handle is a position in this list, for this choice only.
var entries: Array = []

func _init(owner_game: Node) -> void:
	game = owner_game

func reset() -> void:
	kind = ""
	effect = ""
	source = null
	encounter = -1
	stage = ""
	ally_lane = -1
	handles = []
	entries = []

## The first pick stage of an effect, or "" when it has no pick.
static func first_stage(effect_id: String) -> String:
	match effect_id:
		"rally", "cleanse", "move", "extract": return "ally"
		"seal": return "field"
		"tutor": return "deck"
		"recover": return "grave"
		"tax": return "hand"
	return ""

## The private entries behind a list stage, read from the game now. Handles are positions in this list.
func list_entries(stage_name: String) -> Array:
	match stage_name:
		"deck": return game.deck.filter(func(entry): return not game.is_sealed(entry))
		"grave": return game.recoverable_units()
		"hand": return game.enemy_hand.duplicate()
	return []

# True when this exact entry (not an equal copy) is still in the list.
func _still_listed(entry: Dictionary, fresh: Array) -> bool:
	return fresh.any(func(other): return is_same(other, entry))

## Legal lanes for a stage, read from the board right now.
func handles_for(stage_name: String) -> Array:
	var lanes: Array = []
	var slots: Array = game._response_slots()
	if stage_name == "field":
		var threat_slots: Array = game._threat_slots()
		for card in game.seal_targets(): lanes.append(threat_slots.find(card.current_slot))
		return lanes
	for lane in slots.size():
		var card = game._get_card_in_slot(slots[lane])
		if stage_name == "destination" and card == null: lanes.append(lane)
		elif stage_name == "ally" and is_instance_valid(card) and card.is_alive(): lanes.append(lane)
	return lanes

## True when the first stage of this effect has something to pick.
func has_targets(effect_id: String) -> bool:
	var first := first_stage(effect_id)
	if first.is_empty(): return false
	if first in LIST_STAGES: return not list_entries(first).is_empty()
	return not handles_for(first).is_empty()

## True while a choice is open. A choice from an old encounter, phase or hand is dropped here.
func active() -> bool:
	if kind == "": return false
	var valid: bool = encounter == game.encounter_serial and game.phase == game.Phase.PLAYER_PLAY \
		and game.encounter_kind == "versus" and game.seat_prep == "remote"
	if valid and kind == "utility": valid = is_instance_valid(source) and source in game.get_hand_cards()
	if valid and kind == "tactic": valid = effect in game.plans.unlocked
	if valid and kind == "relocation":
		valid = is_instance_valid(source) and source.is_alive() and source.current_slot != null and not source.in_hand
	if not valid: reset()
	return valid

func begin_utility(card: Node, effect_id: String) -> void:
	reset()
	kind = "utility"
	effect = effect_id
	source = card
	_start(first_stage(effect_id))

## A played unit with "On play: move another ally" (Lane Marshal). The unit is already on the board and paid for.
## The move is optional: cancel keeps the unit where it is.
func begin_relocation(card: Node) -> void:
	reset()
	kind = "relocation"
	effect = "move"
	source = card
	_start("ally")

func begin_tactic(id: String) -> void:
	reset()
	kind = "tactic"
	effect = id
	_start("ally")

func _start(first: String) -> void:
	encounter = game.encounter_serial
	choice += 1
	_set_stage(first)

func _set_stage(stage_name: String) -> void:
	stage = stage_name
	entries = list_entries(stage_name)
	handles = range(entries.size()) if stage_name in LIST_STAGES else handles_for(stage_name)
	# A relocation moves another ally, never the unit that was just played, and the ally must be eligible.
	if kind == "relocation" and stage_name == "ally":
		handles = handles.filter(func(lane: int) -> bool:
			var ally := _ally_in(lane)
			return ally != source and game.plans.eligible(ally))

func _prompt() -> String:
	if stage == "destination": return "Choose an empty lane."
	if kind == "relocation": return "Choose another ally to move, or cancel."
	if stage == "field": return "Choose a Disaster card on the field."
	if stage == "deck": return "Choose a card from your deck."
	if stage == "grave": return "Choose a unit from your graveyard."
	if stage == "hand": return "Choose one card from the Disaster hand. You cannot see it."
	return "Choose a deployed ally."

# Candidates for a list stage. The deck and the graveyard are the owner's own cards. The Disaster hand is blind.
# While a Scout reveal lasts, the hand cards are named, as in the local Tax pick.
func _candidates() -> Array:
	var list: Array = []
	var named: bool = game.preparedness_actions.scout_active()
	for handle in entries.size():
		if stage == "hand" and not named: list.append({"handle": handle})
		else: list.append({"handle": handle, "card": entries[handle].duplicate(true)})
	return list

## What the Preparedness client may know about the open choice. {} when nothing is open.
func view() -> Dictionary:
	if not active(): return {}
	var title: String = str(source.card_data.get("name", effect)) if kind in ["utility", "relocation"] \
		else str(game.plans.definition(effect).get("name", effect))
	var out := {"choice": choice, "encounter": encounter, "kind": kind, "effect": effect, "name": title,
		"source": game.get_hand_cards().find(source) if kind == "utility" else -1,
		"stage": stage, "handles": handles.duplicate(), "ally": ally_lane, "prompt": _prompt()}
	if stage in LIST_STAGES: out["candidates"] = _candidates()
	return out

func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _only_fields(msg: Dictionary, fields: Array) -> bool:
	if msg.size() != fields.size(): return false
	return fields.all(func(field): return msg.has(field))

## Checks the ids every message carries. Returns "" when the message belongs to the open choice.
func _problem(msg: Dictionary, fields: Array) -> String:
	if not active(): return "no_choice"
	if not _only_fields(msg, fields): return "bad_message"
	for field in ["encounter", "choice"]:
		if typeof(msg.get(field)) != TYPE_INT: return "bad_message"
	if msg.encounter != encounter or msg.choice != choice: return "stale_choice"
	return ""

func cancel(msg: Dictionary) -> Dictionary:
	var problem := _problem(msg, ["kind", "encounter", "choice"])
	if not problem.is_empty(): return _refuse(problem)
	reset()
	return {"ok": true, "reason": ""}

func pick(msg: Dictionary) -> Dictionary:
	var problem := _problem(msg, ["kind", "encounter", "choice", "stage", "handle"])
	if not problem.is_empty(): return _refuse(problem)
	if typeof(msg.get("stage")) != TYPE_STRING or typeof(msg.get("handle")) != TYPE_INT: return _refuse("bad_message")
	if msg.stage != stage: return _refuse("stale_choice")
	# The board is read again: the handle must be legal now, not only when the choice began.
	if msg.handle not in handles: return _refuse("bad_handle")
	if stage in LIST_STAGES:
		# The entry behind the handle must still be in the list, or the choice has gone stale.
		if not _still_listed(entries[msg.handle], list_entries(stage)):
			reset()
			return _refuse("stale_choice")
	elif msg.handle not in handles_for(stage): return _refuse("bad_handle")
	if kind == "tactic": return _pick_tactic(msg.handle)
	if kind == "relocation": return _pick_relocation(msg.handle)
	var problem_now: String = game.preparedness_actions.utility_problem(source)
	if not problem_now.is_empty():
		reset()
		return _refuse(problem_now)
	return _pick_utility(msg.handle)

func _ally_in(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])

# Emergency Extraction: the ally, then the empty lane. Arming pays the token.
func _pick_tactic(handle: int) -> Dictionary:
	if stage == "ally":
		ally_lane = handle
		_set_stage("destination")
		return {"ok": true, "reason": ""}
	var ally := _ally_in(ally_lane)
	var slot: Node3D = game._response_slots()[handle]
	var id := effect
	reset()
	if ally == null or not ally.is_alive(): return _refuse("stale_choice")
	if not game.preparedness_actions.arm_tactic_on(id, [ally], slot): return _refuse("tactic_unavailable")
	return {"ok": true, "reason": ""}

# Played unit: the ally, then the empty lane. The unit was paid for when it was played, so nothing else is spent.
func _pick_relocation(handle: int) -> Dictionary:
	if stage == "ally":
		ally_lane = handle
		_set_stage("destination")
		return {"ok": true, "reason": ""}
	var ally := _ally_in(ally_lane)
	var slot: Node3D = game._response_slots()[handle]
	var unit := source
	reset()
	if ally == null or not ally.is_alive() or not game.plans.eligible(ally): return _refuse("stale_choice")
	game.apply_relocation(ally, slot, unit)
	return {"ok": true, "reason": ""}

func _pick_utility(handle: int) -> Dictionary:
	if effect == "move" and stage == "ally":
		ally_lane = handle
		_set_stage("destination")
		return {"ok": true, "reason": ""}
	var card := source
	var id := effect
	var power := int(card.card_data.get("utility_power", 0))
	var lane_ally := _ally_in(ally_lane) if ally_lane >= 0 else null
	var target: Variant = null
	if stage == "field": target = game._get_card_in_slot(game._threat_slots()[handle])
	elif stage == "ally": target = _ally_in(handle)
	elif stage in LIST_STAGES: target = entries[handle]
	# The same check as the local pick: a full hand cannot take a recovered unit.
	if id == "recover" and game.get_hand_cards().size() > game.HAND_SIZE_MAX:
		reset()
		return _refuse("hand_full")
	# Closed first, so a repeated pick cannot pay twice.
	reset()
	if id == "move":
		if lane_ally == null or not lane_ally.is_alive(): return _refuse("stale_choice")
		game.apply_relocation(lane_ally, game._response_slots()[handle], card)
		return {"ok": true, "reason": ""}
	# Same order as the local pick: effect, payment, then the received card.
	var received: Dictionary = {}
	if id == "recover": received = game.recovered_definition(target)
	elif id == "tutor": received = target
	game.apply_utility_pick(id, target, power)
	game.consume_utility(card)
	if id in ["tutor", "recover"]: game.add_card_to_hand(received)
	game._refresh_bars()
	return {"ok": true, "reason": ""}
