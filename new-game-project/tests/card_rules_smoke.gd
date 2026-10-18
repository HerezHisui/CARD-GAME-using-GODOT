# Covers: Card sorting, prices and upgrade queries across catalogs and upgrade levels.
extends SceneTree

const CardRules = preload("res://scripts/run_card_rules.gd")
const CATALOG_PATHS := [
	"res://data/starter_deck.json",
	"res://data/response_expansion.json",
	"res://data/disaster_deck.json",
	"res://data/disaster_expansion.json",
]
# Captured against the original director methods before wrapper integration.
const ORIGINAL_RESULTS_SHA256 := "32bea4d0e728bae97a0e81e0456fa753bdb6c48d2a782e5b8ae515fe6ce90b31"

var director: Node
var failures := 0
var comparisons := 0
var result_hash := HashingContext.new()

func _initialize() -> void:
	result_hash.start(HashingContext.HASH_SHA256)
	call_deferred("run")

func same(actual: Variant, expected: Variant, label: String) -> void:
	comparisons += 1
	result_hash.update(var_to_bytes(expected))
	if actual != expected:
		failures += 1
		push_error("FAILED: " + label)

func catalog_cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for path: String in CATALOG_PATHS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Array:
			failures += 1
			push_error("FAILED: catalog must contain an array: " + path)
			continue
		for definition: Dictionary in parsed:
			cards.append(definition)
	return cards

func compare_card(card: Dictionary) -> Dictionary:
	var before: Dictionary = card.duplicate(true)
	var label := str(card.get("id", card.get("name", "fixture")))
	same(CardRules.shop_price(card), director.shop_price(card), label + " price")
	same(CardRules.upgrade_level(card), director.upgrade_level(card), label + " upgrade level")
	same(CardRules.can_upgrade(card, int(director.MAX_UPGRADES)), director.can_upgrade(card), label + " cap")
	var upgraded: Dictionary = director.upgraded_definition(card)
	# This manager-dependent method stays in the director; pin its original outputs too.
	same(upgraded, director.upgraded_definition(card.duplicate(true)), label + " upgrade result")
	same(card, before, label + " query input unchanged")
	return upgraded

func compare_sort(cards: Array) -> void:
	var before: Array = cards.duplicate(true)
	for key_index: int in CardRules.SORT_KEYS.size():
		for descending: bool in [false, true]:
			same(CardRules.sorted_indices(cards, key_index, descending),
				director.sorted_indices(cards, key_index, descending), "sort key %d" % key_index)
	same(cards, before, "sorting input unchanged")

func compare_catalog(cards: Array[Dictionary]) -> void:
	var current: Array[Dictionary] = cards.duplicate(true)
	for level: int in range(int(director.MAX_UPGRADES) + 1):
		compare_sort(current)
		var next: Array[Dictionary] = []
		for card: Dictionary in current:
			next.append(compare_card(card))
		current = next
	compare_sort(current)

func compare_fixtures() -> void:
	var cards: Array[Dictionary] = [
		{"name": "Card 10", "acquired": 2},
		{"name": "card 2", "acquired": 1},
		{"name": "card 2", "acquired": 2},
		{"name": "Plain++"},
		{"name": "Explicit++", "upgrades": 0},
	]
	compare_sort([])
	compare_sort(cards)
	for card: Dictionary in cards:
		same(CardRules.upgrade_level(card), director.upgrade_level(card), "legacy upgrade level")
		same(CardRules.can_upgrade(card, int(director.MAX_UPGRADES)), director.can_upgrade(card), "legacy cap")
		same(CardRules.can_upgrade(card, 0), false, "explicit zero cap")

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	director = game.run_director
	await process_frame
	var cards: Array[Dictionary] = catalog_cards()
	same(cards.size(), 65, "all JSON catalog definitions loaded")
	same(CardRules.SORT_KEYS, director.SORT_KEYS, "sort keys")
	compare_catalog(cards)
	compare_fixtures()
	var checksum := result_hash.finish().hex_encode()
	if checksum != ORIGINAL_RESULTS_SHA256:
		failures += 1
		push_error("FAILED: original card-rule output checksum")
	if failures > 0:
		quit(1)
		return
	print("PASS: card_rules_smoke (%d comparisons)" % comparisons)
	quit(0)
