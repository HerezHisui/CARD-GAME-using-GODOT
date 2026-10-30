extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func run() -> void:
	check(FileAccess.file_exists("res://scenes/startup.tscn"), "Application has a studio splash scene")
	var scene := load("res://scenes/ui/ui_title.tscn") as PackedScene
	var title := scene.instantiate()
	root.add_child(title)
	await process_frame
	check(not title.get_node("%Title").visible, "Rendered title text is replaced")
	check(not title.get_node("%Subtitle").visible, "Rendered subtitle text is replaced")
	check(not title.get_node("%TitleGlow").visible, "Old title glow text is hidden")
	check(title.get_node_or_null("TitleBox/GameLogo") != null, "Supplied game logo appears on title")
	title.queue_free()
	await process_frame
	print("STARTUP LOGOS: %d failures" % failures)
	quit(1 if failures else 0)
