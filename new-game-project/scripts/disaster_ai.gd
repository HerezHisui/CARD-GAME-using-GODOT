extends RefCounted
## Disaster AI scoring: where to put a threat, which threat to play, and which evolution pays.
## Pure reads of the board. The battle manager keeps thin wrappers and does every action itself.

const BattleEngine = preload("res://scripts/battle_engine.gd")

static func _pick_smart_threat_slot(game: Node, empty_slots: Array, card_data: Dictionary) -> Node3D:
	var elem: String = card_data.get("element", "")
	if game.encounter_kind == "battle" and randf() < 0.5: return empty_slots.pick_random()
	var best_slot: Node3D = null
	var best_score := -999.0

	for s in empty_slots:
		if game.encounter_kind in ["elite", "boss"]:
			var tactical: float = game.score_threat(card_data, s)
			if tactical > best_score:
				best_score = tactical
				best_slot = s
			continue
		var idx: int = game._threat_slots().find(s)
		var score := 0.0
		var opp = game._get_card_in_slot(game._response_slots()[idx])
		if opp and opp.is_alive():
			var opp_elem: String = opp.card_data.get("element", "")
			var mult: float = BattleEngine.TYPE_CHART.get(elem, {}).get(opp_elem, 1.0)
			if mult > 1.0:
				score += 3.0 # Regular encounters use only a mild matchup preference.
			elif mult == 1.0:
				score += 2.0
			else:
				score += 1.0
		else:
			score += 2.0 # Open lane
		# Slight organic variance
		score += randf() * 3.0
		if score > best_score:
			best_score = score
			best_slot = s

	return best_slot if best_slot else empty_slots.pick_random()

static func choose_base_threat(game: Node, candidates: Array, slots: Array) -> Dictionary:
	if game.encounter_kind == "battle": return candidates.pick_random()
	var best: Dictionary = candidates[0]
	var value := -INF
	for definition in candidates:
		for slot in slots:
			var score: float = game.score_threat(definition, slot)
			if score > value:
				value = score
				best = definition
	return best

static func score_threat(game: Node, definition: Dictionary, slot: Node3D, layout: Dictionary = {}) -> float:
	var lane: int = game._threat_slots().find(slot)
	var opponent = game._get_card_in_slot(game._response_slots()[lane])
	var element: String = definition.get("element", "")
	var attack: int = maxi(0, int(definition.get("attack", 0)) + int(definition.get("strength", 0))
		+ game.buff_value(false, "strength"))
	var health: int = maxi(1, int(definition.get("health", 1)) + game.buff_value(false, "health"))
	if definition.has("evaluated_attack"): attack = int(definition.evaluated_attack)
	if definition.has("evaluated_health"): health = int(definition.evaluated_health)
	var slow: bool = game.definition_has_modifier(definition, "sluggish") or game.buff_value(false, "sluggish") > 0
	var pierce: bool = game.definition_has_modifier(definition, "piercing") or game.buff_value(false, "piercing") > 0
	var score := health * 0.45 + attack * (0.8 if slow else 1.3)
	var condition_target: Variant = opponent
	var condition_source: Variant = definition.get("evaluated_statuses", {"strength":int(definition.get("strength", 0))})
	if game.condition_met(definition.get("condition", {}), condition_source, condition_target):
		attack += int(definition.condition.get("bonus", 0))
	if opponent and game.status_stacks(opponent, "any") >= 3: attack += int(definition.get("status_bonus", 0))
	var strikes: int = 2 if game.condition_met(definition.get("condition", {}), condition_source, condition_target) \
		and int(definition.condition.get("strikes", 1)) > 1 else 1
	var can_strike := true
	var hero_damage: int = attack + (2 if game.definition_has_modifier(definition, "fierce") else 0)
	if opponent and opponent.is_alive():
		var mult: float = BattleEngine.TYPE_CHART.get(element, {}).get(opponent.card_data.element, 1.0)
		var dealt: int = opponent.adjusted_damage(maxi(1, int(attack * mult)), pierce)
		var back_mult := float(BattleEngine.TYPE_CHART.get(opponent.card_data.element, {}).get(element, 1.0))
		var incoming := maxi(1, int(opponent.effective_attack() * back_mult))
		if game.definition_has_modifier(definition, "armored"):
			incoming = maxi(1, incoming - int(definition.get("armor_value", 1)))
		can_strike = not game.player_first or incoming < health
		score += minf(dealt, opponent.card_data.health) * (1.7 if can_strike else 0.2)
		if dealt >= opponent.card_data.health and can_strike: score += 8
		if not can_strike: score -= 12 # A dead blocker cannot counterattack.
		else: score += 3
		if game.enemy_hp <= opponent.effective_attack() + 2: score += 15 # Cover potentially lethal lanes.
		for status in definition.get("on_hit", {}): score += int(definition.on_hit[status]) * 0.5
	else:
		score += attack * 1.6
		if hero_damage * strikes >= game.player_hp: score += 50
	if pierce and can_strike and (opponent == null or not opponent.has_modifier("armored")):
		score += attack * 1.2
		if hero_damage * strikes >= game.player_hp: score += 70
	for neighbor in [lane - 1, lane + 1]:
		if neighbor < 0 or neighbor > 3: continue
		var neighbor_slot: Node3D = game._threat_slots()[neighbor]
		var ally = game._get_card_in_slot(neighbor_slot)
		var adjacent: Dictionary = layout.get(neighbor_slot, {}) if not layout.is_empty() \
			else (ally.card_data if ally else {})
		if not adjacent.is_empty() and adjacent.element == element: score += 3 + game.buff_value(false, "synergy")
	if strikes > 1 and can_strike: score += attack * 2.0
	if int(definition.get("on_play_draw", 0)) > 0: score += 2 * int(definition.on_play_draw)
	if definition.get("effect", "") == "draw": score += 3
	if definition.get("effect", "") in ["heal_all", "rally_all"]: score += 2
	return score

static func live_ai_definition(game: Node, card: Node) -> Dictionary:
	var data: Dictionary = card.card_data.duplicate(true)
	data.evaluated_attack = card.effective_attack()
	data.evaluated_health = int(card.card_data.health)
	data.evaluated_statuses = card.statuses.duplicate()
	data.modifiers = card.modifiers.duplicate()
	return data

static func board_score(game: Node, layout: Dictionary) -> float:
	var value := 0.0
	for slot in game._threat_slots():
		var definition: Dictionary = layout.get(slot, {})
		if not definition.is_empty(): value += game.score_threat(definition, slot, layout)
		else:
			var response = game._get_card_in_slot(game._response_slots()[game._threat_slots().find(slot)])
			if response and response.is_alive() and response.can_attack(game.turn):
				var damage: int = response.effective_attack() + game._synergy_bonus(response)
				value -= damage * (5.0 if game.enemy_hp <= damage else 1.8)
	return value

static func best_evolution_plan(game: Node, active: Array, candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gain := 1.0
	var before: Dictionary = {}
	for card in active: before[card.current_slot] = game.live_ai_definition(card)
	var baseline: float = game.board_score(before)
	var opposition: int = game._response_slots().filter(func(slot): return game._get_card_in_slot(slot) != null).size()
	for definition in candidates:
		var cost := int(definition.cost)
		if cost < 1 or cost > active.size(): continue
		for mask in range(1, 1 << active.size()):
			var sacrifices: Array = []
			for i in active.size():
				if mask & (1 << i): sacrifices.append(active[i])
			if sacrifices.size() != cost: continue
			if sacrifices.any(func(card): return not game.can_sacrifice(card)): continue
			for target in sacrifices:
				var after: Dictionary = before.duplicate(true)
				for sacrificed in sacrifices: after.erase(sacrificed.current_slot)
				after[target.current_slot] = definition
				var gain: float = game.board_score(after) - baseline
				if cost >= 3: gain += 3.0
				for sacrificed in sacrifices:
					if sacrificed.card_data.get("on_sacrifice", "") == "draw" and not game.enemy_deck.is_empty(): gain += 2.0
					if sacrificed.card_data.get("on_sacrifice", "") == "burn": gain += 1.0
				# Board presence buys blockers, future sacrifices and formation bonuses.
				# Charge more for losing a numerical advantage, unless a lethal attack wins now.
				var lost := cost - 1
				gain -= lost * (5.0 if active.size() > opposition else 2.0)
				if active.size() > opposition and after.size() <= opposition and lost > 0: gain -= 6
				if gain > best_gain:
					best_gain = gain
					best = {"card":definition, "slot":target.current_slot, "sacrifices":sacrifices, "gain":gain}
	return best
