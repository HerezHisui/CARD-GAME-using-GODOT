extends SceneTree
# Visual room-only captures for comparison with the supplied asset reference.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit()
		return
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.run_director.set_process(false)
	game.run_director.root.hide()
	game.get_node("HUD/Root").hide()
	game.visible = true
	game.get_node("Sketchfab_Scene").hide()
	game.get_viewport().use_taa = RenderingServer.get_current_rendering_method() == "forward_plus"
	for mode in [game.View.WIDE, game.View.DESK]:
		game._apply_view(game.view_settings(mode))
		await create_timer(1.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/artifacts/lighting_%s_%d.png" % [RenderingServer.get_current_rendering_method(), mode])
	quit()
