# Covers: Workshop upgrades moved to run_workshop.gd give the same cards and screens as before the move.
extends SceneTree

# Captured on the original director code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "134de026e69ea7f5c05a740f282df95a647cab48d0ac0b6f8f5a4713e4ba2a61"

var game: Node
var director: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	# Every catalog card through both upgrade tiers, plus the refusal at the limit.
	var results: Array = []
	for card: Dictionary in director.catalog:
		var once: Dictionary = director.upgraded_definition(card)
		var twice: Dictionary = director.upgraded_definition(once)
		var third: Dictionary = director.upgraded_definition(twice)
		results.append([once, twice, third, director.upgrade_level(twice), director.can_upgrade(twice)])
		check(third == twice, "a fully upgraded card does not change: " + str(card.id))
	# The workshop screen and the preview screen.
	director.current = 3
	director.show_upgrade()
	var grid: Node = director.content.get_node("Cards/Grid")
	results.append([director.screen, grid.get_child_count()])
	check(grid.get_child_count() == director.collection.size(), "one tile per collection card")
	director.show_upgrade_preview(1)
	results.append([director.screen, director.content.get_node("Row").get_child_count()])
	var before: Dictionary = director.collection[1].duplicate(true)
	director.upgrade(1)
	results.append([director.collection[1], director.screen])
	check(director.collection[1] == director.upgraded_definition(before) or director.collection[1].name.ends_with("+"),
		"upgrade replaces the chosen card")
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("run_workshop_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("run_workshop_smoke: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("PASS: workshop upgrades and screens match the original director code")
	quit(0)
