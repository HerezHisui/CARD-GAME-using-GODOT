# Covers: Original debug availability, selection, live card stats, statuses and real checkpoint parity.
extends SceneTree

const RunDebug = preload("res://scripts/run_debug.gd")
# Captured before replacing the original director methods with wrappers.
const ORIGINAL_RESULTS_SHA256 := "fb9279b5781399c3c5742d3c1c2b20f1248f2967b55fabe2ed99b3bd629e1b10"
const DEFINITIONS := [
	{"name":"Unit", "type":"response", "element":"evac", "cost":2, "attack":3, "health":6},
	{"name":"Enemy", "type":"disaster", "element":"fire", "cost":1, "attack":4, "health":9},
	{"name":"Utility", "type":"response", "element":"evac", "cost":1, "utility":true, "effect":"draw"},
]

class CheckpointProbe:
	extends "res://scripts/run_save.gd"
	var results: Array = []
	var observations: Array = []
	var watched: Node

	func checkpoint() -> bool:
		observations.append([watched.card_data.duplicate(true), watched.max_health,
			watched.statuses.duplicate(true), watched.face_signature == watched.current_face_signature()])
		var result := super.checkpoint()
		results.append(result)
		return result

var game: Node
var director: Node
var probe: CheckpointProbe
var picker := OptionButton.new()
var failures := 0
var comparisons := 0
var result_hash := HashingContext.new()

func _initialize() -> void:
	result_hash.start(HashingContext.HASH_SHA256)
	call_deferred("run")

func same(actual: Variant, expected: Variant, label: String, pin: bool = true) -> void:
	comparisons += 1
	if pin: result_hash.update(var_to_bytes(expected))
	if actual != expected:
		failures += 1
		if failures <= 10: push_error("FAILED: " + label)

func live_card(definition: Dictionary) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.statuses = {"strength":2, "bleed":1, "burn":3, "poison":2, "barrier":4, "healing_reduced":1}
	card._refresh_face()
	game.hand.append(card)
	return card

func card_state(card: Node) -> Array:
	return [card.card_data.duplicate(true), card.max_health, card.statuses.duplicate(true),
		card.modifiers.duplicate(), card.base_definition.duplicate(true),
		card.face_signature == card.current_face_signature()]

func compare_edit(first: Node, second: Node, key: String, value: float) -> void:
	first.in_hand = true
	second.in_hand = false
	probe.watched = first
	probe.results.clear()
	probe.observations.clear()
	director._debug_set_card_stat(value, [first], picker, key)
	var results: Array = probe.results.duplicate()
	var observations: Array = probe.observations.duplicate(true)
	var saved: Dictionary = probe.read_save()
	first.in_hand = false
	second.in_hand = true
	probe.watched = second
	probe.results.clear()
	probe.observations.clear()
	var selected := RunDebug._debug_selected_card([second], picker.selected)
	if RunDebug._debug_set_card_stat(value, selected, key): probe.checkpoint()
	same(card_state(second), card_state(first), key + " live card state")
	same(probe.results, results, key + " checkpoint calls and results")
	same(probe.observations, observations, key + " state and face refreshed before checkpoint")
	same(probe.read_save(), saved, key + " complete saved snapshot", false)
	var accepted: bool = key == "cost" or not first.card_data.get("utility", false)
	same(results.size(), 1 if accepted else 0, key + " checkpoint count")
	if accepted:
		same(results[0], not probe.restoring, key + " checkpoint success or refusal")
		if not probe.restoring:
			same(saved.cards.size(), 1, "one live twin saved")
			same(saved.cards[0].data, first.card_data, "checkpoint contains updated card")
			same(saved.cards[0].runtime.max_health, first.max_health, "checkpoint contains healing ceiling")
			same(saved.cards[0].runtime.statuses, first.statuses, "checkpoint contains all six statuses")

func compare_cards() -> void:
	for definition: Dictionary in DEFINITIONS:
		var first := live_card(definition)
		var second := live_card(definition)
		var original: Dictionary = first.base_definition.duplicate(true)
		var statuses: Dictionary = first.statuses.duplicate(true)
		for restoring: bool in [false, true]:
			probe.restoring = restoring
			for key: String in ["cost", "attack", "health"]:
				for value: float in [12.0, 3.0, 0.0, -2.0, 4.9, 10000.0]:
					compare_edit(first, second, key, value)
		probe.restoring = false
		same(first.base_definition, original, "original definition preserved")
		same(first.statuses, statuses, "existing statuses preserved")
		first.free()
		second.free()
		game.hand.clear()

func compare_selection(targets: Array, index: int, expected: Node) -> void:
	picker.select(index)
	same(director._debug_selected_card(targets, picker) == expected, true, "original selection")
	same(RunDebug._debug_selected_card(targets, picker.selected) == expected, true, "static selection")

func compare_selection_guards() -> void:
	var card := live_card(DEFINITIONS[0])
	compare_selection([card], 0, card)
	compare_selection([], 0, null)
	compare_selection([null], 0, null)
	compare_selection([card], -1, null)
	compare_selection([card], 1, null)
	card.preview_only = true
	compare_selection([card], 0, null)
	card.preview_only = false
	card.card_data.health = 0
	compare_selection([card], 0, null)
	card.card_data.health = 6
	card.in_hand = false
	compare_selection([card], 0, null)
	card.current_slot = game._response_slots()[0]
	compare_selection([card], 0, card)
	var stale: Array = [card]
	card.free()
	compare_selection(stale, 0, null)
	game.hand.clear()
	picker.select(0)
	probe.results.clear()
	director._debug_set_card_stat(8, stale, picker, "attack")
	if RunDebug._debug_set_card_stat(8, RunDebug._debug_selected_card(stale, 0), "attack"):
		probe.checkpoint()
	same(probe.results, [], "stale target never checkpoints")

func compare_availability() -> void:
	var card := live_card(DEFINITIONS[0])
	for active: bool in [false, true]:
		director.battle_active = active
		for phase: int in game.Phase.values():
			game.phase = phase
			for pending: bool in [false, true]:
				game.board_input.action = {"kind":"pick"} if pending else {}
				for drag_mode: int in range(3):
					game.dragged_hand_card = null if drag_mode == 0 else card
					card.is_dragging = drag_mode == 2
					same(RunDebug.debug_available(game, active), director.debug_available(), "debug availability")
	game.dragged_hand_card = null
	game.board_input.action.clear()
	card.is_dragging = false
	card.free()
	game.hand.clear()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.new_run()
	game.clear_battle()
	game.set_process(false)
	director.screen = "debug"
	director.battle_active = true
	game.phase = game.Phase.PLAYER_PLAY
	probe = CheckpointProbe.new()
	director.add_child(probe)
	probe.setup(director)
	director.persistence = probe
	picker.add_item("First")
	picker.add_item("Out of range")
	picker.select(0)
	var collection: Array = director.collection.duplicate(true)
	compare_cards()
	same(director.collection, collection, "collection preserved", false)
	compare_selection_guards()
	compare_availability()
	var checksum := result_hash.finish().hex_encode()
	if checksum != ORIGINAL_RESULTS_SHA256:
		failures += 1
		push_error("FAILED: original debug output checksum")
	probe.discard()
	picker.free()
	if failures > 0:
		quit(1)
		return
	print("PASS: run_debug_smoke (%d comparisons)" % comparisons)
	quit(0)
