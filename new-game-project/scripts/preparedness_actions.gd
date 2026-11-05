extends RefCounted
## Preparedness actions in a Versus match. Same style as disaster_actions.gd.
## A remote Preparedness player (LAN) sends hand and lane indices; every action is checked here first.
## The local drag and the local tactic picks also end here, so the board is changed in one place.
## Each action returns {"ok": bool, "reason": String}. The reason is empty when ok.
## Not here yet (LAN slice): utility cards and the Extraction tactic. They answer "not_supported".

# Tactics a remote player cannot use yet: they need a second pick or no ally.
const NOT_SUPPORTED_TACTICS := ["extract", "supply", "shelter"]

var game: Node

func _init(owner_game: Node) -> void:
	game = owner_game

func _result(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}

# True for a whole number from 0 to size - 1. A float or a string is refused.
func _is_index(value, size: int) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value < size

## Checks shared by every action in the play phase. Returns the reason, or "" when it may go ahead.
func _common_problem() -> String:
	if game.phase != game.Phase.PLAYER_PLAY: return "not_prep_turn"
	if not game.board_input.action.is_empty(): return "busy"
	return ""

## A remote Preparedness owner presses Draw once during its draw phase.
func draw_card() -> Dictionary:
	if game.encounter_kind != "versus" or game.seat_prep != "remote": return _result(false, "not_remote_prep")
	if game.phase != game.Phase.PLAYER_DRAW: return _result(false, "not_draw_phase")
	if game.evolution_choice.pending() or not game.board_input.action.is_empty(): return _result(false, "busy")
	if game.get_hand_cards().size() >= game.HAND_SIZE_MAX: return _result(false, "hand_full")
	var choices: Array = game.deck.filter(func(card): return not game.is_sealed(card))
	if choices.is_empty():
		game._set_phase(game.Phase.PLAYER_PLAY, "Your turn - play cards, then End Turn")
		game._refresh_bars()
	else: game.complete_draw_choice(choices.pick_random(), true)
	return _result(true)

## Play a unit card from the hand into an empty Preparedness lane.
func play_card(hand_index, lane) -> Dictionary:
	var problem := _common_problem()
	if not problem.is_empty(): return _result(false, problem)
	var hand_cards: Array = game.get_hand_cards()
	if not _is_index(hand_index, hand_cards.size()): return _result(false, "bad_hand")
	var slots: Array = game._response_slots()
	if not _is_index(lane, slots.size()): return _result(false, "bad_lane")
	var card: Node = hand_cards[hand_index]
	problem = _card_problem(card)
	if problem.is_empty() and game._get_card_in_slot(slots[lane]) != null: problem = "lane_full"
	if not problem.is_empty(): return _result(false, problem)
	place_unit(card, slots[lane])
	# LAN: a remote player has no relocation picker yet, so the optional move after play is skipped.
	if game.seat_prep != "local" and not game.board_input.action.is_empty(): game.cancel_move_effect()
	return _result(true)

## The reason this hand card cannot be played now, or "".
func _card_problem(card: Node) -> String:
	if card.card_data.get("utility", false): return "not_supported"
	if game.is_sealed(card.card_data): return "sealed"
	if game.preparedness < int(card.card_data.get("cost", 0)): return "no_energy"
	return ""

## LAN view hint: why play_card would refuse this hand card now, or "" (lane_full when no lane is free).
func hand_problem(hand_index: int) -> String:
	var problem := _common_problem()
	if not problem.is_empty(): return problem
	var hand_cards: Array = game.get_hand_cards()
	if not _is_index(hand_index, hand_cards.size()): return "bad_hand"
	problem = _card_problem(hand_cards[hand_index])
	if problem.is_empty() and legal_lanes(hand_index).is_empty(): problem = "lane_full"
	return problem

## Empty Preparedness lanes where play_card would accept this hand card.
func legal_lanes(hand_index: int) -> Array:
	var lanes: Array = []
	var hand_cards: Array = game.get_hand_cards()
	if not _is_index(hand_index, hand_cards.size()) or not _common_problem().is_empty(): return lanes
	if not _card_problem(hand_cards[hand_index]).is_empty(): return lanes
	var slots: Array = game._response_slots()
	for lane in slots.size():
		if game._get_card_in_slot(slots[lane]) == null: lanes.append(lane)
	return lanes

## Puts a unit on the board and pays for it. The local drag calls this after its own checks.
func place_unit(card: Node, slot: Node3D) -> void:
	card.place_on_slot(slot)
	game.on_card_played(card)

## Utility cards are not sent over LAN yet. The local drag still uses game.try_utility.
func use_utility(_hand_index, _target) -> Dictionary:
	return _result(false, "not_supported")

## Arm a tactic on the deployed ally in this lane. Brace, Coordinate, Medicine and the other one-ally tactics.
func use_tactic(id, ally_lane) -> Dictionary:
	var problem := _common_problem()
	if not problem.is_empty(): return _result(false, problem)
	if typeof(id) != TYPE_STRING or id not in game.plans.unlocked: return _result(false, "bad_tactic")
	if id in NOT_SUPPORTED_TACTICS: return _result(false, "not_supported")
	if not game.run_director.tactic_available(id): return _result(false, "tactic_unavailable")
	var slots: Array = game._response_slots()
	if not _is_index(ally_lane, slots.size()): return _result(false, "bad_lane")
	var ally: Node = game._get_card_in_slot(slots[ally_lane])
	if ally == null: return _result(false, "bad_lane")
	if not arm_tactic(id, ally): return _result(false, "tactic_unavailable")
	return _result(true)

## Arms a tactic on one ally. The local picks (run_director) call this too.
func arm_tactic(id: String, ally: Node) -> bool:
	# plans.can_arm asks game.can_player_act, which is false for a remote seat (host clicks are blocked).
	# use_tactic has done the checks, so the seat counts as local just for this one call.
	var seat: String = game.seat_prep
	game.seat_prep = "local"
	var armed: bool = game.plans.arm(id, [ally])
	game.seat_prep = seat
	return armed

## End the Preparedness turn. The round (Disaster turn, combat, next round) then runs on the host.
func end_turn() -> Dictionary:
	if game.phase != game.Phase.PLAYER_DRAW and game.phase != game.Phase.PLAYER_PLAY:
		return _result(false, "not_prep_turn")
	if not game.board_input.action.is_empty(): return _result(false, "busy")
	if game.run_director and game.run_director.modal.visible: return _result(false, "host_busy")
	for card in game.get_hand_cards():
		if card.is_dragging: return _result(false, "busy")
	# Not awaited: the round plays its animations and the turn comes back later.
	game.end_prep_turn()
	return _result(true)
