extends SceneTree
## Screen timing probe. Not a smoke suite (no _smoke in the name).
## Run: godot [--headless] --path . -s tests/perf_probe.gd -- --output=<file.json>
## Any engine or script error makes it print FAILED and exit 1. No sample is kept after an error.

const FRAMES := 300
const WARMUP := 60
const SCREENS := ["title", "map", "battle", "deck", "shop"]

## Catches every error the engine logs, so a broken fixture can never give a sample.
class ErrorCatcher extends Logger:
	var count := 0
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING: return
		count += 1
		if first.is_empty(): first = "%s %s:%d %s %s" % [function, file, line, code, rationale]

## Stamps the time at the start or the end of the node _process pass.
class Stamp extends Node:
	var usec := 0
	func _process(_delta: float) -> void: usec = Time.get_ticks_usec()

var catcher := ErrorCatcher.new()
var first_stamp := Stamp.new()
var last_stamp := Stamp.new()
var game: Node
var director: Node
var results: Array[Dictionary] = []
var output := ""
var windowed := false
var finished := false
var frames_alive := 0

func _initialize() -> void:
	OS.add_logger(catcher)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	windowed = DisplayServer.get_name() != "headless"
	call_deferred("run")

## Watchdog: a script error kills the run coroutine, so stop here instead of hanging.
func _process(_delta: float) -> bool:
	frames_alive += 1
	if catcher.count > 0 and not finished: fail("engine error: " + catcher.first)
	if frames_alive > 20000 and not finished: fail("probe took too long")
	return false

func fail(reason: String) -> void:
	finished = true
	print("FAILED: perf_probe " + reason)
	OS.remove_logger(catcher)
	quit(1)

func run() -> void:
	seed(12345)
	Engine.max_fps = 0
	root.size = Vector2i(1440, 900)
	if windowed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1440, 900))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	first_stamp.process_priority = -1000000
	last_stamp.process_priority = 1000000
	root.add_child(first_stamp)
	root.add_child(last_stamp)
	for screen_name: String in SCREENS:
		await measure(screen_name)
		if finished: return
	var report := {
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"frames": FRAMES,
		"screens": results,
	}
	print("PERF_RESULT " + JSON.stringify(report))
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			fail("cannot write " + output)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	finished = true
	paused = false
	game.queue_free()
	await process_frame
	OS.remove_logger(catcher)
	quit(0)

func next_frame() -> void:
	await process_frame
	if windowed: await RenderingServer.frame_post_draw

## Builds one screen. Returns the build time in ms.
func open_screen(screen_name: String) -> float:
	var started := Time.get_ticks_usec()
	match screen_name:
		"title":
			game = load("res://scenes/game_3d.tscn").instantiate()
			root.add_child(game)
			current_scene = game
			game.presentation.automated_choice = 0
			director = game.run_director
		"map":
			director.selected_character = 0
			director.new_run()
			director.rng.seed = 12345
			director.screen = ""
			director.generate_map()
			director.show_map()
		"battle":
			paused = false
			director.screen = ""
			director.modal.hide()
			director.battle_active = true
			game.start_encounter(director.collection, "battle", 1, 0)
		"deck":
			game.clear_battle()
			director.battle_active = false
			director.screen = ""
			director.show_deck()
		"shop":
			director.screen = ""
			director.show_shop()
	return float(Time.get_ticks_usec() - started) / 1000.0

## Battle only: wait for the coin flip, then put one card on each side.
func fill_battle() -> void:
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	if not game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]:
		fail("battle never reached the player turn")
		return
	var response: Node = game.Card3DScene.instantiate()
	game.add_child(response)
	response.add_to_group("cards")
	response.setup(director.collection[0])
	response.place_on_slot(game._response_slots()[0])
	var threat: Node = game.Card3DScene.instantiate()
	game.add_child(threat)
	threat.add_to_group("cards")
	threat.setup(game.enemy_deck[0])
	threat.place_on_slot(game._threat_slots()[0])

func measure(screen_name: String) -> void:
	var started := Time.get_ticks_usec()
	var build_ms := open_screen(screen_name)
	await next_frame()
	var first_frame_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if screen_name == "battle": await fill_battle()
	if finished: return
	# Let entry tweens settle before the steady samples.
	for i in WARMUP: await next_frame()
	var frame: Array[float] = []
	var script: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in FRAMES:
		await next_frame()
		var now := Time.get_ticks_usec()
		frame.append(float(now - previous) / 1000.0)
		script.append(float(last_stamp.usec - first_stamp.usec) / 1000.0)
		if windowed:
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		previous = now
	if catcher.count > 0 or finished:
		fail("error during " + screen_name + ": " + catcher.first)
		return
	var sample := {
		"screen": screen_name,
		"build_ms": build_ms,
		"first_frame_ms": first_frame_ms,
		"frame_avg_ms": average(frame),
		"frame_worst_ms": frame.max(),
		"script_avg_ms": average(script),
		"script_worst_ms": script.max(),
		"render_cpu_avg_ms": average(render_cpu),
		"render_gpu_avg_ms": average(render_gpu),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_memory_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}
	results.append(sample)
	print("PERF_SCREEN " + JSON.stringify(sample))

func average(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var total := 0.0
	for value in values: total += value
	return total / values.size()
