extends RefCounted
## LAN Part B: the board as the remote Disaster may see it. Built on the host only.
## Starts from battle_snapshot, then drops what the Disaster must not know.
## Kept: lanes, both sides' HP and resources, round and phase, the Disaster hand.
## Counts only: the Preparedness hand, every draw pile, the evolution deck, the graveyards.
## Dropped: RNG states, pending choice, plans, battle log, and every card no kept zone uses.
## LAN Part D2-b: build(game, "preparedness") is the mirror for a remote Preparedness player.
## Kept there: lanes, both HPs, energy, Plan tokens, tactics, the Preparedness hand.
## Counts only: the Disaster hand, every draw pile, the evolution deck, the graveyards.

const BattleSnapshot = preload("res://scripts/battle_snapshot.gd")


# The whole view for the client. Plain data, so it fits an RPC.
# side is "disaster" (the Part B view, unchanged) or "preparedness".
static func build(game: Node, side: String = "disaster") -> Dictionary:
	if side == "preparedness":
		return build_prep(game)
	var snapshot: Dictionary = BattleSnapshot.new().capture(game).to_dict()
	var zones: Dictionary = snapshot.zones
	var view := {
		"round": snapshot.round_number,
		"phase": phase_name(game),
		"turn_side": turn_side(game),
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
			"disaster_graveyard": game.disaster_graveyard.size(),
		},
		"actions_left": game.disaster_actions.actions_left(),
		"cards": {},
		"hints": hand_hints(game),
	}
	var relocation: Dictionary = game.disaster_relocation.view()
	if not relocation.is_empty(): view["relocation"] = relocation
	_keep_cards(view, snapshot.cards, view.disaster_hand)
	if game.evolution_choice.lan_enabled(): _disaster_evolutions(game, view)
	view["lane_notes"] = lane_notes(game)
	# Flag on: the Disaster's own graveyard as a list. The Preparedness view keeps the count only.
	if game.preparedness_actions.flag_on(): view["disaster_graveyard_list"] = _graveyard_list(game)
	return view


# The view for a remote Preparedness player. Never holds a Disaster hand or deck card.
static func build_prep(game: Node) -> Dictionary:
	var snapshot: Dictionary = BattleSnapshot.new().capture(game).to_dict()
	var zones: Dictionary = snapshot.zones
	var view := {
		"side": "preparedness",
		"round": snapshot.round_number,
		"phase": phase_name(game),
		"turn_side": turn_side(game),
		"is_prep_turn": game.phase == game.Phase.PLAYER_PLAY,
		"first_side": snapshot.first_side,
		"coin": snapshot.coin.duplicate(),
		"sides": snapshot.sides.duplicate(true),
		"lanes": snapshot.lanes.duplicate(true),
		"prep_hand": zones.response.hand.duplicate(),
		"counts": {
			"disaster_hand": zones.disaster.hand.size(),
			"disaster_draw": zones.disaster.draw.size(),
			"disaster_evolution": zones.disaster.evolution.size(),
			"disaster_graveyard": game.disaster_graveyard.size(),
			"response_draw": zones.response.draw.size(),
			"response_graveyard": zones.response.graveyard.size(),
		},
		"energy": game.preparedness,
		"energy_cap": game.energy_cap,
		"plan_tokens": game.plans.tokens,
		"armed": str(game.plans.armed.get("kind", "")),
		"tactics": tactic_hints(game),
		"cards": {},
		"hints": prep_hand_hints(game),
	}
	_keep_cards(view, snapshot.cards, view.prep_hand)
	view["lane_notes"] = lane_notes(game)
	if game.evolution_choice.lan_enabled(): _evolution_counts(game, view)
	# Flag on: the open utility pick. It goes to the Preparedness client only, never to the Disaster view.
	if game.preparedness_actions.utilities_on():
		view["pending_choice"] = game.preparedness_actions.utility_choice.view()
		# Scout: the Disaster hand as it was at the cast, only while the reveal lasts. Never in the Disaster view.
		if game.preparedness_actions.scout_active():
			view["disaster_hand_revealed"] = game.preparedness_actions.scout_hand.duplicate(true)
	return view


# --- P2 lists: sent only when a seat asks (lan_session.ask_list), never inside a view ---

# What one seat may see of a list. kind is "log", "deck" or "grave". Only the asking seat's own cards.
static func seat_list(game: Node, side: String, kind: String) -> Array:
	if side not in ["disaster", "preparedness"]: return []
	if kind == "log": return seat_log(game, side)
	if kind == "deck": return _deck_list(game, side)
	if kind == "grave":
		var cards: Array = game.disaster_graveyard if side == "disaster" else game.player_graveyard
		var list: Array = []
		for entry in cards:
			list.append(entry.duplicate(true))
		return list
	return []


# The battle log for one seat. A line that names the other seat's private card is swapped for its public words.
# Lines with no tag (restored from a save or a snapshot) are left out, so nothing unchecked goes out.
static func seat_log(game: Node, side: String) -> Array:
	var lines: Array = []
	var tags: Array = game.log_private
	var offset: int = game.battle_log.size() - tags.size()
	for index in game.battle_log.size():
		if index < offset: continue
		var tag: Dictionary = tags[index - offset]
		if tag.is_empty() or str(tag.side) == side:
			lines.append(game.battle_log[index])
		else:
			lines.append(str(tag.public))
	return lines


# The seat's own deck list, the one the host's D key shows for that seat (versus_hud.deck_cards).
static func _deck_list(game: Node, side: String) -> Array:
	var list: Array = []
	for entry in game.versus_master.get(side, []):
		list.append((entry as Dictionary).duplicate(true))
	return list


# The inspect lines that need host state, for every lane card. Lane cards are public, so both seats get this.
# {"response": [note, ...], "disaster": [note, ...]}; a note is {} or holds condition, movement, blood_pact.
static func lane_notes(game: Node) -> Dictionary:
	var notes := {"response": [], "disaster": []}
	var mine := {"response": game._response_slots(), "disaster": game._threat_slots()}
	for lane_side in ["response", "disaster"]:
		var theirs: Array = mine.disaster if lane_side == "response" else mine.response
		for lane in mine[lane_side].size():
			var card: Node = game._get_card_in_slot(mine[lane_side][lane])
			var note := {}
			if is_instance_valid(card):
				# The same checks as run_director's THIS COMBAT lines.
				var data: Dictionary = card.card_data
				if game.balance_enabled():
					var movement := int(card.get_meta("dash_attack", 0))
					if movement > 0: note["movement"] = movement
					if data.has("condition"):
						var target: Node = game._get_card_in_slot(theirs[lane])
						note["condition"] = game.condition_met(data.condition, card, target)
				if game.buff_value(data.get("type", "response") == "response", "kill_or_die") > 0:
					note["blood_pact"] = true
			notes[lane_side].append(note)
	return notes


# The Disaster's own graveyard cards: every one was played face up. Plain copies, oldest first.
static func _graveyard_list(game: Node) -> Array:
	var list: Array = []
	for entry in game.disaster_graveyard:
		list.append(entry.duplicate(true))
	return list


# Preparedness receives only these public additions. Private zones never enter its wire dictionary.
static func _evolution_counts(game: Node, view: Dictionary) -> void:
	view["evolution_waiting"] = game.evolution_choice.pending()
	view.counts["disaster_held_evolutions"] = game.evolution_choice.held.size()


# Build the owner's private payload on the host, separately from the Preparedness whitelist.
static func _disaster_evolutions(game: Node, view: Dictionary) -> void:
	var choice: RefCounted = game.evolution_choice
	_evolution_counts(game, view)
	view["match_id"] = choice.match_id
	view["evolution_offer"] = {}
	view["held_evolutions"] = []
	if choice.pending():
		var candidates: Array = []
		for entry in choice.offer:
			candidates.append({"id": entry.id, "card": entry.definition.duplicate(true)})
		view.evolution_offer = {"match_id": choice.match_id, "offer_id": choice.offer_id, "candidates": candidates}
	for entry in choice.held:
		view.held_evolutions.append({"id": entry.id, "card": entry.definition.duplicate(true),
			"hints": _held_hints(game, entry.definition)})


static func _held_hints(game: Node, definition: Dictionary) -> Dictionary:
	var actions: RefCounted = game.disaster_actions
	var slots: Array = game._threat_slots()
	var sacrifices: Array = []
	for card in actions.legal_sacrifices(definition):
		sacrifices.append(_lane_of(game, slots, card))
	var can_use: bool = actions.can_use(definition)
	return {"can_use": can_use, "problem": actions.card_problem(definition), "needs_target": false,
		"sacrifices": sacrifices, "lanes": sacrifices.duplicate() if can_use else [], "targets": []}


# Copy only the cards that sit in a lane or in the hand this view keeps.
static func _keep_cards(view: Dictionary, all_cards: Dictionary, hand: Array) -> void:
	var ids: Array = hand.duplicate()
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


# One hint per Preparedness hand card, in hand order. lanes are free Preparedness lane indices.
static func prep_hand_hints(game: Node) -> Array:
	var actions: RefCounted = game.preparedness_actions
	var hints: Array = []
	for index in game.get_hand_cards().size():
		var lanes: Array = actions.legal_lanes(index)
		var hint := {
			"can_play": not lanes.is_empty(),
			"problem": actions.hand_problem(index),
			"lanes": lanes,
		}
		# Flag on: a utility is cast, not placed. It has no lanes; the effect tells the client what to send.
		var card: Node = game.get_hand_cards()[index]
		if actions.utilities_on() and card.card_data.get("utility", false):
			hint["can_play"] = hint.problem == ""
			hint["utility"] = true
			hint["effect"] = str(card.card_data.get("effect", ""))
			# The stage the host will ask for first: "" means the card runs at once.
			hint["pick"] = actions.utility_choice.first_stage(hint.effect)
		hints.append(hint)
	return hints


# One hint per unlocked tactic. lanes are the Preparedness lanes with an ally to pick.
static func tactic_hints(game: Node) -> Array:
	var actions: RefCounted = game.preparedness_actions
	var ally_lanes: Array = []
	var slots: Array = game._response_slots()
	for lane in slots.size():
		if game._get_card_in_slot(slots[lane]) != null:
			ally_lanes.append(lane)
	var hints: Array = []
	for id in game.plans.unlocked:
		var tactic: Dictionary = game.plans.definition(id)
		# Flag on: Supply Line and Shelter are allowed, and they take no ally.
		var no_ally: bool = actions.utilities_on() and id in actions.NO_ALLY_TACTICS
		# Flag on: Emergency Extraction opens a pick (ally, then empty lane), so it has no lanes here.
		var pick_first: bool = actions.utilities_on() and id == "extract"
		var available: bool = (id not in actions.NOT_SUPPORTED_TACTICS or no_ally or pick_first) \
			and game.run_director.tactic_available(id) and not actions.utility_choice.active()
		var hint := {
			"id": id,
			"name": str(tactic.get("name", id)),
			"cost": int(tactic.get("cost", 0)),
			"available": available,
			"lanes": [] if no_ally or pick_first or not available else ally_lanes.duplicate(),
		}
		if no_ally: hint["no_ally"] = true
		if pick_first: hint["pick"] = true
		hints.append(hint)
	return hints

static func phase_name(game: Node) -> String:
	if game.phase == game.Phase.PLAYER_DRAW: return "draw"
	if game.phase in [game.Phase.PLAYER_PLAY, game.Phase.ENEMY]: return "play"
	return "end"


static func turn_side(game: Node) -> String:
	if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: return "preparedness"
	if game.phase == game.Phase.ENEMY: return "disaster"
	return ""
