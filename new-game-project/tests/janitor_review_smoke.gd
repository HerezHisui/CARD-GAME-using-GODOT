extends SceneTree
## Targeted game/animation review. Captures are opt-in and never touch the player's save.
var failures := 0
var output := ""
var target_size := Vector2i(1440, 900)
var game: Node
var director: Node
var cloth_updates := 0
var cloth_skin_error := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func capture(filename: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	check(pixels.get_size() == target_size, "Rendered capture matches requested dimensions")
	pixels.save_png(output.path_join(filename + ".png"))

func battle() -> void:
	paused = false
	game.show()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.ENEMY)
	game.presentation.clear_banner()
	game.opponent_hand.refresh()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--width=1280": target_size = Vector2i(1280, 800)
	root.size = target_size
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	await splash_checks()
	game = preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await create_timer(0.6).timeout
	await capture("title")
	var logo: TextureRect = director.content.get_node("TitleScreen/TitleBox/GameLogo")
	check(root.get_visible_rect().encloses(logo.get_global_rect()), "Title logo stays within window margins")
	check(logo.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Title logo keeps supplied aspect ratio")
	director.new_run()
	battle()
	game.enemy_hand.assign([{"id":"review_unit", "name":"Review Threat", "type":"disaster",
		"element":"fire", "cost":0, "attack":1, "health":3, "tension_cost":1}])
	game.opponent_hand.refresh()
	game._apply_view(game.DESK_VIEW)
	await create_timer(0.5).timeout
	var character: Node3D = game.opponent_hand.character
	var hood: Vector2 = game.camera.unproject_position(character.to_global(Vector3(0, 1.99, 0)))
	check(hood.y > 60 and hood.y < target_size.y * .4, "Desk camera frames hood below HUD")
	await capture("janitor_desk")
	game._apply_view(game.WIDE_VIEW)
	await create_timer(0.3).timeout
	await capture("janitor_wide")
	game._apply_view(game.BOARD_VIEW)
	await create_timer(0.3).timeout
	await capture("janitor_board")
	game._apply_view(game.DESK_VIEW)
	await gameplay_checks()
	await stage_checks()
	director.persistence.discard()
	game.queue_free()
	await process_frame
	print("JANITOR REVIEW: %d failures" % failures)
	quit(1 if failures else 0)

func splash_checks() -> void:
	var splash := preload("res://scenes/startup.tscn").instantiate()
	splash.next_scene = ""
	splash.hold_seconds = 10
	root.add_child(splash)
	await create_timer(0.5).timeout
	await capture("studio_splash")
	var complete := [false]
	splash.finished.connect(func(): complete[0] = true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(target_size) * 0.5
	press.pressed = true
	root.push_input(press, true)
	check(splash.dismissing, "Mouse press starts splash dismissal")
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await create_timer(0.6).timeout
	check(complete[0], "Splash fade completes after release")
	splash.queue_free()
	await process_frame

func gameplay_checks() -> void:
	var character: Node3D = game.opponent_hand.character
	game.turn = 3
	game.tension = 1
	game.enemy_deck.clear()
	game.enemy_evolution_deck.clear()
	await game._enemy_turn()
	var unit_count := 0
	for slot in game._threat_slots():
		var card = game._get_card_in_slot(slot)
		if card and card.card_data.id == "review_unit": unit_count += 1
	check(unit_count == 1 and game.enemy_hand.is_empty(), "Real enemy turn plays the chosen unit exactly once")
	check(game.tension == 0, "Presentation does not spend extra resources")
	await capture("actual_enemy_play")
	character.play_card({"id":"interrupted"})
	director.battle_active = false
	game.clear_battle()
	game.opponent_hand.refresh()
	check(character.playing.get_child_count() == 0 and not character.visible,
		"Encounter cleanup hides character and clears selected card")
	check(character.cloth.points == character.cloth.rest, "Encounter cleanup resets cloth")
	battle()
	game.enemy_hand.assign([{"id":"review_spell", "name":"Review Seal", "utility":true,
		"type":"disaster", "element":"fire", "effect":"seal", "tension_cost":1}])
	game.add_card_to_hand(director.collection[0])
	game.tension = 1
	await game._enemy_turn()
	check(game.enemy_hand.is_empty() and game.tension == 0, "Utility gesture leaves single-spend spell behavior intact")
	check(game.get_hand_cards()[0].card_data.get("locked_until", 0) > 0, "Real enemy utility effect resolves")
	game._set_phase(game.Phase.PLAYER_PLAY)
	check(director.persistence.checkpoint(), "Battle checkpoint remains available")
	director.show_title()
	await create_timer(0.4).timeout
	check(director.content.get_node_or_null("TitleScreen/Menu/ContinueButton") != null,
		"Title preserves Continue for saved run")
	check(root.find_child("Startup", true, false) == null, "Returning to title does not replay splash")
	await capture("title_continue")
	check(director.persistence.resume(), "Continue restores battle")
	game.opponent_hand.refresh()
	check(character.visible and character.playing.get_child_count() == 0, "Continue restores clean opponent presentation")
	await evolution_and_boss_checks()
	if DisplayServer.get_name() != "headless":
		create_timer(.15).timeout.connect(func():
			director.battle_active = false
			game.clear_battle()
		)
		var completed: bool = await game._present_enemy_card({"id":"cancel_during_present"})
		check(not completed, "Encounter change cancels pending presentation before gameplay resumes")
		check(character.playing.get_child_count() == 0, "Interrupted handoff cannot leave a selected card")

func evolution_and_boss_checks() -> void:
	game.clear_battle()
	battle()
	game.encounter_kind = "elite"
	game.turn = 3
	game.tension = 1
	game.enemy_hand.assign([{"id":"review_evolution", "name":"Review Evolution", "type":"disaster",
		"element":"fire", "cost":1, "attack":8, "health":8}])
	var base: Node = game.Card3DScene.instantiate()
	game.add_child(base)
	base.add_to_group("cards")
	base.setup({"id":"review_sacrifice", "name":"Review Sacrifice", "type":"disaster",
		"element":"fire", "cost":0, "attack":1, "health":1})
	base.place_on_slot(game._threat_slots()[0])
	await game._enemy_turn()
	var evolved: Node = game._get_card_in_slot(game._threat_slots()[0])
	check(evolved != null and evolved.card_data.id == "review_evolution", "Real evolution resolves after gesture")
	check(game.enemy_hand.is_empty(), "Evolution is removed from enemy hand once")
	await capture("actual_evolution_play")
	game.clear_battle()
	battle()
	game.final_boss = preload("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	game.enemy_hp = 34
	game.player_hp = 34
	game.turn = 2
	game.opponent_hand.refresh()
	game.final_boss.resolve_intent()
	check(game.opponent_hand.character.action_kind == "warden", "Real Warden intent triggers its separate gesture")
	check(game.opponent_hand.character.playing.get_child_count() == 0 and game.enemy_hand.is_empty(),
		"Scripted Warden actions do not fabricate hand cards")
	await create_timer(.35).timeout
	await capture("warden_pattern")

func stage_checks() -> void:
	# Isolate the character for deformation and grip review with neutral illumination.
	director.set_process(false)
	game.set_process(false)
	game.hide()
	game.get_node("HUD").hide()
	director.root.hide()
	game.presentation.hide()
	game.turn_banner.hide()
	var container := SubViewportContainer.new()
	root.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.size = target_size
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var character := preload("res://scripts/janitor_character.gd").new()
	stage.add_child(character)
	character.set_encounter(true)
	character.set_hand_count(5)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 1.1, 3.5)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.3
	camera.make_current()
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 2.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.13, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	character.cloth.modification_processed.connect(func():
		cloth_updates += 1
		var index: int = character.cloth.bone_ids[39]
		var actual: Vector3 = character.skeleton.get_bone_global_pose(index).origin
		cloth_skin_error = maxf(cloth_skin_error, actual.distance_to(character.cloth.points[39]))
	)
	await create_timer(0.5).timeout
	await capture("rig_idle")
	var idle_skin := verify_imported_skin(character, "idle")
	check(cloth_updates > 0, "Skeleton modifier actually applies simulated cloth")
	check(cloth_skin_error < .0001, "Applied cloth skin bone matches simulated particle")
	character.play_card({"id":"pose_review"})
	character.set_process(false)
	# Sample the clip itself, without a paused transition retaining its idle contribution.
	character.animation.stop()
	character.animation.play("card_play", 0)
	character.animation.advance(0)
	character.animation.pause()
	for sample in [0.26, 0.52, 0.72, 1.2]:
		character.animation.seek(sample, true)
		await process_frame
		await capture("rig_play_%03d" % int(sample * 100))
		var posed := verify_imported_skin(character, "play_%03d" % int(sample * 100))
		if sample == .72 and not idle_skin.is_empty():
			var motion := 0.0
			for i in posed.size(): motion = maxf(motion, posed[i].distance_to(idle_skin[i]))
			check(motion > .02, "Rendered play gesture actually deforms the mesh away from idle")
	character.cancel_action()
	character.set_process(true)
	for cycle in 3:
		character.play_card({"id":"cloth_cycle_%d" % cycle})
		await create_timer(.6).timeout
		await capture("cloth_motion_%d" % cycle)
		verify_imported_skin(character, "live_cloth_%d" % cycle)
		character.set_encounter(false)
		check(character.cloth.points == character.cloth.rest, "Interrupted gesture resets cloth exactly")
		character.set_encounter(true)
		await create_timer(.1).timeout
	camera.position = Vector3(3, 1.1, 1.2)
	camera.look_at(Vector3(0, 1.1, 0))
	await create_timer(0.3).timeout
	await capture("rig_side_grips")
	container.queue_free()
	await process_frame

func verify_imported_skin(character: Node3D, sample: String) -> PackedVector3Array:
	if DisplayServer.get_name() == "headless": return PackedVector3Array()
	var mesh: MeshInstance3D = character.find_child("JanitorMesh", true, false)
	var baked := mesh.bake_mesh_from_current_skeleton_pose()
	check(baked != null, "Rendered skin readback exists")
	if not baked: return PackedVector3Array()
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var actual: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ratios := PackedFloat32Array()
	for i in range(0, indices.size(), 3):
		for edge in 3:
			var a := indices[i + edge]
			var b := indices[i + (edge + 1) % 3]
			var length := original[a].distance_to(original[b])
			if length > .001: ratios.append(actual[a].distance_to(actual[b]) / length)
	ratios.sort()
	var p99 := ratios[int((ratios.size() - 1) * .99)]
	check(p99 < 2.5, "Imported rendered skin retains broad stretch limit: " + sample)
	check(ratios[-1] < 4.0, "Imported rendered skin has no localized spike: " + sample)
	print("IMPORTED SKIN ", sample, " p99=", p99, " max=", ratios[-1])
	return actual
