extends RefCounted
## LAN Part C: turns a Disaster message from the client into the real disaster_actions call.
## Runs on the host only. The message holds only indices, never nodes:
##   {kind:"base", hand:i, lane:j}
##   {kind:"evolve", hand:i, lane:j, sacrifices:[lane, ...]}
##   {kind:"cast", hand:i, target:k}  (k is a Preparedness hand index, or -1 for no target)
##   {kind:"end"}
## Bad indices are refused here. Every game rule is still checked by disaster_actions.gd.
## LAN Part D2-c: a Preparedness message goes to preparedness_actions.gd, which checks every index:
##   {kind:"play", hand:i, lane:j}
##   {kind:"tactic", id:"brace", lane:j}  (j is the Preparedness lane of the ally)
##   {kind:"utility", hand:i, target:k}  (refused as not_supported for now)
##   {kind:"end"}


# Do one action. Returns {ok, reason}, like disaster_actions. Await it: actions play animations.
# side is the seat of the sender: "disaster" (Part C) or "preparedness".
static func apply(game: Node, msg, side: String = "disaster") -> Dictionary:
	if typeof(msg) != TYPE_DICTIONARY or typeof(msg.get("kind")) != TYPE_STRING:
		return _refuse("bad_message")
	if msg.kind == "evolution_pick" and game.evolution_choice.lan_enabled():
		return _apply_evolution_pick(game, msg, side)
	if game.evolution_choice.lan_enabled() and game.evolution_choice.enabled():
		if game.evolution_choice.pending(): return _refuse("busy")
		if side not in ["disaster", "preparedness"]: return _refuse("bad_message")
	if side == "preparedness":
		return _apply_prep(game, msg)
	var actions: RefCounted = game.disaster_actions
	match msg.kind:
		"move_ally":
			if side != "disaster": return _refuse("bad_message")
			return game.disaster_relocation.pick(msg)
		"end":
			return actions.end_turn()
		"base":
			return await _apply_base(game, msg)
		"evolve":
			return await _apply_evolve(game, msg)
		"cast":
			return await _apply_cast(game, msg)
	return _refuse("bad_message")


static func _apply_prep(game: Node, msg: Dictionary) -> Dictionary:
	var actions: RefCounted = game.preparedness_actions
	match msg.kind:
		"draw":
			return actions.draw_card()
		"end":
			return actions.end_turn()
		"play":
			return actions.play_card(msg.get("hand"), msg.get("lane"))
		"tactic":
			return actions.use_tactic(msg.get("id"), msg.get("lane"))
		"utility":
			return actions.use_utility(msg.get("hand"), msg.get("target"), msg.get("id"))
		# Flag on only: a pick or a cancel of the open utility choice. Flag off they are unknown messages.
		"utility_pick":
			if not actions.utilities_on(): return _refuse("bad_message")
			return actions.utility_pick(msg)
		"utility_cancel":
			if not actions.utilities_on(): return _refuse("bad_message")
			return actions.utility_cancel(msg)
	return _refuse("bad_message")


static func _apply_base(game: Node, msg: Dictionary) -> Dictionary:
	if not _is_index(msg.get("hand"), game.enemy_hand.size()): return _refuse("bad_hand")
	var slots: Array = game._threat_slots()
	if not _is_index(msg.get("lane"), slots.size()): return _refuse("bad_lane")
	var definition: Dictionary = game.enemy_hand[msg.hand]
	return await game.disaster_actions.play_base(definition, slots[msg.lane])


static func _apply_evolve(game: Node, msg: Dictionary) -> Dictionary:
	var held: bool = game.evolution_choice.lan_enabled() and msg.get("source") == "held_evolutions"
	var definition: Dictionary
	var id := ""
	if held:
		if not game.evolution_choice.enabled() or not game.evolution_choice.lan_enabled():
			return _refuse("bad_message")
		if not _only_fields(msg, ["kind", "source", "match_id", "id", "lane", "sacrifices"]):
			return _refuse("bad_message")
		if not _active_evolution_match(game, msg): return _refuse("stale_match")
		if typeof(msg.get("id")) != TYPE_STRING: return _refuse("bad_hand")
		id = msg.id
		definition = game.evolution_choice.definition(id)
		if definition.is_empty(): return _refuse("bad_hand")
	else:
		if game.evolution_choice.lan_enabled():
			if not _only_fields(msg, ["kind", "hand", "lane", "sacrifices"]):
				return _refuse("bad_message")
		if not _is_index(msg.get("hand"), game.enemy_hand.size()): return _refuse("bad_hand")
		definition = game.enemy_hand[msg.hand]
	var slots: Array = game._threat_slots()
	if not _is_index(msg.get("lane"), slots.size()): return _refuse("bad_lane")
	if typeof(msg.get("sacrifices")) != TYPE_ARRAY: return _refuse("bad_sacrifice")
	# Each sacrifice is a threat lane index. Turn it back into the card in that lane.
	var sacrifices: Array = []
	for lane in msg.sacrifices:
		if not _is_index(lane, slots.size()): return _refuse("bad_sacrifice")
		var card = game._get_card_in_slot(slots[lane])
		if card == null: return _refuse("bad_sacrifice")
		sacrifices.append(card)
	return await game.disaster_actions.evolve(definition, sacrifices, slots[msg.lane], id)


static func _apply_evolution_pick(game: Node, msg: Dictionary, side: String) -> Dictionary:
	if side != "disaster": return _refuse("not_disaster_peer")
	if not game.evolution_choice.lan_enabled() or not game.evolution_choice.enabled():
		return _refuse("bad_message")
	if not _only_fields(msg, ["kind", "match_id", "offer_id", "id"]): return _refuse("bad_message")
	if not _active_evolution_match(game, msg): return _refuse("stale_match")
	if typeof(msg.get("offer_id")) != TYPE_INT or typeof(msg.get("id")) != TYPE_STRING:
		return _refuse("bad_message")
	var choice: RefCounted = game.evolution_choice
	if not choice.pick(msg.id, msg.offer_id, game.encounter_serial, msg.match_id):
		return _refuse("stale_choice")
	return {"ok": true, "reason": ""}


static func _active_evolution_match(game: Node, msg: Dictionary) -> bool:
	if game.encounter_kind != "versus" or not game.disaster_is_human: return false
	if game.phase not in [game.Phase.SETUP, game.Phase.ENEMY]: return false
	if typeof(msg.get("match_id")) != TYPE_STRING or msg.match_id != game.evolution_choice.match_id:
		return false
	if game.evolution_choice.serial != game.encounter_serial: return false
	var versus: Node = game.run_director.versus_match
	if not is_instance_valid(versus): return false
	return not versus.prematch_active and not versus.deck_step_active


static func _only_fields(msg: Dictionary, fields: Array) -> bool:
	return preload("res://scripts/lan_validators.gd").only_fields(msg, fields)


static func _apply_cast(game: Node, msg: Dictionary) -> Dictionary:
	if not _is_index(msg.get("hand"), game.enemy_hand.size()): return _refuse("bad_hand")
	# -1 or no target means a spell without a target. disaster_actions refuses it if one is needed.
	var target: Node = null
	var target_index = msg.get("target", -1)
	if typeof(target_index) != TYPE_INT: return _refuse("bad_target")
	if target_index != -1:
		var hand_cards: Array = game.get_hand_cards()
		if not _is_index(target_index, hand_cards.size()): return _refuse("bad_target")
		target = hand_cards[target_index]
	var definition: Dictionary = game.enemy_hand[msg.hand]
	return await game.disaster_actions.cast(definition, target)


# True for a whole number from 0 to size - 1. A float or a string is refused.
static func _is_index(value, size: int) -> bool:
	return preload("res://scripts/lan_validators.gd").is_index(value, size)


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
