extends RefCounted
## Scene references are resolved here; the engine receives only dictionaries and scalars.

static func context(game: Node) -> Dictionary:
	return {
		"response": {"buffs": game.player_buffs, "run_buffs": game.player_run_buffs},
		"disaster": {"buffs": game.enemy_buffs, "run_buffs": game.enemy_run_buffs},
		"player_first": game.player_first,
	}

static func card(game: Node, unit: Node) -> Dictionary:
	var neighbors: Array = []
	if game != null:
		var slots: Array = game._response_slots() if unit.card_data.type == "response" else game._threat_slots()
		var index: int = slots.find(unit.current_slot)
		# Preserve the existing off-board index -1 behavior: lane 0 is its right neighbor.
		for neighbor in [index - 1, index + 1]:
			if neighbor >= 0 and neighbor < slots.size():
				var ally: Node = game._get_card_in_slot(slots[neighbor])
				if ally != null:
					neighbors.append(ally.card_data)
	return {
		"card_data": unit.card_data, "statuses": unit.statuses, "modifiers": unit.modifiers,
		"preview_only": unit.preview_only, "last_attack_turn": unit.last_attack_turn,
		"plan_attack_bonus": unit.plan_attack_bonus, "on_board": unit.current_slot != null,
		"neighbors": neighbors,
	}

static func statuses(subject: Variant) -> Variant:
	if subject == null or subject is Dictionary:
		return subject
	return subject.statuses
