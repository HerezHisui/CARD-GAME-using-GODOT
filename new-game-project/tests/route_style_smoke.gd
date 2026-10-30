extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func run() -> void:
	root.size = Vector2i(1280, 800)
	var game := preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var director = game.run_director
	director.persistence.enabled = false
	director.new_run()
	for dimensions in [Vector2i(1280, 800), Vector2i(1440, 900)]:
		root.size = dimensions
		director.close_modal()
		director.show_map()
		await create_timer(.65).timeout
		var canvas: Control = director.content.get_node("RouteRow/MapScroll/Canvas")
		var positions := {}
		for button in canvas.get_children():
			if not button.has_meta("room"): continue
			var id := int(button.get_meta("room"))
			var room: Dictionary = director.rooms[id]
			check(button.icon != null, "Every room has an imported semantic icon")
			check(button.disabled == not director.reachable(id), "Route access rules remain authoritative")
			check(canvas.get_rect().size.x >= button.position.x + button.size.x, "Nodes fit canvas width")
			positions[id] = button.position.y
		for room in director.rooms:
			for next in room.links:
				check(positions[next] < positions[room.id], "Routes progress vertically toward boss")
		check(director.content.get_node("RouteRow/Dossier/DossierText/RoomLegend").get_child_count() == 7,
			"Legend covers all seven encounter kinds")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("C:/Users/0stef/Downloads/map-review-%d.png" % dimensions.x)
	game.queue_free()
	await process_frame
	print("ROUTE STYLE: %d failures" % failures)
	quit(1 if failures else 0)
