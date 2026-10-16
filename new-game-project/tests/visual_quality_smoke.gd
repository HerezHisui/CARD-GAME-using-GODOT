extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/supplied_classroom/play_area_manifest.json"))
	check(FileAccess.get_sha256("res://assets/supplied_classroom/classroom_play_area.glb") == manifest.runtime_glb_sha256, "optimized classroom matches its integrity manifest")
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	var environment: Environment = game.get_node("WorldEnvironment").environment
	var enhanced := RenderingServer.get_current_rendering_method() == "forward_plus"
	check(root.msaa_3d == Viewport.MSAA_4X and root.use_taa == enhanced and is_equal_approx(root.scaling_3d_scale, 1.0), "AA layers use full rendering resolution")
	check(environment.glow_enabled == enhanced and environment.glow_intensity >= 0.5, "bloom is enabled on the supported renderer")
	var finish = game.get_node("ClassroomFinish")
	var effect: ColorRect = finish.get_node("ClarityAndSharpness")
	check(finish.layer < game.get_node("HUD").layer and finish.layer < game.run_director.layer, "clarity grade renders beneath HUD and menus")
	check(effect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "visual grade cannot intercept card input")
	var room = game.get_node("SchoolEnvironment/SuppliedClassroom/OriginalRoom")
	check(room.find_children("*", "MeshInstance3D", true, false).size() == 59, "classroom retains the unaffected room meshes and the new game table")
	check(not game.has_node("Sketchfab_Scene"), "base game excludes Monika")
	var materials := 0
	var normal_maps := 0
	var shared_materials: Dictionary = {}
	for node in room.find_children("*", "MeshInstance3D", true, false):
		for i in node.mesh.get_surface_count():
			var material = node.get_active_material(i)
			var original = node.mesh.surface_get_material(i)
			if original:
				if shared_materials.has(original):
					check(material == shared_materials[original], "authored material instances share one runtime override")
				else: shared_materials[original] = material
			if not material is StandardMaterial3D: continue
			check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "original PBR materials use anisotropic filtering")
			if material.albedo_texture: materials += 1
			if material.normal_enabled and material.normal_texture: normal_maps += 1
	check(materials > 40 and normal_maps > 0, "authored base colours and supplied normal maps are retained")
	game.run_director.start_character(0)
	game.run_director.visit(0)
	for i in 200:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	if game.phase == game.Phase.PLAYER_DRAW: game._on_draw_button_pressed()
	await create_timer(0.8).timeout
	check(game.can_player_act() and game.get_hand_cards().size() > 0, "enhanced rendering leaves real battle input available")
	await process_frame
	check(effect.size.is_equal_approx(root.get_visible_rect().size), "sharpness grade covers the viewport without lowering resolution")
	if DisplayServer.get_name() != "headless":
		if "--msaa-only" in OS.get_cmdline_user_args(): root.use_taa = false
		game.set_view(game.View.WIDE)
		await create_timer(1.0).timeout
		await capture("quality_room")
		game.set_view(game.View.DESK)
		await create_timer(0.8).timeout
		game.clear_hand_hover()
		game.get_hand_cards()[0].set_hand_hover(true)
		game.set_process(false)
		await create_timer(0.4).timeout
		await capture("quality_cards")
		game.run_director.show_title_help(3)
		await capture("quality_help")
	if failures:
		quit(1)
		return
	print("PASS: supplied classroom checksum, new classroom mesh preservation, authored PBR maps, 4x MSAA/TAA/full resolution, supported bloom, clarity/sharpness layer, HUD ordering and live battle")
	quit()

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if "--msaa-only" in OS.get_cmdline_user_args(): label += "_msaa"
	root.get_texture().get_image().save_png("res://tests/artifacts/" + label + ".png")
