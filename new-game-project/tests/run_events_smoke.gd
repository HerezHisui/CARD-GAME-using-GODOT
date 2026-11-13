# Covers: Room events moved to run_events.gd give the same screens and results as before the move.
extends SceneTree

# Captured on the original director code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "72e3b853e6ab86b32aabec0ea7f86f6ecdefc615e16c7be117bdf0f5c52b2f6c"

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

const CASES := [
	["locked", "risk"], ["locked", "safe"], ["radio", "radio_buy"], ["radio", "safe"], ["rooftop", "training"],
	["rooftop", "safe"], ["science", "science_0"], ["science", "science_1"], ["science", "safe"],
	["infirmary", "treatment"], ["infirmary", "rest"], ["lost_found", "safe"],
]

## Every button on the event screen: name, text and whether it is off.
func buttons(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child is Button: out.append([str(child.name), child.text, child.disabled])
		buttons(child, out)
	return out

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	var results: Array = []
	for item: Array in CASES:
		for hp: int in [10, 3]:
			director.new_run()
			director.rng.seed = 777
			director.current = 1
			director.rooms[1].event = item[0]
			director.event_key = ""
			director.coins = 25
			game.player_hp = hp
			director.show_event()
			check(director.screen == "event", "event screen opens: " + item[0])
			results.append([item, hp, buttons(director.modal, []), director.event_cards])
			director.resolve_event(item[1])
			results.append([director.coins, game.player_hp, director.collection, game.player_run_buffs,
				director.screen, director.event_resolved])
	director.resolve_event("safe")
	results.append([director.coins, director.screen])
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("run_events_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("run_events_smoke: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("PASS: room events match the original director code")
	quit(0)
