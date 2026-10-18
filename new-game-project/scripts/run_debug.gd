extends RefCounted

static func debug_available(game: Node, battle_active: bool) -> bool:
	return battle_active \
		and not (is_instance_valid(game.dragged_hand_card) and game.dragged_hand_card.is_dragging) \
		and game.board_input.action.is_empty() \
		and game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]

static func _debug_selected_card(targets: Array, selected: int) -> Node:
	if selected < 0 or selected >= targets.size(): return null
	if not is_instance_valid(targets[selected]): return null
	var card: Node = targets[selected]
	if not card.is_alive() or card.preview_only: return null
	return card if card.in_hand or is_instance_valid(card.current_slot) else null

# The caller checkpoints only after an accepted edit and its face refresh.
static func _debug_set_card_stat(value: float, card: Node, key: String) -> bool:
	if card == null or (key != "cost" and card.card_data.get("utility", false)): return false
	card.card_data[key] = maxi(1 if key == "health" else 0, int(value))
	if key == "health": card.max_health = maxi(card.max_health, int(card.card_data.health))
	card._refresh_face()
	return true
