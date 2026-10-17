extends SceneTree
var game: Node3D
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func key(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func settle() -> void:
	for i in 8:
		await create_timer(.08).timeout
		check(game.get_node("SchoolEnvironment").camera_inside(game.camera.global_position), "view transition remains inside the classroom")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/camera_" + label + ".png")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	game.run_director.new_run()
	game.run_director.visit(0)
	for i in 200:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(.1).timeout
	if game.phase == game.Phase.PLAYER_DRAW: game._on_draw_button_pressed()
	check(game.can_player_act(), "real encounter accepts input")
	await settle()
	var school := game.get_node("SchoolEnvironment")
	var enemy_position: Vector3 = school.get_node("OpponentPosition").global_position + Vector3.UP * 6.2
	var window_position: Vector3 = school.source_point_to_world(Vector3(3.94, 2, -3.0))
	for slot in game._response_slots() + game._threat_slots():
		var screen: Vector2 = game.camera.unproject_position(slot.global_position)
		check(root.get_visible_rect().grow(-80).has_point(screen), "normal view frames all eight playable lanes")
	await capture("normal")
	await key(KEY_S)
	check(game.view_mode == game.View.WIDE, "S opens the wider view")
	await settle()
	check(absf(game.get_node("CameraPivot").rotation_degrees.y) <= 15, "S keeps the opponent-facing side instead of orbiting 90 degrees")
	for point in [enemy_position, window_position]:
		check(not game.camera.is_position_behind(point), "enemy/window remain in front of the wide camera")
		check(root.get_visible_rect().grow(-80).has_point(game.camera.unproject_position(point)), "wide view retains enemy and window framing")
	await capture("s_view")
	await key(KEY_S)
	check(game.view_mode == game.View.WIDE, "S at the outer limit stays wide")
	await key(KEY_W)
	check(game.view_mode == game.View.DESK, "W returns to normal")
	await key(KEY_W, true)
	check(game.view_mode == game.View.DESK, "keyboard repeats cannot skip a view")
	await key(KEY_W)
	check(game.view_mode == game.View.BOARD and game.in_board_view, "W opens overhead")
	await settle()
	await capture("overhead")
	await key(KEY_S)
	check(game.view_mode == game.View.DESK and not game.in_board_view, "S returns overhead to normal")
	await settle()
	# Reverse direction before the tween finishes, then immediately continue.
	await key(KEY_S)
	await create_timer(.12).timeout
	await key(KEY_W)
	await key(KEY_W)
	await settle()
	check(game.view_mode == game.View.BOARD and is_equal_approx(game.camera.position.z, game.BOARD_VIEW.dist), "rapid reversals finish at the requested camera")
	game.run_director.show_deck()
	await key(KEY_S)
	check(game.view_mode == game.View.BOARD, "deck modal does not consume S as camera movement")
	game.run_director.close_modal()
	check(root.get_camera_3d() == game.camera, "game retains its active camera")
	if failures:
		quit(1)
		return
	print("PASS: eight-lane normal framing, enemy/window wide framing, actual W/S keys, view limits, echo suppression, contained transitions, rapid reversals, modal guard and overhead camera")
	quit()
