# Covers: Room build moved to game_room_setup.gd makes the same environment, board slots and finish as before.
extends SceneTree

# Captured on the original game_3d_manager code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "f27ae8a3b6177efe77587f473be0963ec707955d98d8a5ec16fb1f331cc413a7"

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var results: Array = []
	var env: Environment = game.get_node("WorldEnvironment").environment
	results.append(var_to_str(env))
	results.append(var_to_str(env.sky.sky_material))
	for slot: Node3D in game.get_node("Slots").get_children():
		results.append([str(slot.name), var_to_str(slot.transform), var_to_str(slot.mesh.size)])
	var names: Array = []
	for child in game.get_children():
		if not str(child.name).begins_with("@"): names.append([str(child.name), child.get_class()])
	results.append(names)
	var finish: CanvasLayer = game.get_node("ClassroomFinish")
	var effect: ColorRect = finish.get_node("ClarityAndSharpness")
	results.append([finish.layer, effect.mouse_filter, effect.material.shader.resource_path])
	check(finish.layer == 0 and effect.material.shader != null, "finish layer has its shader")
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("game_room_setup_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("game_room_setup_smoke: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	print("PASS: room build matches the original manager code")
	quit(0)
