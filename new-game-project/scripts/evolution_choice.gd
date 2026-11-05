extends RefCounted
## Local human Versus evolution ownership. IDs identify physical copies, including duplicate definitions.
var game: Node
var held: Array[Dictionary] = []
var offer: Array[Dictionary] = []
var serial := -1
var next_id := 0
var offer_id := 0
var preview_id := ""

func _init(owner_game: Node) -> void:
	game = owner_game

func enabled() -> bool:
	if not is_instance_valid(game): return false
	return (preload("res://scripts/versus_match.gd").EVOLUTION_DRAW_CHOICE
		or game.evolution_draw_choice_override) and game.encounter_kind == "versus" \
		and game.disaster_is_human and not game.lan_remote_prep and not game.lan_remote_disaster

func pending() -> bool:
	if not is_instance_valid(game): return false
	return enabled() and not offer.is_empty() and serial == game.encounter_serial

func reset() -> void:
	held.clear()
	offer.clear()
	preview_id = ""
	serial = game.encounter_serial

func draw() -> void:
	if pending(): return
	if held.size() >= 2:
		game.log_event("Evolution draw skipped, 2 held")
		if game.run_director.versus_hud.active:
			game.run_director.versus_hud.show_note("Evolution draw skipped, 2 held", "")
		return
	serial = game.encounter_serial
	offer_id += 1
	var indices: Array = range(game.enemy_evolution_deck.size())
	indices.shuffle()
	for index in indices.slice(0, 3):
		next_id += 1
		offer.append({"id": "evolution_%d" % next_id, "index": index,
			"definition": game.enemy_evolution_deck[index]})

func definition(id: String) -> Dictionary:
	for entry in held:
		if entry.id == id: return entry.definition
	return {}

func id_for(value: Dictionary) -> String:
	for entry in held:
		if is_same(entry.definition, value): return entry.id
	return ""

func pick(id: String, expected_offer: int, expected_serial: int) -> bool:
	if not pending() or expected_offer != offer_id or expected_serial != serial: return false
	for entry in offer:
		if entry.id != id: continue
		var index: int = entry.index
		if index >= game.enemy_evolution_deck.size(): return false
		if not is_same(entry.definition, game.enemy_evolution_deck[index]): return false
		game.enemy_evolution_deck.remove_at(index)
		held.append({"id": id, "definition": entry.definition})
		offer.clear()
		game.log_event("Disaster holds an evolution.")
		return true
	return false

func consume(id: String) -> void:
	for i in held.size():
		if held[i].id == id:
			held.remove_at(i)
			preview_id = ""
			return

func definitions() -> Array:
	return held.map(func(entry): return entry.definition)

func show_offer() -> void:
	if not pending(): return
	var director: Node = game.run_director
	var cards: Array = offer.map(func(entry): return entry.definition)
	director.choose_card("CHOOSE AN EVOLUTION", cards, _choose, Callable(), "Choose 1. The other cards stay in the deck.")
	director.content.get_node("CancelButton").hide()
	director.screen = "evolution_offer"
	game.get_tree().paused = false

func _choose(value: Dictionary) -> void:
	for entry in offer:
		if is_same(entry.definition, value):
			if pick(entry.id, offer_id, serial): game.run_director.close_modal()
			return

func show_held() -> void:
	if pending():
		show_offer()
		return
	if not enabled() or not game.disaster_seat_on: return
	game.run_director.choose_card("HELD EVOLUTIONS", definitions(), _preview,
		game.run_director.close_modal, "Choose a card, then click its sacrifice lane on the board.")

func _preview(value: Dictionary) -> void:
	preview_id = id_for(value)
	game.run_director.close_modal()
	game.disaster_seat._sync_hand()
	for card in game.disaster_seat.cards:
		if is_same(card.get_meta("seat_def"), value):
			game.disaster_seat.selected = card
	game.disaster_seat._arrange()

func resolve() -> bool:
	if not is_instance_valid(game): return false
	var encounter: int = game.encounter_serial
	if not pending(): return true
	game.hide_versus_hand()
	game.run_director.privacy_serial = encounter
	game.run_director.privacy_last = "disaster"
	game.run_director.show_privacy_cover("DISASTER, choose an evolution")
	while true:
		if not is_instance_valid(game): return false
		if encounter != game.encounter_serial or game.phase == game.Phase.GAME_OVER: return false
		if not game.run_director.privacy_screen.visible: break
		await game.get_tree().process_frame
	show_offer()
	while true:
		if not is_instance_valid(game): return false
		if encounter != game.encounter_serial or game.phase == game.Phase.GAME_OVER: return false
		if not pending(): break
		await game.get_tree().process_frame
	if not is_instance_valid(game): return false
	return encounter == game.encounter_serial
