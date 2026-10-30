extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func run() -> void:
	check(FileAccess.file_exists("res://scripts/janitor_character.gd"), "Skinned opponent controller exists")
	var rig := load("res://assets/characters/janitor/janitor_rigged.glb") as PackedScene
	check(rig != null, "Rigged GLB imports")
	var model := rig.instantiate()
	root.add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(skeleton != null, "Character uses a real skeleton")
	if skeleton:
		check(skeleton.get_bone_count() >= 60, "Torso, arms, fingers and cloth have bones")
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(player != null and player.has_animation("card_play"), "Card-playing animation imports")
	var mesh := model.find_child("JanitorMesh", true, false) as MeshInstance3D
	check(mesh != null and mesh.skin != null, "Mesh has imported skin binds")
	if mesh:
		var arrays := mesh.mesh.surface_get_arrays(0)
		check(not arrays[Mesh.ARRAY_WEIGHTS].is_empty(), "Mesh contains real vertex skin weights")
	model.queue_free()
	await process_frame
	if FileAccess.file_exists("res://scripts/janitor_character.gd"):
		await controller_checks()
	print("JANITOR: %d failures" % failures)
	quit(1 if failures else 0)

func controller_checks() -> void:
	var character: Node3D = load("res://scripts/janitor_character.gd").new()
	root.add_child(character)
	character.set_encounter(true)
	character.set_hand_count(6)
	check(character.holding.get_child_count() == 6, "Held cards match actual hand count")
	for card in character.holding.get_children():
		check(card.global_position.y > character.holding.global_position.y + .12,
			"Card fan levitates above the supporting palm")
		check(card.mesh.material.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"Both card sides display only the hidden back")
	character.play_card({"id": "test_threat"}, Vector3(1, 1, 0))
	check(character.played_id == "test_threat", "Gesture carries actual chosen card ID")
	check(character.playing.get_child_count() == 1, "Selected card attaches to playing hand")
	check(character.playing.bone_name == character.holding.bone_name,
		"Selected card leaves the floating fan, not the directing hand")
	var center: Vector3 = character.playing.get_child(0).global_position
	character.release_card()
	check(character.released_origin.distance_to(center) < .00001, "Handoff preserves selected card center")
	check(character.playing.get_child_count() == 0, "Release removes held selected visual")
	character.play_card({"id": "replacement"})
	character.play_card({"id": "latest"})
	check(character.playing.get_child_count() == 1, "Repeated plays cannot accumulate stale visuals")
	var cloth: Node = character.cloth
	cloth.running = false
	cloth.reset_simulation()
	cloth.disturb()
	var max_stretch := 1.0
	for i in 1200: cloth.simulate(1.0 / 120.0)
	for edge in cloth.pairs.size():
		var pair: Vector2i = cloth.pairs[edge]
		max_stretch = maxf(max_stretch, cloth.points[pair.x].distance_to(cloth.points[pair.y]) / cloth.lengths[edge])
	check(max_stretch < 1.08, "Cloth structural/shear/bend constraints limit edge stretch")
	for i in cloth.points.size():
		check(cloth.points[i].is_finite(), "Cloth remains finite")
		check(cloth.points[i].distance_to(cloth.rest[i]) < 0.091, "Cloth stays inside safety tether")
		if i in cloth.pins:
			check(cloth.points[i].distance_to(cloth.rest[i]) < 0.001, "Waist cloth remains pinned")
		else:
			check(cloth.points[i].y >= .018, "Cloth remains above floor collision plane")
			var relative: Vector3 = (cloth.points[i] - Vector3(0, .44, -.06)) / Vector3(.15, .47, .115)
			check(relative.length_squared() >= .999, "Cloth stays outside body collision proxy")
	check(cloth.points[39].distance_to(cloth.rest[39]) > 0.00001, "Physics moves unpinned cloth")
	character.set_encounter(false)
	check(character.playing.get_child_count() == 0 and character.action_time < 0,
		"Battle interruption clears gesture and selected card")
	check(cloth.points == cloth.rest, "Encounter transition resets cloth")
	character.set_hand_count(0)
	character.set_encounter(true)
	character.warden_pattern()
	check(character.action_kind == "warden" and character.playing.get_child_count() == 0,
		"Scripted Warden gestures do not fabricate cards")
	character.queue_free()
	await process_frame
	print("CLOTH constraint stretch max=", max_stretch)
