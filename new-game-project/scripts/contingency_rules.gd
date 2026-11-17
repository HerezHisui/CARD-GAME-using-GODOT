extends Node
const UI = preload("res://scripts/ui_theme.gd")
const LeaderKits = preload("res://scripts/leader_kits.gd")
## Response trades unused energy for a limited, delayed combat plan.
const TACTICS := [
	{"id":"brace", "name":"Brace", "cost":1, "description":"One ally blocks up to 2 damage from its next attack hit this combat."},
	{"id":"coordinate", "name":"Coordinated Response", "cost":1, "description":"Choose one ally. It and the adjacent ally on each side gain +1 attack this combat."},
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
# The run's leader kit id. "" means today's plans.
var kit := ""
# Second Wind is spent for this battle.
var kit_used := false
# True while a Eureka deals its damage, so that hit cannot start a second one.
var eureka_running := false
# False while Lane Swap moves units: a swap gives no Tempo.
var _count_moves := true

func setup(manager: Node) -> void: game = manager

func definition(id: String) -> Dictionary:
	if kit_id() != "": return LeaderKits.effect(kit_id(), id)
	return find_tactic(id)

## A tactic by id, without a rules object. The LAN client reads names and descriptions here.
static func find_tactic(id: String) -> Dictionary:
	for tactic in TACTICS:
		if tactic.id == id: return tactic
	return {}

func reset_run() -> void:
	reset()
	unlocked.assign(["brace", "coordinate"])
	kit = ""

## The kit in play, or "" for today's plans. Versus always uses plans.
func kit_id() -> String:
	if game.encounter_kind == "versus": return ""
	return kit

## Give this run a leader kit. An unknown id or "" keeps today's plans.
func set_kit(id: String) -> void:
	var data := LeaderKits.kit(id)
	kit = id if not data.is_empty() else ""
	kit_used = false
	if not data.is_empty(): unlocked.assign(data.start)

## The most charges the counter holds.
func cap() -> int:
	return int(LeaderKits.kit(kit_id()).get("cap", 2))

func unlock(id: String) -> bool:
	if definition(id).is_empty() or id in unlocked: return false
	unlocked.append(id)
	game.log_event("Unlocked contingency: " + str(definition(id).name), "preparedness",
		"Preparedness unlocks a contingency.")
	return true

func reset() -> void:
	finish_combat()
	tokens = 0
	saved_round = -1
	committed_round = -1
	kit_used = false

func bank_unused_energy() -> bool:
	# A kit that never banks (Kai): unused energy is lost.
	if LeaderKits.kit(kit_id()).get("bank", "") == "none": return false
	if not auto_save or tokens >= cap() or game.preparedness < 2 or saved_round == game.turn: return false
	game.preparedness -= 2
	tokens += 1
	saved_round = game.turn
	game.log_event("Saved 2 energy for a Plan token (%d/%d)." % [tokens, cap()], "preparedness",
		"Preparedness saves 2 energy.")
	game._refresh_bars()
	return true

func eligible(card: Variant) -> bool:
	return is_instance_valid(card) and card.is_alive() and not card.in_hand and card.current_slot in game._response_slots()

func can_arm() -> bool:
	return tokens > 0 and game.can_player_act() and committed_round != game.turn and armed.is_empty() and not game.get_hand_cards().any(func(card): return card.is_dragging)

## Statuses that Clean Up clears.
const BAD_STATUSES := ["burn", "poison", "bleed", "healing_reduced"]

## The deployed ally with the lowest health. A tie keeps the leftmost lane.
## with_status: only allies that carry a bad status.
func weakest(with_status := false) -> Node:
	var result = null
	for slot in game._response_slots():
		var card = game._get_card_in_slot(slot)
		if not eligible(card): continue
		if with_status and not BAD_STATUSES.any(func(status): return int(card.statuses.get(status, 0)) > 0): continue
		if result == null or int(card.card_data.health) < int(result.card_data.health): result = card
	return result

## A kit effect can be used now: your play phase, enough charge, one per round, and its target exists.
func kit_available(id: String) -> bool:
	var row := definition(id)
	if kit_id() == "" or row.is_empty() or id not in unlocked: return false
	if game.phase != game.Phase.PLAYER_PLAY or tokens < int(row.cost) or committed_round == game.turn: return false
	if not armed.is_empty(): return false
	if row.does == "recover":
		return not game.recoverable_units().is_empty() and game.get_hand_cards().size() < game.HAND_SIZE_MAX
	if row.does == "draw":
		return not game.deck.is_empty() and game.get_hand_cards().size() < game.HAND_SIZE_MAX
	if row.does == "energy": return game.preparedness < game.energy_cap
	if row.target == "enemy": return not enemy_units().is_empty()
	if row.target == "weakest": return weakest() != null
	if row.target == "weakest_status": return weakest(true) != null
	if row.target == "ally": return not allies().is_empty()
	if row.target == "ally_to_lane":
		var empty_lane: bool = game._response_slots().any(func(slot): return game._get_card_in_slot(slot) == null)
		return empty_lane and not allies().is_empty()
	if row.target == "two_allies": return allies().any(func(card): return coordination_targets(card).size() > 1)
	return true

## Living deployed allies, in lane order.
func allies() -> Array:
	var result: Array = []
	for slot in game._response_slots():
		var card = game._get_card_in_slot(slot)
		if eligible(card): result.append(card)
	return result

## The picked target fits the effect. second: the lane (a move or Duck) or the other unit (Lane Swap).
func _kit_target_ok(row: Dictionary, target: Node, second: Node) -> bool:
	if row.target == "enemy": return target in enemy_units()
	if row.target == "ally": return eligible(target)
	if row.target == "ally_to_lane":
		return eligible(target) and second in game._response_slots() and game._get_card_in_slot(second) == null
	if row.target == "two_allies": return target != second and second in coordination_targets(target)
	return true

## Living Disaster units on the board, in lane order.
func enemy_units() -> Array:
	var result: Array = []
	for slot in game._threat_slots():
		var card = game._get_card_in_slot(slot)
		if is_instance_valid(card) and card.is_alive() and not card.in_hand: result.append(card)
	return result

## Use a kit effect. "now" effects happen at once; "combat" effects arm and fire when combat starts.
## target: the unit picked on the board (an enemy for Sage, an ally for Kai).
## second: the empty lane for a move or Duck, or the neighbour for Lane Swap.
func use_kit_effect(id: String, target: Node = null, second: Node = null) -> bool:
	if not kit_available(id): return false
	var row := definition(id)
	if not _kit_target_ok(row, target, second): return false
	tokens -= int(row.cost)
	committed_round = game.turn
	if row.when == "combat":
		# Same four keys as a Plan: preview_attack reads them every frame.
		armed = {"kind":id, "targets":[], "destination":null, "triggered":false}
		# Rally and Duck keep their unit; Duck also keeps its lane.
		if row.target in ["ally", "ally_to_lane"]: armed.targets = [target]
		if row.target == "ally_to_lane": armed.destination = second
		game.log_event("Armed %s for this combat." % row.name, "preparedness", "Preparedness arms a Plan.")
		preview_attack()
		return true
	if row.does == "heal":
		var unit = weakest()
		game.log_event("%s helps %s." % [row.name, unit.card_data.name], "preparedness", "Preparedness uses Aid.")
		unit.heal(int(row.amount))
	elif row.does == "status":
		# Exact amount: the chemist buff only adds to card hits.
		game.log_event("%s on %s." % [row.name, target.card_data.name], "preparedness", "Preparedness uses a Sample.")
		target.add_status(str(row.status), int(row.amount))
	elif row.does == "cleanse":
		var unit = weakest(true)
		game.log_event("%s helps %s." % [row.name, unit.card_data.name], "preparedness", "Preparedness uses Aid.")
		unit.cleanse()
	elif row.does == "recover":
		# The same steps as the recover utility, on the last destroyed unit, with no picker.
		var entries: Array = game.recoverable_units()
		var entry: Dictionary = entries[entries.size() - 1]
		var received: Dictionary = game.recovered_definition(entry)
		game.log_event("%s brings back %s." % [row.name, entry.get("name", "a unit")], "preparedness",
			"Preparedness uses Aid.")
		game.apply_utility_pick("recover", entry, 0)
		game.add_card_to_hand(received)
	elif row.does == "move":
		# The Tempo comes from the ally_moved hook in apply_relocation.
		game.apply_relocation(target, second, null)
	elif row.does == "swap":
		# A swap is not a move: no Tempo, or it would pay for itself.
		var first_slot: Node3D = target.current_slot
		_count_moves = false
		target.place_on_slot(second.current_slot)
		second.place_on_slot(first_slot)
		_count_moves = true
		game.log_event("%s: %s and %s trade lanes." % [row.name, target.card_data.name, second.card_data.name],
			"preparedness", "Preparedness uses Tempo.")
	elif row.does == "energy":
		game.preparedness = mini(game.energy_cap, game.preparedness + int(row.amount))
		game.log_event("%s gives back energy." % row.name, "preparedness", "Preparedness uses Tempo.")
		game._refresh_bars()
	return true

## Kai's Drill: one of your units changed lane, so gain Tempo up to the cap.
## apply_relocation calls this for both sides; it does nothing without a kit that has "tempo_on_move".
func ally_moved(card: Node) -> void:
	if kit_id() == "" or not _count_moves: return
	var gain := int(LeaderKits.kit(kit_id()).get("tempo_on_move", 0))
	if gain <= 0 or not is_instance_valid(card) or card.current_slot not in game._response_slots(): return
	tokens = mini(cap(), tokens + gain)
	game.log_event("%s changes lane: Tempo %d/%d." % [card.card_data.name, tokens, cap()], "preparedness",
		"Preparedness gains Tempo.")
	game._refresh_bars()

func coordination_targets(center: Node) -> Array:
	if not eligible(center): return []
	var result: Array = [center]
	var slots: Array = game._response_slots()
	var origin: int = slots.find(center.current_slot)
	# Only the lane right next to it on each side counts. An empty lane breaks the link.
	for direction in [-1, 1]:
		var lane: int = origin + direction
		if lane < 0 or lane >= slots.size(): continue
		var ally = game._get_card_in_slot(slots[lane])
		if eligible(ally): result.append(ally)
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
	game.log_event("Armed %s for this combat." % tactic.name, "preparedness", "Preparedness arms a Plan.")
	preview_attack()
	return true

## Show an armed attack Plan on the board before combat, following formation changes.
func preview_attack() -> void:
	if game.phase in [game.Phase.COMBAT, game.Phase.GAME_OVER]: return
	var bonus := {}
	var targets: Array = armed.get("targets", [])
	if not targets.is_empty() and eligible(targets[0]):
		if armed.kind in ["coordinate", "rally"]:
			for card in coordination_targets(targets[0]): bonus[card] = 1
		elif armed.kind == "precision":
			bonus[targets[0]] = 2
	for card in game.get_tree().get_nodes_in_group("cards"):
		var amount: int = bonus.get(card, 0)
		if game.balance_enabled(): amount += int(card.get_meta("dash_attack", 0))
		if card.plan_attack_bonus != amount: card.set_plan_attack_bonus(amount)

func try_extract(card: Node, damage: int) -> bool:
	if kit_id() != "":
		if armed.get("kind", "") == "duck": return _duck(card, damage)
		return _second_wind(card, damage)
	if armed.get("kind", "") != "extract" or armed.get("triggered", false) or damage < int(card.card_data.health): return false
	if armed.targets[0] != card or not eligible(card): return false
	var slot: Node3D = armed.destination
	if not is_instance_valid(slot) or game._get_card_in_slot(slot) != null: return false
	armed.triggered = true
	card.place_on_slot(slot)
	if game.balance_enabled():
		if int(card.card_data.get("relocation_attack", 0)) > 0 and int(card.get_meta("dash_round", -1)) != game.turn:
			card.set_meta("dash_round", game.turn)
			card.set_meta("dash_attack", 1)
			card.set_plan_attack_bonus(card.plan_attack_bonus + 1)
	card.last_evaded_hit = true
	game.log_event("Emergency Extraction saves %s from a lethal attack." % card.card_data.name)
	card.spawn_popup("EXTRACTED", UI.RESPONSE)
	return true

## Robin's Second Wind: once per battle, a lethal attack hit leaves the unit at 1 health.
## It runs inside take_damage, so it never calls take_damage or heal.
func _second_wind(card: Node, damage: int) -> bool:
	if not LeaderKits.kit(kit_id()).get("save_once", false) or kit_used: return false
	if not eligible(card) or damage < int(card.card_data.health): return false
	card.card_data.health = 1
	kit_used = true
	card._refresh_face()
	card.spawn_popup("SECOND WIND", UI.RESPONSE)
	game.log_event("Second Wind keeps %s at 1 HP." % card.card_data.name)
	return true

## Kai's Duck: the armed unit dodges one lethal attack hit into its empty lane, like Emergency Extraction.
## The dodge is a lane change, so it gives Tempo.
func _duck(card: Node, damage: int) -> bool:
	if armed.triggered or damage < int(card.card_data.health): return false
	if armed.targets.is_empty() or armed.targets[0] != card or not eligible(card): return false
	var slot = armed.destination
	if not is_instance_valid(slot) or game._get_card_in_slot(slot) != null: return false
	armed.triggered = true
	card.place_on_slot(slot)
	card.last_evaded_hit = true
	game.log_event("Duck saves %s from a lethal attack." % card.card_data.name)
	card.spawn_popup("DUCKED", UI.RESPONSE)
	ally_moved(card)
	return true

func apply_combat() -> void:
	if armed.is_empty(): return
	if kit_id() != "":
		_apply_kit_combat()
		return
	var targets: Array = armed.targets
	if armed.kind == "brace" and eligible(targets[0]):
		targets[0].planned_guard = 2
		targets[0]._refresh_face()
		game.log_event("Brace protects %s against its next attack this combat." % targets[0].card_data.name)
	elif armed.kind == "coordinate" and not targets.is_empty() and eligible(targets[0]):
		for card in coordination_targets(targets[0]):
			var movement: int = int(card.get_meta("dash_attack", 0)) if game.balance_enabled() else 0
			card.set_plan_attack_bonus(1 + movement)
		game.log_event("Coordinated Response grants the chosen ally and its adjacent allies +1 attack for this combat.")
	elif armed.kind == "medicine" and eligible(targets[0]):
		targets[0].statuses.erase("bleed")
		targets[0].heal(3)
	elif armed.kind == "flank" and eligible(targets[0]):
		targets[0].plan_ignore_taunt = true
		targets[0]._refresh_face()
	elif armed.kind == "precision" and eligible(targets[0]):
		var movement: int = int(targets[0].get_meta("dash_attack", 0)) if game.balance_enabled() else 0
		targets[0].set_plan_attack_bonus(2 + movement)
	elif armed.kind == "supply": game.draw_cards(1)
	elif armed.kind == "shelter": game.plan_hero_barrier = 3
	elif armed.kind == "extract": pass
	else: game.log_event("Contingency expired: its target or formation changed.")

## A kit's "combat" effect fires. Cover picks the weakest unit now, not when it was pressed.
func _apply_kit_combat() -> void:
	var row := definition(str(armed.kind))
	if row.get("does", "") == "guard":
		var unit = weakest()
		if unit == null:
			game.log_event("Aid expired: no unit to cover.")
			return
		unit.planned_guard = int(row.amount)
		unit._refresh_face()
		game.log_event("%s protects %s against its next hit this combat." % [row.name, unit.card_data.name])
	elif row.get("does", "") == "hero_block":
		game.plan_hero_barrier = int(row.amount)
	elif row.get("does", "") == "draw":
		game.draw_cards(int(row.amount))
	elif row.get("does", "") == "attack_adjacent":
		# Rally works like Coordinated Response: an empty lane breaks the link.
		var targets: Array = armed.targets
		if targets.is_empty() or not eligible(targets[0]):
			game.log_event("%s expired: its unit is gone." % row.name)
			return
		for card in coordination_targets(targets[0]): card.set_plan_attack_bonus(int(row.amount))
		game.log_event("%s gives %s and its neighbours +%d attack this combat." % [row.name,
			targets[0].card_data.name, int(row.amount)])

## Statuses that make a Eureka when one enemy unit has all three.
const REAGENTS := ["burn", "poison", "bleed"]

## Sage's Eureka. card_3d.add_status calls this for every card, both sides and the boss.
## It does nothing unless the kit has "eureka" and a living enemy unit has all three reagents above 0.
func status_added(card: Node) -> void:
	if eureka_running or kit_id() == "": return
	var damage := int(LeaderKits.kit(kit_id()).get("eureka", 0))
	if damage <= 0 or card not in enemy_units(): return
	# Burn can sit at 0 after it halves. A 0 does not count.
	if REAGENTS.any(func(status): return int(card.statuses.get(status, 0)) <= 0): return
	eureka_running = true
	for status in REAGENTS: card.statuses.erase(status)
	card._refresh_face()
	game.vfx.sync_status(card, false)
	card.spawn_popup("EUREKA", UI.AMBER)
	game.log_event("Eureka! %s takes %d." % [card.card_data.name, damage])
	# bypass_armor: armor is ignored, and take_damage never reaches the Disaster's HP.
	card.take_damage(damage, 1.0, true)
	eureka_running = false

func finish_combat() -> void:
	for card in game.get_tree().get_nodes_in_group("cards"):
		if card.has_meta("dash_attack"): card.remove_meta("dash_attack")
		if card.planned_guard > 0 or card.plan_attack_bonus > 0 or card.plan_ignore_taunt:
			card.planned_guard = 0
			card.set_plan_attack_bonus(0)
			card.plan_ignore_taunt = false
			card._refresh_face()
	game.plan_hero_barrier = 0
	armed.clear()
