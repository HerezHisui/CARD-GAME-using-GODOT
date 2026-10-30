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
	director.new_run()
	game.clear_battle()
	director.battle_active = true
	director.encounter = "battle"
	director.current = 0
	director.screen = ""
	director.modal.hide()
	paused = false
	game.effects_enabled = true
	game.phase = game.Phase.PLAYER_PLAY
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":"vfx_test", "name":"VFX test", "type":"response", "element":"evac",
		"cost":1, "attack":1, "health":20})
	card.place_on_slot(game._response_slots()[0])
	card.add_status("burn", 4)
	check(game.vfx._cards.has(card.get_instance_id()), "real add_status starts persistent visuals")
	var before: int = card.card_data.health
	card.status_upkeep()
	check(card.card_data.health == before - 4 and card.statuses.burn == 2, "particle hooks preserve status damage/decay")
	check(game.vfx._cards[card.get_instance_id()].stacks.burn == 2, "upkeep updates visual stacks immediately")
	card.cleanse()
	check(not game.vfx._cards.has(card.get_instance_id()), "cleanse removes persistent visuals immediately")
	card.add_status("poison", 2)
	director.battle_finished(true)
	check(game.vfx._cards.is_empty() and game.vfx._bursts.is_empty(), "normal victory clears all battle particles")
	game.vfx.sync_status(card)
	check(game.vfx._cards.is_empty(), "status refresh cannot restart particles outside battle")
	director.battle_active = true
	game.boss_fog.set_active(true)
	game.vfx.sync_status(card)
	director.battle_finished(false)
	check(game.vfx._cards.is_empty() and not game.boss_fog.active, "defeat clears status particles and boss fog")
	game.queue_free()
	await process_frame
	print("VFX gameplay integration smoke: %d failures" % failures)
	quit(1 if failures else 0)
