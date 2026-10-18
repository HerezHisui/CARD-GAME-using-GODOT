extends Node
const UI = preload("res://scripts/ui_theme.gd")
## Response trades unused energy for a limited, delayed combat plan.
const TACTICS := [
	{"id":"brace", "name":"Brace", "cost":1, "description":"One ally blocks up to 2 damage from its next attack hit this combat."},
	{"id":"coordinate", "name":"Coordinated Response", "cost":1, "description":"Choose one ally. It and the nearest ally on each side gain +1 attack this combat."},
	{"id":"medicine", "name":"Field Medicine", "cost":1, "description":"At combat start, heal one ally 3 and remove its Bleed."},
	{"id":"supply", "name":"Supply Line", "cost":1, "description":"Draw 1 card at combat start to prepare your next turn."},
	{"id":"flank", "name":"Flanking Route", "cost":1, "description":"One ally ignores guardian Taunt for this combat."},
	{"id":"shelter", "name":"Emergency Shelter", "cost":1, "description":"Your health pool gains 3 temporary attack protection this combat."},
	{"id":"precision", "name":"Precision Team", "cost":2, "description":"One ally gains +2 attack for this combat."},
	{"id":"extract", "name":"Emergency Extraction", "cost":1, "description":"Move an ally to a chosen empty lane instead of taking one lethal attack."}
]
var unlocked: Array[String] = ["brace", "coordinate"]
var game: Node
var tokens := 0
var auto_save := true
var saved_round := -1
var committed_round := -1
var armed: Dictionary = {}

func setup(manager: Node) -> void: game = manager

func definition(id: String) -> Dictionary:
	for tactic in TACTICS:
		if tactic.id == id: return tactic
	return {}

func reset_run() -> void:
	reset()
	unlocked.assign(["brace", "coordinate"])

func unlock(id: String) -> bool:
	if definition(id).is_empty() or id in unlocked: return false
	unlocked.append(id)
	game.log_event("Unlocked contingency: " + str(definition(id).name))
	return true

func reset() -> void:
	finish_combat()
	tokens = 0
	saved_round = -1
	committed_round = -1

func bank_unused_energy() -> bool:
	if not auto_save or tokens >= 2 or game.preparedness < 2 or saved_round == game.turn: return false
	game.preparedness -= 2
	tokens += 1
	saved_round = game.turn
	game.log_event("Saved 2 energy for a Plan token (%d/2)." % tokens)
	game._refresh_bars()
	return true

func eligible(card: Variant) -> bool:
	return is_instance_valid(card) and card.is_alive() and not card.in_hand and card.current_slot in game._response_slots()

func can_arm() -> bool:
	return tokens > 0 and game.can_player_act() and committed_round != game.turn and armed.is_empty() and not game.get_hand_cards().any(func(card): return card.is_dragging)

func coordination_targets(center: Node) -> Array:
	if not eligible(center): return []
	var result: Array = [center]
	var slots: Array = game._response_slots()
	var origin: int = slots.find(center.current_slot)
	for direction in [-1, 1]:
		var lane: int = origin + direction
		while lane >= 0 and lane < slots.size():
			var ally = game._get_card_in_slot(slots[lane])
			if eligible(ally):
				result.append(ally)
				break
			lane += direction
	return result

func arm(kind: String, cards: Array, destination: Node3D = null) -> bool:
	var tactic := definition(kind)
	if not can_arm() or kind not in unlocked or tactic.is_empty() or tokens < int(tactic.cost): return false
	if kind == "coordinate":
		if cards.size() != 1 or not eligible(cards[0]): return false
	elif kind in ["brace", "medicine", "flank", "precision", "extract"]:
		if cards.size() != 1 or not eligible(cards[0]): return false
		if kind == "extract" and (destination not in game._response_slots() or game._get_card_in_slot(destination) != null): return false
	elif kind == "supply":
		if game.deck.is_empty() or game.get_hand_cards().size() >= game.HAND_SIZE_MAX: return false
	elif kind != "shelter": return false
	tokens -= int(tactic.cost)
	committed_round = game.turn
	armed = {"kind":kind, "targets":cards.duplicate(), "destination":destination, "triggered":false}
	game.log_event("Armed %s for this combat." % tactic.name)
	return true

func try_extract(card: Node, damage: int) -> bool:
	if armed.get("kind", "") != "extract" or armed.get("triggered", false) or damage < int(card.card_data.health): return false
	if armed.targets[0] != card or not eligible(card): return false
	var slot: Node3D = armed.destination
	if not is_instance_valid(slot) or game._get_card_in_slot(slot) != null: return false
	armed.triggered = true
	card.place_on_slot(slot)
	card.last_evaded_hit = true
	game.log_event("Emergency Extraction saves %s from a lethal attack." % card.card_data.name)
	card.spawn_popup("EXTRACTED", UI.RESPONSE)
	return true

func apply_combat() -> void:
	if armed.is_empty(): return
	var targets: Array = armed.targets
	if armed.kind == "brace" and eligible(targets[0]):
		targets[0].planned_guard = 2
		targets[0]._refresh_face()
		game.log_event("Brace protects %s against its next attack this combat." % targets[0].card_data.name)
	elif armed.kind == "coordinate" and not targets.is_empty() and eligible(targets[0]):
		for card in coordination_targets(targets[0]):
			card.set_plan_attack_bonus(1)
		game.log_event("Coordinated Response grants the chosen ally and its nearest neighbors +1 attack for this combat.")
	elif armed.kind == "medicine" and eligible(targets[0]):
		targets[0].statuses.erase("bleed")
		targets[0].heal(3)
	elif armed.kind == "flank" and eligible(targets[0]):
		targets[0].plan_ignore_taunt = true
		targets[0]._refresh_face()
	elif armed.kind == "precision" and eligible(targets[0]):
		targets[0].set_plan_attack_bonus(2)
	elif armed.kind == "supply": game.draw_cards(1)
	elif armed.kind == "shelter": game.plan_hero_barrier = 3
	elif armed.kind == "extract": pass
	else: game.log_event("Contingency expired: its target or formation changed.")

func finish_combat() -> void:
	for card in game.get_tree().get_nodes_in_group("cards"):
		if card.planned_guard > 0 or card.plan_attack_bonus > 0 or card.plan_ignore_taunt:
			card.planned_guard = 0
			card.set_plan_attack_bonus(0)
			card.plan_ignore_taunt = false
			card._refresh_face()
	game.plan_hero_barrier = 0
	armed.clear()
