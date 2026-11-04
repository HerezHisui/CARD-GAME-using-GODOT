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
	if side == "preparedness":
		return _apply_prep(game, msg)
	var actions: RefCounted = game.disaster_actions
	match msg.kind:
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
		"end":
			return actions.end_turn()
		"play":
			return actions.play_card(msg.get("hand"), msg.get("lane"))
		"tactic":
			return actions.use_tactic(msg.get("id"), msg.get("lane"))
		"utility":
			return actions.use_utility(msg.get("hand"), msg.get("target"))
	return _refuse("bad_message")


static func _apply_base(game: Node, msg: Dictionary) -> Dictionary:
	if not _is_index(msg.get("hand"), game.enemy_hand.size()): return _refuse("bad_hand")
	var slots: Array = game._threat_slots()
	if not _is_index(msg.get("lane"), slots.size()): return _refuse("bad_lane")
	var definition: Dictionary = game.enemy_hand[msg.hand]
	return await game.disaster_actions.play_base(definition, slots[msg.lane])


static func _apply_evolve(game: Node, msg: Dictionary) -> Dictionary:
	if not _is_index(msg.get("hand"), game.enemy_hand.size()): return _refuse("bad_hand")
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
	var definition: Dictionary = game.enemy_hand[msg.hand]
	return await game.disaster_actions.evolve(definition, sacrifices, slots[msg.lane])


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
	return typeof(value) == TYPE_INT and value >= 0 and value < size


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
