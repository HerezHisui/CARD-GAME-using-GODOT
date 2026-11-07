extends RefCounted
## Disaster actions in a Versus match. The AI and a human UI call the same functions.
## Every action is checked here first, then done by the helpers in game_3d_manager.gd.
## Each action returns {"ok": bool, "reason": String}. The reason is empty when ok.

signal turn_ended

var game: Node
var actions_used := 0
var evolution_actions := 0
var action_limit := 0
var busy := false
var turn_closed := false  # set when End Turn is accepted, cleared in begin_turn

func _init(owner_game: Node) -> void:
	game = owner_game

func _result(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}

## Call once at the start of each Disaster turn, after the draw.
func begin_turn() -> void:
	actions_used = 0
	evolution_actions = 0
	action_limit = game.enemy_action_limit()
	busy = false
	turn_closed = false

func actions_left() -> int:
	return maxi(0, action_limit - actions_used + evolution_actions)

## Checks shared by every action. Returns the reason, or "" when the action may go ahead.
func _common_problem(definition: Dictionary, held_id: String = "") -> String:
	if game.evolution_choice.pending() or game.disaster_relocation.pending(): return "busy"
	if game.phase != game.Phase.ENEMY: return "not_disaster_turn"
	# End Turn was accepted: nothing more this turn.
	if turn_closed: return "turn_ended"
	# Draw button on: nothing is played before this turn's draw.
	if game.disaster_draw.waiting: return "draw_first"
	if busy: return "busy"
	if held_id.is_empty():
		if definition not in game.enemy_hand: return "not_in_hand"
	elif not game.evolution_choice.enabled() or game.evolution_choice.id_for(definition) != held_id:
		return "not_in_hand"
	if game.is_sealed(definition): return "sealed"
	if not game.balance_enabled():
		if actions_left() <= 0: return "action_limit"
		if game.tension <= 0: return "no_tension"
	return ""

## Play a base threat (cost 0) into an empty threat lane.
func play_base(definition: Dictionary, slot: Node3D) -> Dictionary:
	var problem := _base_problem(definition, slot)
	if not problem.is_empty(): return _result(false, problem)
	game.enemy_hand.erase(definition)
	busy = true
	var done: bool = await game.disaster_play_base(definition, slot)
	return _finish(done)

## Sacrifice threats and put an evolution in one of their lanes.
func evolve(definition: Dictionary, sacrifices: Array, slot: Node3D, held_id: String = "") -> Dictionary:
	var problem := _common_problem(definition, held_id)
	if problem.is_empty():
		var cost := int(definition.get("cost", 0))
		if definition.get("utility", false) or cost < 1: problem = "not_evolution"
		elif sacrifices.size() != cost: problem = "bad_sacrifice"
		else: problem = _sacrifice_problem(sacrifices, slot)
	if not problem.is_empty(): return _result(false, problem)
	if game.balance_enabled():
		var serial: int = game.encounter_serial
		if not await game.run_director.confirm_balance_evolution(definition, sacrifices):
			return _result(false, "cancelled")
		if serial != game.encounter_serial: return _result(false, "battle_over")
		problem = _common_problem(definition, held_id)
		if problem.is_empty(): problem = _sacrifice_problem(sacrifices, slot)
		if not problem.is_empty(): return _result(false, problem)
	if held_id.is_empty(): game.enemy_hand.erase(definition)
	else: game.evolution_choice.consume(held_id)
	busy = true
	var done: bool = await game.disaster_evolve(definition, sacrifices, slot)
	return _finish(done, game.encounter_kind == "versus")

## Each sacrifice must be a different Disaster card on the board that is allowed to go. The lane is one of theirs.
func _sacrifice_problem(sacrifices: Array, slot: Node3D) -> String:
	var lanes: Array = []
	for card in sacrifices:
		if not game.can_sacrifice(card): return "bad_sacrifice"
		if card.current_slot not in game._threat_slots() or card.current_slot in lanes: return "bad_sacrifice"
		lanes.append(card.current_slot)
	if slot not in lanes: return "bad_slot"
	return ""

## Cast a Disaster spell. Seal and tax need a card in the Response hand as target.
func cast(definition: Dictionary, target: Node) -> Dictionary:
	var problem := _cast_problem(definition, target)
	if not problem.is_empty(): return _result(false, problem)
	game.enemy_hand.erase(definition)
	busy = true
	var done: bool = await game.disaster_cast(definition, target)
	return _finish(done)

func _target_problem(effect: String, target) -> String:
	if target == null or not is_instance_valid(target): return "bad_target"
	if target not in game.get_hand_cards(): return "bad_target"
	if effect == "seal" and game.is_sealed(target.card_data): return "bad_target"
	return ""

## The reason a base card cannot go into this lane, or "" when play_base would accept it.
func _base_problem(definition: Dictionary, slot: Node3D) -> String:
	var problem := _common_problem(definition)
	if not problem.is_empty(): return problem
	if definition.get("utility", false) or int(definition.get("cost", 0)) != 0: return "not_base"
	if int(definition.get("tension_cost", 1)) > game.tension: return "no_tension"
	if slot not in game._threat_slots(): return "bad_slot"
	if game._get_card_in_slot(slot) != null: return "lane_full"
	return ""

## The reason a spell cannot be cast on this target, or "" when cast would accept it.
func _cast_problem(definition: Dictionary, target) -> String:
	var problem := _common_problem(definition)
	if not problem.is_empty(): return problem
	var effect: String = definition.get("effect", "")
	if not definition.get("utility", false): return "not_spell"
	if int(definition.get("tension_cost", 1)) > game.tension: return "no_tension"
	if effect in ["seal", "tax"]: return _target_problem(effect, target)
	return ""

## The reason this card cannot be used at all right now, or "". Used to dim hand rows.
func card_problem(definition: Dictionary) -> String:
	var held_id: String = game.evolution_choice.id_for(definition) if game.evolution_choice.enabled() else ""
	var problem := _common_problem(definition, held_id)
	var evolution: bool = not definition.get("utility", false) and int(definition.get("cost", 0)) > 0
	if not (game.balance_enabled() and evolution):
		if problem.is_empty() and int(definition.get("tension_cost", 1)) > game.tension: problem = "no_tension"
	return problem

## True for a spell that needs a Response hand card as target.
func needs_target(definition: Dictionary) -> bool:
	return definition.get("utility", false) and definition.get("effect", "") in ["seal", "tax"]

## Threat lanes where play_base would accept this card.
func legal_lanes(definition: Dictionary) -> Array:
	return game._threat_slots().filter(func(slot): return _base_problem(definition, slot).is_empty())

## Response hand cards where cast would accept this spell. Empty for a spell with no target.
func legal_targets(definition: Dictionary) -> Array:
	if not needs_target(definition): return []
	return game.get_hand_cards().filter(func(card): return _cast_problem(definition, card).is_empty())

## Threat cards that evolve() would accept as sacrifices (same check as _sacrifice_problem). One per lane.
func legal_sacrifices(definition: Dictionary) -> Array:
	if definition.get("utility", false) or int(definition.get("cost", 0)) < 1: return []
	var cards: Array = []
	for slot in game._threat_slots():
		var card = game._get_card_in_slot(slot)
		if card != null and game.can_sacrifice(card): cards.append(card)
	return cards

## True when the panel may offer this card: a base with a free lane, a spell that can be cast,
## or an evolution with enough cards to sacrifice.
func can_use(definition: Dictionary) -> bool:
	if not card_problem(definition).is_empty(): return false
	if definition.get("utility", false):
		return not legal_targets(definition).is_empty() if needs_target(definition) else true
	var cost := int(definition.get("cost", 0))
	if cost > 0: return legal_sacrifices(definition).size() >= cost
	return not legal_lanes(definition).is_empty()

## Stop the Disaster turn. The turn code waits for turn_ended when a human plays.
func end_turn() -> Dictionary:
	if game.evolution_choice.pending() or game.disaster_relocation.pending(): return _result(false, "busy")
	if game.phase != game.Phase.ENEMY: return _result(false, "not_disaster_turn")
	if turn_closed: return _result(false, "turn_ended")
	if busy: return _result(false, "busy")
	turn_closed = true
	turn_ended.emit()
	return _result(true)

func _finish(done: bool, evolution: bool = false) -> Dictionary:
	busy = false
	if not done: return _result(false, "battle_over")
	actions_used += 1
	# Versus evolutions stay in the total, but spend sacrifices instead of the turn allowance.
	if evolution: evolution_actions += 1
	return _result(true)
