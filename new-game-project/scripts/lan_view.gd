extends RefCounted
## LAN Part B: the board as the remote Disaster may see it. Built on the host only.
## Starts from battle_snapshot, then drops what the Disaster must not know.
## Kept: lanes, both sides' HP and resources, round and phase, the Disaster hand.
## Counts only: the Preparedness hand, every draw pile, the evolution deck, the graveyards.
## Dropped: RNG states, pending choice, plans, battle log, and every card no kept zone uses.

const BattleSnapshot = preload("res://scripts/battle_snapshot.gd")


# The whole view for the client. Plain data, so it fits an RPC.
static func build(game: Node) -> Dictionary:
	var snapshot: Dictionary = BattleSnapshot.new().capture(game).to_dict()
	var zones: Dictionary = snapshot.zones
	var view := {
		"round": snapshot.round_number,
		"is_disaster_turn": game.phase == game.Phase.ENEMY,
		"first_side": snapshot.first_side,
		"coin": snapshot.coin.duplicate(),
		"sides": snapshot.sides.duplicate(true),
		"lanes": snapshot.lanes.duplicate(true),
		"disaster_hand": zones.disaster.hand.duplicate(),
		"counts": {
			"response_hand": zones.response.hand.size(),
			"response_draw": zones.response.draw.size(),
			"response_graveyard": zones.response.graveyard.size(),
			"disaster_draw": zones.disaster.draw.size(),
			"disaster_evolution": zones.disaster.evolution.size(),
			"disaster_graveyard": zones.disaster.graveyard.size(),
		},
		"actions_left": game.disaster_actions.actions_left(),
		"cards": {},
		"hints": hand_hints(game),
	}
	_keep_cards(view, snapshot.cards)
	return view


# Copy only the cards that sit in a lane or in the Disaster hand.
static func _keep_cards(view: Dictionary, all_cards: Dictionary) -> void:
	var ids: Array = view.disaster_hand.duplicate()
	for side in ["response", "disaster"]:
		for id in view.lanes[side]:
			if id != "":
				ids.append(id)
	for id in ids:
		view.cards[id] = all_cards[id].duplicate(true)


# One hint per Disaster hand card, in hand order. The host still checks every action.
# lanes and sacrifices are threat lane indices. targets are Preparedness hand indices (blind picks).
static func hand_hints(game: Node) -> Array:
	var actions: RefCounted = game.disaster_actions
	var threat_slots: Array = game._threat_slots()
	var hints: Array = []
	for definition in game.enemy_hand:
		var lanes: Array = []
		for slot in actions.legal_lanes(definition):
			lanes.append(threat_slots.find(slot))
		var sacrifices: Array = []
		for card in actions.legal_sacrifices(definition):
			sacrifices.append(_lane_of(game, threat_slots, card))
		var targets: Array = []
		var hand_cards: Array = game.get_hand_cards()
		for card in actions.legal_targets(definition):
			targets.append(hand_cards.find(card))
		hints.append({
			"can_use": actions.can_use(definition),
			"problem": actions.card_problem(definition),
			"needs_target": actions.needs_target(definition),
			"lanes": lanes,
			"sacrifices": sacrifices,
			"targets": targets,
		})
	return hints


static func _lane_of(game: Node, threat_slots: Array, card: Node) -> int:
	for lane in threat_slots.size():
		if game._get_card_in_slot(threat_slots[lane]) == card:
			return lane
	return -1
