extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)
func finish() -> void:
	if failures == 0: print("PASS: Response-only graveyard, compact HUD, current editor previews and legacy save compatibility")
	quit(1 if failures else 0)
func run() -> void:
	root.size = Vector2i(1440, 900)
	if Engine.is_editor_hint():
		var preview = load("res://scenes/card_3d.tscn").instantiate()
		root.add_child(preview)
		await process_frame
		check(preview.preview_only and preview.card_data.name == "Quick Dash", "editor displays the current card instead of a blank box")
		check(preview.art_sprite.texture != null and not preview.is_processing(), "editor preview has a face without running game logic")
		preview.queue_free()
		await process_frame
		await create_timer(2.0).timeout
		print("Editor card preview checked.")
		finish()
		return
	var scene = load("res://scenes/game_3d.tscn").instantiate()
	check(not scene.has_node("Table") and not scene.has_node("SpookyLight"), "obsolete table and light are absent from the saved scene")
	for name in ["OrbGauge_2", "OrbGauge_3", "DeckShadow", "DrawCaption", "EnemyDeckPlaque"]:
		check(not scene.has_node("HUD/Root/" + name), "unused HUD widget removed: " + name)
	check(scene.get_node("HUD/Root/EndTurnButton").text == "End turn", "saved HUD uses the current controls")
	root.add_child(scene)
	current_scene = scene
	var director = scene.run_director
	director.persistence.discard()
	director.new_run()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	scene.set_process(false)
	scene.clear_battle()
	scene._set_phase(scene.Phase.PLAYER_PLAY)
	var definition := {"name":"Lost ally", "type":"response", "element":"evac", "cost":1, "attack":2, "health":3}
	var ally = scene.Card3DScene.instantiate()
	scene.add_child(ally)
	ally.setup(definition)
	ally.place_on_slot(scene._response_slots()[0])
	scene.record_graveyard(ally, "Destroyed")
	definition.type = "disaster"
	definition.name = "Lost threat"
	var threat = scene.Card3DScene.instantiate()
	scene.add_child(threat)
	threat.setup(definition)
	threat.place_on_slot(scene._threat_slots()[0])
	scene.record_graveyard(threat, "Sacrificed")
	scene.record_enemy_spell({"name":"Enemy spell"})
	check(scene.player_graveyard.size() == 1 and scene.graveyard_serial == 1, "only Response entries allocate graveyard snapshots")
	check(scene.battle_log.any(func(line): return "Lost threat" in line) and scene.battle_log.any(func(line): return "Enemy spell" in line), "enemy events remain in the combat log")
	director.show_graveyard()
	check(director.viewed_cards.size() == 1, "graveyard shows only Response entries")
	check(not director.content.find_children("*", "Button", true, false).any(func(button): return "Janitor" in button.text), "no enemy graveyard tab")
	check(director.threat.get_parent().get_child_count() == 2, "tension retains its label and bar without hidden pile counts")
	director.close_modal()
	check(director.persistence.checkpoint(), "current checkpoint saves")
	var snapshot = director.persistence.read_save()
	check(not snapshot.game.has("enemy_graveyard"), "new saves omit enemy graveyard history")
	snapshot.game.enemy_graveyard = [{"name":"Legacy enemy"}]
	var file = FileAccess.open(director.persistence.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	check(director.persistence.resume() and scene.player_graveyard.size() == 1, "older enemy graveyard data is ignored while Response history survives")
	await create_timer(0.3).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/artifacts/oct16_cleanup.png")
	director.persistence.discard()
	finish()
