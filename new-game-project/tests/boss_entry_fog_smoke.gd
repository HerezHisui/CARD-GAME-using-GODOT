extends SceneTree

var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var director = game.run_director
	if not director.has_method("debug_enter_boss"):
		check(false, "debug boss entry exists")
	else:
		director.new_run()
		# Direct invocation without unlocked debug UI must not replace an encounter.
		check(not director.debug_enter_boss(3), "boss shortcut gated by unlocked debug screen")
		for floor_number in [1, 2, 3]:
			director.screen = "debug"
			game.presentation.automated_choice = 0
			check(director.debug_enter_boss(floor_number), "debug enters floor boss")
			check(director.floor_number == floor_number and director.battle_active, "floor and battle initialized")
			check(director.rooms[director.current].kind == "boss", "current route node is boss")
			check(game.player_hp > 0 and not director.collection.is_empty(), "player state valid")
			check(game.encounter_kind == "boss" and game.enemy_hp > 0, "real boss encounter initialized")
			check(is_instance_valid(game.final_boss) == (floor_number == 3), "Warden only at floor three")
			check(game.boss_fog.active, "boss arena fog active")
			game.presentation.cancel_coin()
			director.screen = ""
			director.show_map()
			await process_frame
			var canvas = director.content.get_node("RouteRow/MapScroll/Canvas")
			check(canvas.has_node("BossFog"), "map gets fog at boss node")
			canvas.resized.emit()
			var boss_button: Control
			for child in canvas.get_children():
				if child.get_meta("room", -1) == director.current: boss_button = child
			check(boss_button.position == canvas.point(director.rooms[director.current]) - boss_button.size / 2, "fog does not disrupt room positions")
			director.cleared.append(director.current)
			director.refresh_map_fog()
			check(not canvas.has_node("BossFog"), "clearing node removes map fog")
			director.close_modal()
			var environment: Environment = game.get_node("WorldEnvironment").environment
			check(environment.fog_enabled, "arena gets depth fog")
			game.boss_fog_enabled = false
			game.boss_fog.refresh()
			check(not environment.fog_enabled, "fog setting restores original environment")
			game.boss_fog_enabled = true
			game.boss_fog.refresh()
			game.clear_battle()
			check(not game.boss_fog.active and not environment.fog_enabled, "leaving boss cleans fog")
			director.battle_active = false
			director.screen = ""
			await process_frame
	game.queue_free()
	await process_frame
	print("Boss entry/fog smoke: %d failures" % failures)
	quit(1 if failures else 0)
