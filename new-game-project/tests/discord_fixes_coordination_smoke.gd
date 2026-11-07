# Covers: Coordinated Response only links allies in lanes directly next to each other (Discord fix, item 1).
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.turn = 1
	game.energy_cap = 10
	game.preparedness = 10
	game._set_phase(game.Phase.PLAYER_PLAY)

func unit(id: String, lane: int) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":id, "name":id.capitalize(), "type":"response", "element":"evac", "cost":1, "attack":2,
		"health":4})
	card.place_on_slot(game._response_slots()[lane])
	return card

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.discard()
	director.new_run()
	game.set_process(false)
	# Lanes 0, 1 and 3 are filled. Lane 2 is empty.
	fixture()
	var left = unit("left", 0)
	var center = unit("center", 1)
	var far = unit("far", 3)
	check(game.plans.coordination_targets(center) == [center, left], "center links only to the ally next to it")
	check(game.plans.coordination_targets(far) == [far], "an empty lane on the left breaks the link")
	check(game.plans.coordination_targets(left) == [left, center], "lane 0 links to lane 1")
	# Through the real tactic pick and board click.
	game.plans.unlocked.assign(["coordinate"])
	game.plans.tokens = 1
	director.begin_tactic("coordinate")
	game.board_input.click_card(center)
	check(game.plans.armed.get("kind", "") == "coordinate", "the click arms Coordinated Response")
	game.plans.apply_combat()
	check(left.plan_attack_bonus == 1 and center.plan_attack_bonus == 1, "adjacent allies gain +1 attack")
	check(far.plan_attack_bonus == 0, "the ally past the empty lane gains nothing")
	game.plans.finish_combat()
	# All four lanes filled: both sides link.
	fixture()
	var a = unit("a", 0)
	var b = unit("b", 1)
	var c = unit("c", 2)
	var d = unit("d", 3)
	check(game.plans.coordination_targets(b) == [b, a, c], "a full row links both neighbours")
	check(d not in game.plans.coordination_targets(b), "two lanes away never links")
	if failures > 0:
		push_error("discord_fixes_coordination_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: discord_fixes_coordination_smoke (%d checks)" % checks)
	quit(0)
