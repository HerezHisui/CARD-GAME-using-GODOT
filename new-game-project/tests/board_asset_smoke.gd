extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1280, 800)
	var board := load("res://scenes/school_drill_board.tscn").instantiate() as Node3D
	root.add_child(board)
	var meshes := board.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "Imported board contains a mesh")
	for mesh: MeshInstance3D in meshes:
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		check(absf(bounds.size.x - 5.3) < 0.01, "Board width fits card slots")
		check(absf(bounds.size.z - 3.2) < 0.01, "Board depth fits card slots")
		check(bounds.position.y > 1.004, "Board underside clears the table top")
		check(absf(bounds.end.y - 1.032) < 0.002, "Board surface stays below deployed cards")
		check(absf(bounds.get_center().x) < 0.01 and absf(bounds.get_center().z) < 0.01,
			"Board is centered on the existing slots")
	var image := preload("res://scripts/card_3d.gd")._card_back().get_image()
	var gold: Color = preload("res://scripts/ui_theme.gd").GOLD
	for y in image.get_height():
		for x in image.get_width():
			var border := ((y == 6 or y == 173) and x >= 6 and x <= 125)
			border = border or ((x == 6 or x == 125) and y >= 6 and y <= 173)
			var expected := gold if border else Color.BLACK
			var pixel := image.get_pixel(x, y)
			check(absf(pixel.r - expected.r) < 0.005 and absf(pixel.g - expected.g) < 0.005
				and absf(pixel.b - expected.b) < 0.005, "Card back is black with only a gold border")
	var game := load("res://scenes/game_3d.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	var table := game.find_child("GameTable", true, false) as MeshInstance3D
	var table_bounds: AABB = table.global_transform * table.get_aabb()
	var board_mesh := game.get_node("Playmat").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var board_bounds: AABB = board_mesh.global_transform * board_mesh.get_aabb()
	check(board_bounds.position.y > table_bounds.end.y + 0.004, "Whole board clears actual table")
	check(table_bounds.size.x > board_bounds.size.x, "Table supports enlarged board width")
	for slot: Node3D in game.get_node("Slots").get_children():
		check(absf(slot.global_position.y - 1.016) < 0.0001,
			"Highlight sits just above the measured recess floor")
		check(slot.mesh is PlaneMesh, "Drop highlight has no raised box face")
	var expected_columns := [-1.59583, -0.52629, 0.53, 1.6006]
	for slot: MeshInstance3D in game.get_node("Slots").get_children():
		var column := int(str(slot.name).right(1)) - 1
		var expected_z := -0.7136 if str(slot.name).begins_with("Threat") else 0.7136
		check(absf(slot.position.x - expected_columns[column]) < 0.001
			and absf(slot.position.z - expected_z) < 0.001, "Slot centers match imported painted recesses")
	game.show_drop_targets(true)
	for slot: MeshInstance3D in game._response_slots():
		check(slot.visible and slot.material_override == game._drop_target_material,
			"Drop highlight uses the same slot mesh and transform")
	game.show_drop_targets(false)
	var card = load("res://scenes/card_3d.tscn").instantiate()
	game.add_child(card)
	card.preview_only = true
	card.setup({"id":"fit", "name":"Fit", "type":"response", "element":"evac",
		"cost":1, "attack":1, "health":1})
	var target: Node3D = game._response_slots()[1]
	card.place_on_slot(target)
	await create_timer(0.6).timeout
	check(card.global_position.distance_to(target.global_position + Vector3(0, 0.008, 0)) < 0.001,
		"Deployed card rests in the recess instead of above the frame")
	var card_bottom: float = card.global_position.y - 0.01 * game.BOARD_SCALE
	check(card_bottom > 1.0133 and card_bottom < 1.02, "Card body clears measured recessed surface")
	for view in [game.DESK_VIEW, game.BOARD_VIEW]:
		game._apply_view(view)
		var surface := Vector3(card.global_position.x, 1.0133, card.global_position.z)
		var face: Vector3 = card.art_sprite.global_position
		var separation: float = game.camera.unproject_position(surface).distance_to(
			game.camera.unproject_position(face))
		check(separation < 3.0, "Perspective displacement from the recessed center stays below 3 pixels")
	card.queue_free()
	var draw: Button = game.get_node("HUD/Root/DeckDrawButton")
	game.presentation.remind_to_draw(true)
	var reminder: Control = draw.get_node("DrawReminder")
	check(reminder.get_index() > draw.get_node("DrawIcon").get_index(),
		"Draw reminder overlays the opaque icon area")
	check(reminder.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Reminder preserves button input")
	check(draw.tooltip_text.is_empty() and game.get_node("HUD/Root/GraveyardButton").tooltip_text.is_empty(),
		"Redundant HUD hover instructions are removed")
	game.presentation.remind_to_draw(false)
	var director = game.run_director
	director.persistence.enabled = false
	for dimensions in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var gauge: Control = director.prep.get_parent()
		var grave: Control = game.get_node("HUD/Root/GraveyardButton")
		check(absf(gauge.get_global_rect().end.y - (director.root.size.y - 16)) < 1,
			"Preparedness sits at bottom safe margin")
		check(grave.get_global_rect().position.x >= gauge.get_global_rect().end.x + 8,
			"Graveyard sits to the right of Preparedness")
		check(absf(grave.get_global_rect().end.y - gauge.get_global_rect().end.y) < 1,
			"Preparedness and Graveyard bottoms align")
		check(gauge.get_node("Title").text == "PREPAREDNESS", "Gauge title is preserved")
		check(gauge.has_node("Value") and director.prep.size.y == 8, "Compact gauge keeps separate value and bar")
		check(not game.get_node("HUD/Root/EnergyPips").visible, "Old pips are hidden")
	game.queue_free()
	await process_frame
	board.free()
	if failures == 0: print("PASS: imported board bounds and plain black/gold card backs")
	quit(1 if failures else 0)
