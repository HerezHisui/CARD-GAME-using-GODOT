extends "res://tests/oct18_card_logic_smoke.gd"

func effect_consistency() -> void:
	fixture()
	var ally := unit("response", 0)
	var other := unit("response", 1)
	game.resolve_single_strike(ally, other, true)
	check(other.card_data.health == 8 and game.enemy_hp == 40, "Response cannot attack Response")
	var a: String = director.card_rules({"element":"evac", "modifier":"piercing"})
	var b: String = director.card_rules({"element":"evac", "modifiers":["piercing"]})
	check(a == b, "primary and added modifiers share effect text")
	check("Starts with 2 Strength" in director.card_rules({"element":"brace", "strength":2}),
		"starting Strength is described")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	effect_consistency()
	game.clear_battle()
	print("OCT18 BALANCE: %d failures" % failures)
	quit(1 if failures else 0)
