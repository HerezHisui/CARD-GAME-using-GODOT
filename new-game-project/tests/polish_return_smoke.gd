extends SceneTree

var checks := 0
var failures := 0
var samples: Array = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + text)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 900)
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(0.8).timeout
	game.clear_battle()
	game.run_director.modal.hide()
	game.run_director.screen = ""
	game.run_director.battle_active = true
	game.set_view(game.View.DESK)
	if game.camera_tween: game.camera_tween.kill()
	game._apply_view(game.DESK_VIEW)
	for mode in ["versus", "battle"]:
		game.encounter_kind = mode
		for disaster in [false, true]:
			for struck in [false, true]:
				await check_return(game, mode, disaster, struck)
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("RETURN SAMPLES: ", JSON.stringify(samples))
	print("%s: polish_return_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func attack(card: Node, target: Vector3, hit: Array) -> void:
	await card.attack_lunge(target)
	hit[0] = true

func check_return(game: Node, mode: String, disaster: bool, struck: bool) -> void:
	var slot: Node3D = (game._threat_slots() if disaster else game._response_slots())[1]
	var card: Node3D = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"name": "Quick Dash", "id": "probe", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 9})
	card.in_hand = false
	card.current_slot = slot
	card._set_overlay(false)
	var home := slot.global_position + Vector3(0, 0.02, 0)
	card.global_position = home
	card.scale = Vector3.ONE * game.BOARD_SCALE
	var yaw := PI if disaster else 0.0
	card.rotation = Vector3(0, yaw, 0)
	var hit := [false]
	attack(card, home + Vector3(0, 0, 2.4 if disaster else -2.4), hit)
	await create_timer(0.1).timeout
	var windup: float = card.rotation.x
	expect(absf(windup) > 0.01, "wind-up hit feedback retains its pitch")
	while not hit[0]: await process_frame
	var impact_pitch: float = card.rotation.x
	var hit_roll := 0.0
	if struck:
		card.take_damage(1)
		await create_timer(0.03).timeout
		hit_roll = absf(card.rotation.z)
		await create_timer(0.03).timeout
		hit_roll = maxf(hit_roll, absf(card.rotation.z))
		expect(hit_roll > 0.01, "damage hit feedback retains its wobble before returning")
		await create_timer(0.15).timeout
	else:
		await create_timer(0.04).timeout
	var return_pitch: float = card.rotation.x
	var return_roll: float = card.rotation.z
	# FLAT_CHECK
	expect(absf(impact_pitch) < 0.00001, "return begins flat after the strike")
	expect(absf(return_pitch) < 0.00001 and absf(return_roll) < 0.00001, "card returns flat and straight")
	# END_FLAT_CHECK
	if mode == "versus" and not disaster and struck and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "C:/Users/0stef/Downloads/drrills-polish2-2026-11-06/part2-return-after.png"
		expect(root.get_texture().get_image().save_png(path) == OK, "return frame saved")
	await create_timer(0.4).timeout
	expect(card.global_position.distance_to(home) < 0.001, "same home position after return")
	expect(absf(card.rotation.x) < 0.00001 and absf(card.rotation.z) < 0.00001, "final card is flat")
	expect(absf(wrapf(card.rotation.y - yaw, -PI, PI)) < 0.001, "owning seat yaw is unchanged")
	expect(card.card_data.health == (8 if struck else 9), "damage amount is unchanged")
	expect(card.art_sprite.visible and is_equal_approx(card.art_sprite.modulate.a, 1.0), "face is never hidden")
	samples.append({"mode": mode, "disaster": disaster, "windup": windup,
		"struck": struck, "impact": impact_pitch, "return": return_pitch, "roll": return_roll})
	card.queue_free()
	await process_frame
