extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.preparedness = 1
	var utility = game.Card3DScene.instantiate()
	game.add_child(utility)
	utility.setup({"name": "Test utility", "type": "response", "utility": true, "cost": 1})
	var unit = game.Card3DScene.instantiate()
	game.add_child(unit)
	unit.setup({"name": "Test unit", "type": "response", "cost": 2, "attack": 3, "health": 2})
	check(game.best_disruption_target([utility, unit], false) == unit, "seal ranks mixed hands")
	check(game.best_disruption_target([unit, utility], true) == utility, "tax ranks utility cards")
	check(game.best_disruption_target([utility], false) == utility, "utility-only hands are valid")
	for style in [StyleBoxEmpty.new(), StyleBoxFlat.new(), StyleBoxTexture.new()]:
		var button := Button.new()
		root.add_child(button)
		button.add_theme_stylebox_override("normal", style)
		game.presentation.button_feedback(button)
		for event in ["mouse_entered", "button_down", "button_up", "mouse_exited"]:
			button.emit_signal(event)
			await create_timer(0.16).timeout
		check(button.get_theme_stylebox("normal").get_class() == style.get_class(),
			"feedback preserves the button's style type")
		button.queue_free()
	game.queue_free()
	await process_frame
	if failures == 0: print("PASS: utility disruption targeting and empty/flat/texture button feedback")
	quit(1 if failures else 0)
