extends SceneTree
## Floors read as hours of the night: map label, floor banner, title save label and loss panel.
const Director = preload("res://scripts/run_director.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func texts(node: Node, out: Array) -> Array:
	if node is Label: out.append(node.text)
	for child in node.get_children(): texts(child, out)
	return out

func frame(name: String) -> void:
	# Frames only in a real window; headless runs skip them.
	if DisplayServer.get_name() == "headless": return
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("C:/Users/0stef/Downloads/drrills-frames")
		root.get_texture().get_image().save_png("C:/Users/0stef/Downloads/drrills-frames/dn-hours-%s-%d.png"
			% [name, size.x])
	root.size = Vector2i(1280, 800)

func run() -> void:
	check(Director.floor_hour(1) == "12 AM", "Floor 1 is 12 AM")
	check(Director.floor_hour(2) == "2 AM", "Floor 2 is 2 AM")
	check(Director.floor_hour(3) == "4 AM", "Floor 3 is 4 AM")
	check(Director.floor_hour(0) == "" and Director.floor_hour(4) == "", "Other floors have no hour")

	root.size = Vector2i(1280, 800)
	var game := preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var director = game.run_director
	director.new_run()
	for i in 30: await process_frame

	# The real floor step: floor 1 -> floor 2 shows the banner and the map.
	director.next_floor()
	check(director.floor_number == 2, "next_floor moves to floor 2")
	var banner: Array = texts(game.presentation.banner_node, []) if is_instance_valid(game.presentation.banner_node) \
		else []
	check("FLOOR 2 · 2 AM" in banner, "Floor banner title reads the hour: %s" % [banner])
	check("2 AM. The halls have changed." in banner, "Floor banner subtitle reads the hour: %s" % [banner])
	for i in 60: await process_frame
	var floor_label: Label = director.content.get_node("RouteRow/Dossier/DossierText/FloorLabel")
	check(floor_label.text == "FLOOR 2 · 2 AM", "Map label reads the hour: %s" % floor_label.text)
	await frame("map")

	# The title save label reads the saved floor's hour.
	check(director.persistence.checkpoint(), "The floor 2 map is saved")
	director.show_title()
	for i in 10: await process_frame
	var save_label: Label = director.content.find_child("SaveLabel", true, false)
	check(save_label != null and save_label.text == "UNFINISHED RUN · FLOOR 2 · 2 AM",
		"Title save label reads the hour: %s" % (save_label.text if save_label else "missing"))
	director.continue_saved_run()
	for i in 30: await process_frame

	# A lost fight on floor 2: the loss panel invites another try and keeps the card count.
	check(director.floor_number == 2, "The saved run continues on floor 2")
	director.encounter = "battle"
	director.battle_active = true
	director.battle_finished(false)
	for i in 10: await process_frame
	var panel: Array = texts(director.content, [])
	check("THE NIGHT WON THIS TIME" in panel, "Loss title follows the feeling: %s" % [panel])
	var subtitle := "Made it to 2 AM · %d cards in deck. Try again." % director.collection.size()
	check(subtitle in panel, "Loss subtitle reads the hour and keeps the card count: %s" % [panel])
	check(not "TRAPPED AFTER MIDNIGHT" in panel, "The old loss title is gone")
	await frame("loss")

	director.persistence.discard()
	game.queue_free()
	await process_frame
	print("DN NIGHT HOURS: %d failures" % failures)
	quit(1 if failures else 0)
