extends SceneTree
var game: Node3D
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	var school = game.get_node("SchoolEnvironment")
	var environment: Environment = game.get_node("WorldEnvironment").environment
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		check(environment.ssao_enabled and environment.ssil_enabled and environment.volumetric_fog_enabled and root.use_taa, "desktop lighting includes contact shadows, bounce, haze and temporal smoothing")
	else:
		check(not environment.ssao_enabled and not environment.volumetric_fog_enabled and not root.use_taa, "fallback avoids unsupported lighting effects")
	var room = school.get_node("SuppliedClassroom")
	check(room.has_node("OriginalRoom"), "supplied classroom model is the room")
	check(room.get_node("OriginalRoom").find_children("*", "MeshInstance3D", true, false).size() == 59, "58 retained room meshes and the dedicated game table are present")
	check(not game.has_node("Sketchfab_Scene") and school.has_node("OpponentPosition"), "Monika absent; empty character anchor reserved")
	var source = room.get_node("OriginalRoom")
	var chairs := 0
	for node in source.find_children("*", "MeshInstance3D", true, false):
		if node.get_active_material(0).resource_name == "chair":
			chairs += 1
			var centre: Vector3 = room.to_local(node.to_global(node.get_aabb().get_center()))
			check(centre.z > -1.5, "no chair remains inside the marked rear strip")
	check(chairs == 12, "only the eight marked-area chairs were removed")
	check(source.has_node("GameTable") and school.has_node("PlayerPosition"), "dedicated table and both character positions exist")
	var player_local: Vector3 = room.to_local(school.get_node("PlayerPosition").global_position)
	var janitor_local: Vector3 = room.to_local(school.get_node("OpponentPosition").global_position)
	check(player_local.x < school.DESK_CENTER.x and janitor_local.x > school.DESK_CENTER.x, "player on reference left and janitor on reference right")

	check(school.source_point_to_world(school.DESK_CENTER).is_equal_approx(Vector3(0, 1, 0)), "marked desk top aligns exactly with board origin")
	var table = game.get_node("Table")
	check(not table.visible and not table.use_collision, "old procedural desk is hidden and cannot intercept input")
	check(table.size.x > game.get_node("Playmat").WIDTH and table.size.z > game.get_node("Playmat").DEPTH, "playmat stays within marked desk")
	game.run_director.new_run()
	game.run_director.visit(0)
	for i in 200:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	if game.phase == game.Phase.PLAYER_DRAW: game._on_draw_button_pressed()
	check(game.can_player_act(), "actual encounter remains playable")
	await create_timer(0.7).timeout
	for mode in [game.View.WIDE, game.View.DESK, game.View.BOARD, game.View.WIDE]:
		game.set_view(mode)
		for sample in 7:
			await create_timer(0.1).timeout
			check(school.camera_inside(game.camera.global_position), "camera transition stays inside finished room")
		check(root.get_camera_3d() == game.camera, "game retains its sole active camera")
		await capture("supplied_%d" % mode)
	game.set_view(game.View.BOARD)
	await create_timer(0.7).timeout
	await physics_frame
	for slot in game._response_slots() + game._threat_slots():
		var hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position, slot.global_position + Vector3(0, -0.02, 0)))
		check(not hit.is_empty() and hit.collider.get_parent() == slot, "all eight slot rays remain clear of decoration")
	game.run_director.toggle_map()
	check(game.run_director.screen == "map", "battle map opens")
	game.run_director.toggle_map()
	check(game.run_director.screen == "", "battle map closes")
	game.run_director.show_deck()
	check(game.run_director.screen == "deck", "deck remains available")
	game.run_director.close_modal()
	if DisplayServer.get_name() != "headless": await check_background()
	game.run_director.battle_active = false
	game.run_director.show_map()
	check(not game.visible, "between-room map still hides environment")
	if failures:
		quit(1)
		return
	print("PASS: supplied original room, exact back-row desk alignment, rear strip cleared, dedicated table, left/right empty character anchors, camera paths inside room, no visible void, eight slot raycasts, live encounter, map and deck")
	quit()

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/" + label + ".png")

func check_background() -> void:
	game.run_director.set_process(false)
	game.run_director.root.hide()
	game.get_node("HUD/Root").hide()
	var environment: Environment = game.get_node("WorldEnvironment").environment
	var old_color := environment.background_color
	environment.background_color = Color(1, 0, 1)
	for viewport_size in [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1920, 810)]:
		root.size = viewport_size
		for mode in [game.View.WIDE, game.View.DESK, game.View.BOARD]:
			game._apply_view(game.view_settings(mode))
			await process_frame
			await RenderingServer.frame_post_draw
			var screen := root.get_texture().get_image()
			var exposed := 0
			for y in range(3, screen.get_height(), 16):
				for x in range(3, screen.get_width(), 16):
					var pixel := screen.get_pixel(x, y)
					if pixel.r > 0.5 and pixel.b > 0.5 and pixel.g < 0.12: exposed += 1
			check(exposed == 0, "no background/void pixels in view %d at %s" % [mode, viewport_size])
	environment.background_color = old_color
