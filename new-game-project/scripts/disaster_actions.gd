extends RefCounted
## Disaster actions in a Versus match. The AI and a human UI call the same functions.
## Every action is checked here first, then done by the helpers in game_3d_manager.gd.
## Each action returns {"ok": bool, "reason": String}. The reason is empty when ok.

signal turn_ended

var game: Node
var actions_used := 0
var action_limit := 0
var busy := false

func _init(owner_game: Node) -> void:
	game = owner_game

func _result(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}

## Call once at the start of each Disaster turn, after the draw.
func begin_turn() -> void:
	actions_used = 0
	action_limit = game.enemy_action_limit()
	busy = false

func actions_left() -> int:
	return maxi(0, action_limit - actions_used)

## Checks shared by every action. Returns the reason, or "" when the action may go ahead.
func _common_problem(definition: Dictionary) -> String:
	if game.phase != game.Phase.ENEMY: return "not_disaster_turn"
	if busy: return "busy"
	if definition not in game.enemy_hand: return "not_in_hand"
	if game.is_sealed(definition): return "sealed"
	if actions_used >= action_limit: return "action_limit"
	if game.tension <= 0: return "no_tension"
	return ""

## Play a base threat (cost 0) into an empty threat lane.
func play_base(definition: Dictionary, slot: Node3D) -> Dictionary:
	var problem := _common_problem(definition)
	if problem.is_empty():
		if definition.get("utility", false) or int(definition.get("cost", 0)) != 0: problem = "not_base"
		elif int(definition.get("tension_cost", 1)) > game.tension: problem = "no_tension"
		elif slot not in game._threat_slots(): problem = "bad_slot"
		elif game._get_card_in_slot(slot) != null: problem = "lane_full"
	if not problem.is_empty(): return _result(false, problem)
	game.enemy_hand.erase(definition)
	busy = true
	var done: bool = await game.disaster_play_base(definition, slot)
	return _finish(done)

## Sacrifice threats and put an evolution in one of their lanes.
func evolve(definition: Dictionary, sacrifices: Array, slot: Node3D) -> Dictionary:
	var problem := _common_problem(definition)
	if problem.is_empty():
		var cost := int(definition.get("cost", 0))
		if definition.get("utility", false) or cost < 1: problem = "not_evolution"
		elif sacrifices.size() != cost: problem = "bad_sacrifice"
		else: problem = _sacrifice_problem(sacrifices, slot)
	if not problem.is_empty(): return _result(false, problem)
	game.enemy_hand.erase(definition)
	busy = true
	var done: bool = await game.disaster_evolve(definition, sacrifices, slot)
	return _finish(done)

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
	var problem := _common_problem(definition)
	if problem.is_empty():
		var effect: String = definition.get("effect", "")
		if not definition.get("utility", false): problem = "not_spell"
		elif int(definition.get("tension_cost", 1)) > game.tension: problem = "no_tension"
		elif effect in ["seal", "tax"]: problem = _target_problem(effect, target)
	if not problem.is_empty(): return _result(false, problem)
	game.enemy_hand.erase(definition)
	busy = true
	var done: bool = await game.disaster_cast(definition, target)
	return _finish(done)

func _target_problem(effect: String, target: Node) -> String:
	if target == null or not is_instance_valid(target): return "bad_target"
	if target not in game.get_hand_cards(): return "bad_target"
	if effect == "seal" and game.is_sealed(target.card_data): return "bad_target"
	return ""

## Stop the Disaster turn. The turn code waits for turn_ended when a human plays.
func end_turn() -> Dictionary:
	if game.phase != game.Phase.ENEMY: return _result(false, "not_disaster_turn")
	if busy: return _result(false, "busy")
	turn_ended.emit()
	return _result(true)

func _finish(done: bool) -> Dictionary:
	busy = false
	if not done: return _result(false, "battle_over")
	actions_used += 1
	return _result(true)
