# Covers: Buff choices moved to run_buffs.gd give the same screens and results as before the move.
extends SceneTree

# Captured on the original director code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "192fca9c693467ea4cb32667b3788dc763b9e8ba5f578ae4862ee9d84d2d6149"

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

## Every button and label on the screen: name and text.
func texts(node: Node, out: Array) -> Array:
	for child in node.get_children():
		# Names made by the engine (@Label@12) change from run to run, so they are left out.
		var node_name: String = "" if str(child.name).begins_with("@") else str(child.name)
		if child is Button or child is Label: out.append([node_name, child.text])
		texts(child, out)
	return out

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.new_run()
	var results: Array = []
	results.append(director.buff_summary({}))
	results.append(director.buff_summary({"strength": 2, "unknown_id": 1, "glass": 1}))
	# Battle adaptation: offer, refuse a wrong id, then pick the first.
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game.start_encounter(director.collection, "battle", 1, 0)
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	check(game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY], "battle reaches the player turn")
	director.rng.seed = 4242
	director.show_buff_choices()
	await process_frame
	check(director.screen == "buff", "adaptation screen opens")
	results.append([director.screen, director.buff_choices, texts(director.modal, [])])
	director.select_buff("not_offered")
	results.append([director.screen, game.player_buffs])
	director.show_buff_choices(true)
	results.append([director.screen, director.buff_choices, texts(director.modal, [])])
	var picked: String = director.buff_choices[0].id
	director.select_buff(picked)
	results.append([game.player_buffs.has(picked), director.modal.visible])
	check(game.player_buffs.has(picked), "picked adaptation is added")
	# Floor reward: offer, refuse a wrong id, then pick the second.
	game.clear_battle()
	director.battle_active = false
	director.screen = ""
	director.rng.seed = 4343
	director.show_floor_buffs()
	check(director.screen == "floor_buff", "floor reward screen opens")
	results.append([director.screen, director.buff_choices, texts(director.modal, [])])
	director.select_floor_buff("not_offered")
	results.append([director.screen, director.floor_number])
	var reward: String = director.buff_choices[1].id
	director.select_floor_buff(reward)
	results.append([game.player_run_buffs, director.floor_number, director.screen])
	check(game.player_run_buffs.has(reward), "floor reward lasts the run")
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("run_buffs_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("run_buffs_smoke: %d checks, %d failures" % [checks, failures])
	paused = false
	if failures > 0:
		quit(1)
		return
	print("PASS: buff choices match the original director code")
	quit(0)
