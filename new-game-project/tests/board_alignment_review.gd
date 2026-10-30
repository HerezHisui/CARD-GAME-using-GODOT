extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/0stef/Downloads/board-alignment-" + label + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This optional visual fixture requires a rendering display")
		quit(2)
		return
	root.size = Vector2i(1280, 800)
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.run_director.persistence.enabled = false
	game.run_director.set_process(false)
	game.run_director.root.hide()
	game.get_node("HUD").hide()
	game.show()
	game.set_process(false)
	await process_frame
	for pair in [["desk", game.DESK_VIEW], ["overhead", game.BOARD_VIEW]]:
		game._apply_view(pair[1])
		await capture(str(pair[0]) + "-empty")
	game.show_drop_targets(true)
	for slot in game.get_node("Slots").get_children():
		slot.visible = true
		slot.material_override = game._drop_target_material
	for pair in [["desk", game.DESK_VIEW], ["overhead", game.BOARD_VIEW]]:
		game._apply_view(pair[1])
		await capture(str(pair[0]) + "-highlights")
	for slot in game.get_node("Slots").get_children():
		slot.hide()
		var card = load("res://scenes/card_3d.tscn").instantiate()
		game.add_child(card)
		card.preview_only = true
		card.setup({"id":"fire_drill", "name":"Fire Drill", "type":"response", "element":"evac",
			"cost":1, "attack":1, "health":3})
		card.place_on_slot(slot)
	await create_timer(0.7).timeout
	for pair in [["desk", game.DESK_VIEW], ["overhead", game.BOARD_VIEW]]:
		game._apply_view(pair[1])
		await capture(str(pair[0]) + "-cards")
	game.queue_free()
	await process_frame
	print("PASS: captured empty board, highlights and deployed cards in desk/overhead views")
	quit()
