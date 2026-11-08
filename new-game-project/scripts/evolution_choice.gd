extends RefCounted
## Local human Versus evolution ownership. IDs identify physical copies, including duplicate definitions.
const UI = preload("res://scripts/ui_theme.gd")
var game: Node
var held: Array[Dictionary] = []
var offer: Array[Dictionary] = []
var serial := -1
var next_id := 0
var offer_id := 0
var preview_id := ""
# These identities stay host-owned. Reserve indices never belong in a recipient view.
var match_id := ""
var offer_phase := -1
var reserve_copies: Array[Dictionary] = []
var resolving_token := ""

func _init(owner_game: Node) -> void:
	game = owner_game

func enabled() -> bool:
	if not is_instance_valid(game): return false
	if game.encounter_kind != "versus" or not game.disaster_is_human: return false
	if game.lan_remote_prep or game.lan_remote_disaster: return lan_enabled()
	if game.evolution_draw_choice_override is bool: return game.evolution_draw_choice_override
	return preload("res://scripts/versus_match.gd").EVOLUTION_DRAW_CHOICE

func lan_enabled() -> bool:
	if not is_instance_valid(game) or not (game.lan_remote_prep or game.lan_remote_disaster): return false
	if game.encounter_kind != "versus" or not game.disaster_is_human: return false
	if game.lan_evolution_picks_override is bool: return game.lan_evolution_picks_override
	return preload("res://scripts/versus_match.gd").LAN_EVOLUTION_PICKS

func pending() -> bool:
	if not is_instance_valid(game): return false
	return enabled() and not offer.is_empty() and serial == game.encounter_serial

func reset() -> void:
	if lan_enabled():
		match_id = Crypto.new().generate_random_bytes(16).hex_encode()
		offer_id = 0
		if is_instance_valid(game.run_director) and game.run_director.screen == "evolution_offer":
			game.run_director.close_modal()
	reserve_copies.clear()
	resolving_token = ""
	offer_phase = -1
	held.clear()
	offer.clear()
	preview_id = ""
	serial = game.encounter_serial

func draw() -> void:
	if pending(): return
	if lan_enabled():
		if not enabled() or game.phase not in [game.Phase.SETUP, game.Phase.ENEMY]: return
		if match_id.is_empty(): reset()
		_sync_reserve_copies()
	if held.size() >= 2:
		game.log_event("Evolution draw skipped, 2 held")
		if game.run_director.versus_hud.active:
			game.run_director.versus_hud.show_note("Evolution draw skipped, 2 held", "")
		return
	serial = game.encounter_serial
	offer_id += 1
	offer_phase = game.phase
	var indices: Array = range(game.enemy_evolution_deck.size())
	indices.shuffle()
	for index in indices.slice(0, 3):
		if lan_enabled():
			var copy: Dictionary = reserve_copies[index]
			offer.append({"id": copy.id, "index": index, "definition": copy.definition})
			continue
		next_id += 1
		offer.append({"id": "evolution_%d" % next_id, "index": index,
			"definition": game.enemy_evolution_deck[index]})

func _sync_reserve_copies() -> void:
	var remaining := reserve_copies.duplicate()
	reserve_copies.clear()
	for value in game.enemy_evolution_deck:
		var found := -1
		for i in remaining.size():
			if is_same(remaining[i].definition, value):
				found = i
				break
		if found >= 0:
			reserve_copies.append(remaining[found])
			remaining.remove_at(found)
		else:
			next_id += 1
			var copy_id := "evolution_" + Crypto.new().generate_random_bytes(16).hex_encode()
			reserve_copies.append({"id": copy_id, "definition": value})

func definition(id: String) -> Dictionary:
	for entry in held:
		if entry.id == id: return entry.definition
	return {}

func id_for(value: Dictionary) -> String:
	for entry in held:
		if is_same(entry.definition, value): return entry.id
	return ""

func pick(id: String, expected_offer: int, expected_serial: int, expected_match: String = "") -> bool:
	if not pending() or expected_offer != offer_id or expected_serial != serial: return false
	if lan_enabled():
		if expected_match != match_id or held.size() >= 2 or game.phase != offer_phase: return false
		if game.phase not in [game.Phase.SETUP, game.Phase.ENEMY]: return false
	for entry in offer:
		if entry.id != id: continue
		var index: int = entry.index
		if index >= game.enemy_evolution_deck.size(): return false
		if not is_same(entry.definition, game.enemy_evolution_deck[index]): return false
		game.enemy_evolution_deck.remove_at(index)
		if lan_enabled(): reserve_copies.remove_at(index)
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
	var choose := _choose_lan.bind(offer_id, serial, match_id) if lan_enabled() else _choose
	director.choose_card("CHOOSE AN EVOLUTION", cards, choose, Callable(),
		"Choose 1. The other cards stay in the deck.", true)
	director.content.get_node("CancelButton").hide()
	_style_offer(director)
	director.screen = "evolution_offer"
	game.get_tree().paused = false

## The offer is one centered row of equal cards. A double click on a card chooses it (no Choose button), and
## a card glows when the mouse is over it. The row has no scroll area, so no dead space is left under it.
func _style_offer(director: Node) -> void:
	var scroll: Control = director.content.get_node("Cards")
	var row: HBoxContainer = scroll.get_node("Row")
	scroll.remove_child(row)
	director.content.add_child(row)
	director.content.move_child(row, scroll.get_index())
	scroll.queue_free()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 28)
	for tile: PanelContainer in row.get_children():
		tile.custom_minimum_size.x = 260
		tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.get_node("Box/Center").size_flags_vertical = Control.SIZE_EXPAND_FILL
		var plain: StyleBox = tile.get_theme_stylebox("panel")
		var glow: StyleBoxFlat = director.style(UI.PANEL, UI.GOLD)
		glow.set_border_width_all(3)
		glow.shadow_color = Color(UI.GOLD, 0.45)
		glow.shadow_size = 10
		tile.mouse_entered.connect(func(): tile.add_theme_stylebox_override("panel", glow))
		tile.mouse_exited.connect(func(): tile.add_theme_stylebox_override("panel", plain))

func _choose_lan(value: Dictionary, expected_offer: int, expected_serial: int, expected_match: String) -> void:
	for entry in offer:
		if is_same(entry.definition, value):
			if pick(entry.id, expected_offer, expected_serial, expected_match): game.run_director.close_modal()
			return

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
		game.run_director.close_modal, "Choose a card, then click its sacrifice lane on the board.", true)

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
	if lan_enabled(): return await _resolve_lan()
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

func _resolve_lan() -> bool:
	var encounter: int = game.encounter_serial
	var identity := match_id
	var token := "%s:%d" % [identity, offer_id]
	if resolving_token == token: return false
	resolving_token = token
	if not game.lan_remote_disaster:
		game.run_director.privacy_screen.hide()
		show_offer()
	while is_instance_valid(game):
		if encounter != game.encounter_serial or identity != match_id or game.phase == game.Phase.GAME_OVER:
			return false
		if not pending():
			if resolving_token == token: resolving_token = ""
			return true
		await game.get_tree().process_frame
	return false
