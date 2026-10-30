extends Node
## A telegraphed encounter inspired by the reference's three-phase structure.
var game: Node
var stage := 1
var changed_round := -1
var pillars_spawned := false
var pulse_resolved := false
var last_resolved_round := -1
var last_prepared_round := -1

func setup(manager: Node) -> void:
	game = manager
	game.enemy_deck.clear()
	game.enemy_hand.clear()
	game.enemy_evolution_deck.clear()
	spawn("Night Watch", "guard", 1, 1, 4, "brace")
	spawn("Hall Monitor", "guard", 2, 1, 4, "evac")

func spawn(title: String, role: String, lane: int, attack: int, health: int, counter: String) -> Node:
	var slot: Node3D = game._threat_slots()[lane]
	var previous = game._get_card_in_slot(slot)
	if previous:
		game.record_graveyard(previous, "Reclaimed")
		previous.remove_from_group("cards")
		previous.current_slot = null
		previous.queue_free()
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	var element := "typhoon" if counter == "brace" else "earthquake"
	card.setup({"id":role + str(lane), "name":title, "type":"disaster", "element":element, "cost_type":"sacrifice", "cost":0, "attack":attack, "health":health, "boss_role":role})
	card.in_hand = false
	card.current_slot = slot
	card.global_position = slot.global_position + Vector3(0, 0.02, 0)
	card._set_overlay(false)
	card._refresh_face()
	return card

func accept_damage(amount: int) -> int:
	if stage == 2: return 0
	if stage == 1:
		var threshold := ceili(game.enemy_max_hp / 2.0)
		var accepted := mini(amount, maxi(0, game.enemy_hp - threshold))
		if game.enemy_hp - accepted <= threshold:
			stage = 2
			game.log_event("Warden enters the shielded pillar phase; pulse is announced for next round.")
			changed_round = game.turn
		return accepted
	return amount

func pillars() -> Array:
	return game._threat_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null and card.is_alive() and card.card_data.get("boss_role", "") == "pillar")

func has_pillar(id: String) -> bool:
	return pillars().any(func(card): return card.card_data.get("id", "") == id)

static func pillar_description(data: Dictionary) -> String:
	if data.get("boss_role", "") != "pillar": return ""
	var timing := "Once at round preparation, starting the round after spawning. Stops when this pillar leaves play. "
	match str(data.get("id", "")):
		"pillar0":
			return timing + "Add 1 additional Static Echo to your hand. If full, lose 1 HP instead."
		"pillar3":
			return timing + "Heal a living Shield Guardian by 1 HP, up to its maximum. Never revives it."
	return ""

func guardian() -> Node:
	for slot in game._threat_slots():
		var card = game._get_card_in_slot(slot)
		if card and card.is_alive() and card.card_data.get("boss_role", "") == "taunt": return card
	return null

func redirect_target(attacker: Node, target: Node) -> Node:
	if stage != 2 or target == null or target.card_data.get("boss_role", "") != "pillar" or (attacker.plan_ignore_taunt or attacker.card_data.get("ignore_taunt", false)): return target
	var guard := guardian()
	return guard if guard else target

func on_card_destroyed(card: Node) -> void:
	if stage != 2 or card.card_data.get("boss_role", "") != "pillar": return
	# One predictable recoil discard, rather than deleting the entire player's hand.
	var hand: Array = game.get_hand_cards().filter(func(unit): return not unit.card_data.get("curse", false))
	if not hand.is_empty():
		var discard = hand[hand.size() - 1]
		game.record_graveyard(discard, "Pillar recoil")
		game.hand.erase(discard)
		discard.in_hand = false
		discard.remove_from_group("cards")
		discard.queue_free()
		game.arrange_hand_centered()
	if pillars_spawned and pillars().all(func(pillar): return pillar == card):
		stage = 3
		changed_round = game.turn

func prepare_round() -> void:
	if last_prepared_round == game.turn: return
	last_prepared_round = game.turn
	if stage == 2 and pillars_spawned:
		add_static_echo()
		if has_pillar("pillar0"): add_static_echo()
		var guard := guardian()
		if has_pillar("pillar3") and guard != null and guard.card_data.health < guard.max_health:
			guard.heal(1)
	if stage == 3:
		var targets: Array = game.get_hand_cards().filter(func(card): return not game.is_sealed(card.card_data))
		if not targets.is_empty():
			var target = targets[targets.size() - 1]
			target.card_data.locked_until = game.turn + 2
			target._refresh_face()

func add_static_echo() -> void:
	var echo := {"id":"static_echo", "name":"Static Echo", "type":"response", "element":"douse",
		"cost":0, "utility":true, "effect":"draw", "draw_count":1, "curse":true}
	if game.get_hand_cards().size() < game.HAND_SIZE_MAX: game.add_card_to_hand(echo)
	else: game._damage_side(true, 1, true)

func settle_curses() -> void:
	for card in game.get_hand_cards():
		if card.card_data.get("curse", false):
			game._damage_side(true, 1, true)
			game.record_graveyard(card, "Unresolved curse")
			game.hand.erase(card)
			card.in_hand = false
			card.remove_from_group("cards")
			card.queue_free()
	game.arrange_hand_centered()

func intent() -> String:
	if stage == 2:
		if not pulse_resolved: return "PHASE 2: next round, Shield Pulse (1 to all units) + two 5-HP pillars. Boss shielded."
		return "PHASE 2: break both pillars. Guardian draws attacks; AoE and Ignore Taunt bypass it. Static Echo costs 1 HP."
	if stage == 3: return "PHASE 3: seal one hand card for 2 rounds; all units +1 Bleed, lanes 1 and 3 take 2 damage."
	if game.turn % 2 == 0: return "PHASE 1: summon Shackle; Punishment hits lane 2 for 3 (4 with Shackle), healing reduced for 2 rounds."
	return "PHASE 1: Blade Rush hits lanes 1 and 3 for 1 + Bleed; Punishment hits lane 2 for 3 (4 if Shackle survives), healing reduced for 2 rounds."

func hit_lane(index: int, damage: int, bleed: int = 0, reduced_healing: bool = false) -> void:
	var card = game._get_card_in_slot(game._response_slots()[index])
	if card:
		card.take_damage(damage)
		if card.is_alive() and not card.last_evaded_hit:
			if bleed > 0: card.add_status("bleed", bleed)
			if reduced_healing: card.add_status("healing_reduced", 2)
	else: game._damage_side(true, mini(damage, 2))

func resolve_intent() -> void:
	if last_resolved_round == game.turn: return
	last_resolved_round = game.turn
	if is_instance_valid(game.opponent_hand): game.opponent_hand.character.warden_pattern()
	game.log_event("Warden pattern: " + intent())
	settle_curses()
	if game._check_game_over(): return
	if stage == 2:
		if not pulse_resolved and game.turn > changed_round:
			for slot in game._response_slots():
				var card = game._get_card_in_slot(slot)
				if card: card.take_damage(1)
			spawn("West Circuit Pillar", "pillar", 0, 0, 5, "brace")
			spawn("East Circuit Pillar", "pillar", 3, 0, 5, "evac")
			spawn("Shield Guardian", "taunt", 1, 0, 4, "brace")
			pillars_spawned = true
			pulse_resolved = true
			# Support begins next round, even if preparation is requested again after the pulse.
			last_prepared_round = game.turn
		return
	if stage == 3:
		if game.turn == changed_round: return # Give a full response turn before the new pattern.
		for slot in game._response_slots():
			var card = game._get_card_in_slot(slot)
			if card: card.add_status("bleed", 1)
		hit_lane(0, 2)
		hit_lane(2, 2)
	else:
		if game.turn % 2 == 0:
			spawn("Emergency Shackle", "shackle", 3, 0, 3, "evac")
		else:
			hit_lane(0, 1, 1)
			hit_lane(2, 1, 1)
		var shackled: bool = game._threat_slots().any(func(slot):
			var card = game._get_card_in_slot(slot)
			return card != null and card.card_data.get("boss_role", "") == "shackle"
		)
		hit_lane(1, 4 if shackled else 3, 0, true)
	game._check_game_over()
