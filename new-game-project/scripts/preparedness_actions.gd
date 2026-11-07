extends RefCounted
## Preparedness actions in a Versus match. Same style as disaster_actions.gd.
## A remote Preparedness player (LAN) sends hand and lane indices; every action is checked here first.
## The local drag and the local tactic picks also end here, so the board is changed in one place.
## Each action returns {"ok": bool, "reason": String}. The reason is empty when ok.
## Not here yet (LAN slice): utility cards and the Extraction tactic. They answer "not_supported".

# Tactics a remote player cannot use yet: they need a second pick or no ally.
const NOT_SUPPORTED_TACTICS := ["extract", "supply", "shelter"]
# Flag on: these two are delayed tactics with no ally to pick.
const NO_ALLY_TACTICS := ["supply", "shelter"]
# Flag on: utility effects that run at once, with no pick.
const SIMPLE_UTILITIES := ["draw", "blast", "barrier", "herb", "tablet", "scout"]

var game: Node
# Flag on: Scout (Hazard Forecast). A copy of the Disaster hand taken at the cast, for the Preparedness view only.
var scout_hand: Array = []
var scout_encounter := -1
# Flag on: the open pick of a remote utility card or Emergency Extraction. Empty when the flag is off.
var utility_choice: RefCounted

func _init(owner_game: Node) -> void:
	game = owner_game
	utility_choice = preload("res://scripts/lan_utility_choice.gd").new(owner_game)

func _result(ok: bool, reason: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason}

# True for a whole number from 0 to size - 1. A float or a string is refused.
func _is_index(value, size: int) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value < size

## Checks shared by every action in the play phase. Returns the reason, or "" when it may go ahead.
func _common_problem() -> String:
	if game.phase != game.Phase.PLAYER_PLAY: return "not_prep_turn"
	if not game.board_input.action.is_empty(): return "busy"
	# Flag on: an open utility pick blocks every other play until it is picked or cancelled.
	if utility_choice.active(): return "choice_pending"
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
	# Flag on: a utility is judged by the utility rules. Flag off: it stays not_supported.
	if utilities_on() and hand_cards[hand_index].card_data.get("utility", false):
		return utility_problem(hand_cards[hand_index])
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

## True when LAN utility cards and the delayed tactics are on: the flag, or a test override.
## Only a remote Preparedness seat in Versus counts, so singleplayer and hot-seat never change.
func utilities_on() -> bool:
	if game.seat_prep != "remote": return false
	return flag_on()

## The LAN_PREP_UTILITIES flag in a Versus match, whoever sits remote. The Disaster graveyard list uses this one:
## a remote Disaster client plays against a local Preparedness seat, so utilities_on() is false there.
func flag_on() -> bool:
	if game.encounter_kind != "versus": return false
	if game.lan_prep_utilities_override is bool: return game.lan_prep_utilities_override
	return preload("res://scripts/versus_match.gd").LAN_PREP_UTILITIES

## Scout over LAN: no host modal. Sets the same local flag and keeps a copy of the Disaster hand.
func reveal_scout() -> void:
	game.run_director.intel_revealed = true
	scout_hand = game.enemy_hand.map(func(entry): return entry.duplicate(true))
	scout_encounter = game.encounter_serial

## True while a Scout reveal lasts. It ends with the local intel_revealed flag, or with the encounter.
func scout_active() -> bool:
	if not utilities_on() or scout_encounter != game.encounter_serial: return false
	return game.run_director.intel_revealed

## Why this utility card cannot be cast now, or "". Flag off: every utility is not_supported.
func utility_problem(card: Node) -> String:
	if not utilities_on(): return "not_supported"
	var effect := str(card.card_data.get("effect", ""))
	var has_pick: bool = effect in utility_choice.LANE_UTILITIES or effect in utility_choice.LIST_UTILITIES
	if effect not in SIMPLE_UTILITIES and not has_pick: return "not_supported"
	if game.is_sealed(card.card_data): return "sealed"
	if game.preparedness < int(card.card_data.get("cost", 0)): return "no_energy"
	# Same rule as the local drop: a utility needs an empty lane to be dropped on.
	if not game._response_slots().any(func(slot): return game._get_card_in_slot(slot) == null): return "lane_full"
	# A utility with a pick needs something to pick, as the local cast does.
	if effect not in SIMPLE_UTILITIES and not utility_choice.has_targets(effect): return "no_target"
	return ""

## Cast a utility from the hand. Draw, Blast, Barrier, Herb and Tablet need no pick and run at once.
## card_id is optional: when it is sent, it must match the card at hand_index (a stale view is refused).
func use_utility(hand_index, target = null, card_id = null) -> Dictionary:
	if not utilities_on(): return _result(false, "not_supported")
	var problem := _common_problem()
	if not problem.is_empty(): return _result(false, problem)
	var hand_cards: Array = game.get_hand_cards()
	if not _is_index(hand_index, hand_cards.size()): return _result(false, "bad_hand")
	var card: Node = hand_cards[hand_index]
	if not card.card_data.get("utility", false): return _result(false, "bad_hand")
	if card_id != null and (typeof(card_id) != TYPE_STRING or card_id != str(card.card_data.get("id", ""))):
		return _result(false, "stale_hand")
	problem = utility_problem(card)
	if not problem.is_empty(): return _result(false, problem)
	var effect := str(card.card_data.get("effect", ""))
	if effect in SIMPLE_UTILITIES:
		# A no-pick utility takes no target: -1 or nothing.
		if target != null and not (typeof(target) == TYPE_INT and target == -1): return _result(false, "bad_target")
		game.apply_simple_utility(card, effect)
		return _result(true)
	# A utility with a pick opens a choice on the host. Nothing is paid until the last pick works.
	if target != null and not (typeof(target) == TYPE_INT and target == -1): return _result(false, "bad_target")
	utility_choice.begin_utility(card, effect)
	return _result(true)

## One pick of the open choice (see lan_utility_choice.gd). Flag off: not_supported.
func utility_pick(msg: Dictionary) -> Dictionary:
	if not utilities_on(): return _result(false, "not_supported")
	if game.phase != game.Phase.PLAYER_PLAY: return _result(false, "not_prep_turn")
	return utility_choice.pick(msg)

## Cancel the open choice. Nothing was spent, so nothing is given back.
func utility_cancel(msg: Dictionary) -> Dictionary:
	if not utilities_on(): return _result(false, "not_supported")
	return utility_choice.cancel(msg)

## Arm a tactic on the deployed ally in this lane. Brace, Coordinate, Medicine and the other one-ally tactics.
## Flag on: Supply Line and Emergency Shelter take no ally (lane is left out or -1).
func use_tactic(id, ally_lane) -> Dictionary:
	var problem := _common_problem()
	if not problem.is_empty(): return _result(false, problem)
	if typeof(id) != TYPE_STRING or id not in game.plans.unlocked: return _result(false, "bad_tactic")
	var no_ally: bool = utilities_on() and id in NO_ALLY_TACTICS
	# Flag on: Emergency Extraction opens a pick (ally, then empty lane) and arms at the last pick.
	var pick_first: bool = utilities_on() and id == "extract"
	if id in NOT_SUPPORTED_TACTICS and not no_ally and not pick_first: return _result(false, "not_supported")
	if not game.run_director.tactic_available(id): return _result(false, "tactic_unavailable")
	if pick_first:
		if ally_lane != null and not (typeof(ally_lane) == TYPE_INT and ally_lane == -1):
			return _result(false, "bad_lane")
		utility_choice.begin_tactic(id)
		return _result(true)
	if no_ally:
		if ally_lane != null and not (typeof(ally_lane) == TYPE_INT and ally_lane == -1): return _result(false, "bad_lane")
		if not arm_tactic_on(id, []): return _result(false, "tactic_unavailable")
		return _result(true)
	var slots: Array = game._response_slots()
	if not _is_index(ally_lane, slots.size()): return _result(false, "bad_lane")
	var ally: Node = game._get_card_in_slot(slots[ally_lane])
	if ally == null: return _result(false, "bad_lane")
	if not arm_tactic(id, ally): return _result(false, "tactic_unavailable")
	return _result(true)

## Arms a tactic on one ally. The local picks (run_director) call this too.
func arm_tactic(id: String, ally: Node) -> bool:
	return arm_tactic_on(id, [ally])

## Arms a tactic on these cards (none for Supply Line and Shelter), with an optional destination lane.
func arm_tactic_on(id: String, cards: Array, destination: Node3D = null) -> bool:
	# plans.can_arm asks game.can_player_act, which is false for a remote seat (host clicks are blocked).
	# use_tactic has done the checks, so the seat counts as local just for this one call.
	var seat: String = game.seat_prep
	game.seat_prep = "local"
	var armed: bool = game.plans.arm(id, cards, destination)
	game.seat_prep = seat
	return armed

## End the Preparedness turn. The round (Disaster turn, combat, next round) then runs on the host.
func end_turn() -> Dictionary:
	if game.phase != game.Phase.PLAYER_DRAW and game.phase != game.Phase.PLAYER_PLAY:
		return _result(false, "not_prep_turn")
	if not game.board_input.action.is_empty(): return _result(false, "busy")
	if utility_choice.active(): return _result(false, "choice_pending")
	if game.run_director and game.run_director.modal.visible: return _result(false, "host_busy")
	for card in game.get_hand_cards():
		if card.is_dragging: return _result(false, "busy")
	# Not awaited: the round plays its animations and the turn comes back later.
	game.end_prep_turn()
	return _result(true)
