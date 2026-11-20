extends SceneTree
## dn-title: the game is called Drill Night everywhere a player sees the title.
## Saves stay in the old user folder, so no player loses a save or a setting.

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	# The window title comes from the project name.
	expect(ProjectSettings.get_setting("application/config/name") == "Drill Night", "name: Drill Night")
	expect(OS.get_user_data_dir().ends_with("/Godot/app_userdata/Midnight DRRills"), "saves: the old user folder")
	await check_title_screen()
	await check_menu_header()
	print("DN TITLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


# The title screen shows the text title DRILL and NIGHT, not the old logo picture.
func check_title_screen() -> void:
	var title: Control = load("res://scenes/ui/ui_title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	var big: Label = title.get_node("%Title")
	var small: Label = title.get_node("%Subtitle")
	expect(big.text == "DRILL" and big.is_visible_in_tree(), "title: DRILL shows")
	expect(small.text == "NIGHT" and small.is_visible_in_tree(), "title: NIGHT shows")
	expect(title.get_node("%GlowLabel").text == "DRILL", "title: glow copy says DRILL")
	expect(title.get_node("%SubGlowLabel").text == "NIGHT", "title: glow copy says NIGHT")
	expect(title.find_child("GameLogo", true, false) == null, "title: no logo picture")
	title.queue_free()
	await process_frame


# The in-game menu header says DRILL NIGHT.
func check_menu_header() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var director = game.run_director
	director.persistence.enabled = false
	director.new_run()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	paused = false
	director.show_menu()
	await process_frame
	var labels: Array = director.content.find_children("*", "Label", true, false).map(func(label: Label) -> String:
		return label.text)
	expect(director.screen == "menu", "menu: opens")
	expect("DRILL NIGHT" in labels, "menu: header DRILL NIGHT")
	expect(not ("MIDNIGHT DRRILLS" in labels), "menu: old name gone")
	paused = false
	game.queue_free()
	await process_frame
