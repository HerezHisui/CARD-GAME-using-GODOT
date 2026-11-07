extends SceneTree
const Chart = preload("res://scripts/type_chart_panel.gd")
const EngineChart = preload("res://scripts/battle_engine.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var panel := Chart.new()
	root.add_child(panel)
	await process_frame
	var relations := panel.relations()
	expect(relations.size() == 16, "all sixteen non-neutral relationships appear")
	for attacker in EngineChart.TYPE_CHART:
		for target in EngineChart.TYPE_CHART[attacker]:
			var matching := relations.filter(func(r): return r.attacker == attacker and r.target == target)
			expect(matching.size() == 1, attacker + " to " + target + " appears once")
			expect(matching[0].multiplier == EngineChart.TYPE_CHART[attacker][target], "engine value used")
	var counters := {
		"evac": ["Earthquake", "Typhoon", "Typhoon", "Earthquake"],
		"douse": ["Flood", "Fire", "Fire", "Flood"],
		"clearance": ["Typhoon", "Flood", "Flood", "Typhoon"],
		"brace": ["Fire", "Earthquake", "Earthquake", "Fire"],
		"earthquake": ["Brace", "Evac", "Evac", "Brace"],
		"fire": ["Douse", "Brace", "Brace", "Douse"],
		"flood": ["Clearance", "Douse", "Douse", "Clearance"],
		"typhoon": ["Evac", "Clearance", "Clearance", "Evac"]}
	for element in counters:
		var c: Array = counters[element]
		var expected := "%s takes 2x from %s, 0.5x from %s.\n%s deals 2x to %s, 0.5x to %s." % [
			element.capitalize(), c[0], c[1], element.capitalize(), c[2], c[3]]
		expect(panel.sentence(element) == expected, element + " incoming and outgoing sentence")
		panel.pills[element].mouse_entered.emit()
		expect(panel.description.text == expected, "hover updates visible sentence")
		for other in panel.pills:
			expect(is_equal_approx(panel.pills[other].modulate.a, 1.0 if element == other else 0.35),
				"hover dims only other pills")
		panel.pills[element].mouse_exited.emit()
		expect(panel.description.text == "Hover an element", "leaving resets hover")
	panel.pills.fire.pressed.emit()
	panel.pills.fire.mouse_exited.emit()
	expect(panel.hovered == "fire", "click pins selection after pointer leaves")
	panel.pills.fire.pressed.emit()
	expect(panel.hovered.is_empty(), "second click clears selection")
	panel.toggle.pressed.emit()
	expect(panel.collapsed and not panel.body.visible, "collapse hides body")
	expect(panel.size.y == panel.HEADER_HEIGHT, "collapsed panel keeps only header")
	expect(Rect2(Vector2.ZERO, panel.size).encloses(panel.toggle.get_rect()), "toggle fits collapsed header")
	panel.toggle.pressed.emit()
	expect(not panel.collapsed and panel.body.visible, "expand restores body")
	for element in panel.pills:
		var pill: Button = panel.pills[element]
		expect(Rect2(Vector2.ZERO, panel.ring.size).encloses(pill.get_rect()), "pill stays inside ring")
		for other in panel.pills:
			if other == element: continue
			expect(not pill.get_rect().intersects(panel.pills[other].get_rect()), "pills do not overlap")
	panel.queue_free()
	await process_frame
	if "--hud" in OS.get_cmdline_user_args() or "--render" in OS.get_cmdline_user_args():
		await check_hud()
	print("%s: ui_type_chart %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func check_hud() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var director: Node = game.run_director
	director.persistence.enabled = false
	game.presentation.automated_choice = 0
	director.new_run()
	director.visit(0)
	var started := Time.get_ticks_msec()
	while game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]:
		if Time.get_ticks_msec() - started > 12000: break
		await process_frame
	if game.phase == game.Phase.PLAYER_DRAW:
		game._on_draw_button_pressed()
		if game.phase == game.Phase.PLAYER_DRAW and not game.deck.is_empty():
			game.complete_draw_choice(game.deck[0])
	expect(game.can_player_act(), "main-game encounter reaches playable phase")
	await create_timer(2.0).timeout
	var chart: Control = game.get_node("HUD/Root/TypeChartPanel")
	for target: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await resize(target)
		chart.set_collapsed(false)
		await frames()
		check_layout(game, chart, "main " + str(target))
		await capture("main-%dx%d-expanded" % [target.x, target.y])
		await pointer(chart.pills.fire.get_global_rect().get_center())
		expect(chart.hovered == "fire", "real pointer motion selects Fire")
		expect(chart.pills.evac.modulate.a < 1.0, "real pointer dims another element")
		await capture("main-%dx%d-fire" % [target.x, target.y])
		await click(chart.toggle.get_global_rect().get_center())
		expect(chart.collapsed, "real collapse-button click hides body")
		check_layout(game, chart, "collapsed main")
		await capture("main-%dx%d-collapsed" % [target.x, target.y])
		game.set_view(game.View.DESK)
		await click(game._view_forward_btn.get_global_rect().get_center())
		expect(game.view_mode == game.View.BOARD, "moved W button still opens overhead")
		await click(game._view_back_btn.get_global_rect().get_center())
		expect(game.view_mode == game.View.DESK, "moved S button still returns to desk")
		await key(KEY_S)
		expect(game.view_mode == game.View.WIDE, "S key still opens wide view")
		await key(KEY_W)
		expect(game.view_mode == game.View.DESK, "W key still returns to desk")
		await click(chart.toggle.get_global_rect().get_center())
		expect(not chart.collapsed, "real expand-button click restores body")
	game.clear_battle()
	var match_node: Node = load("res://scripts/versus_match.gd").new()
	director.add_child(match_node)
	match_node.setup(director)
	director.versus_match = match_node
	match_node.automated_side = "preparedness"
	match_node.automated_deck = "standard"
	director.start_versus_match()
	started = Time.get_ticks_msec()
	while game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]:
		if Time.get_ticks_msec() - started > 12000: break
		if director.privacy_screen.visible: director._hide_privacy_screen()
		if director.screen == "evolution_offer" and game.evolution_choice.pending():
			game.evolution_choice._choose(game.evolution_choice.offer[0].definition)
		await process_frame
	expect(game.encounter_kind == "versus" and match_node.running, "local Versus match starts")
	expect(game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY], "Versus reaches opening turn")
	director._hide_privacy_screen()
	await create_timer(2.0).timeout
	for target: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await resize(target)
		await frames()
		check_layout(game, chart, "versus " + str(target))
		expect(chart.body.visible or chart.forced_compact, "Versus starts expanded unless space forces collapse")
		await capture("versus-%dx%d-default" % [target.x, target.y])
		chart.set_collapsed(true)
		check_layout(game, chart, "collapsed versus")
		await capture("versus-%dx%d-collapsed" % [target.x, target.y])
		chart.set_collapsed(false)
		await capture("versus-%dx%d-expanded" % [target.x, target.y])
	game.clear_battle()
	game.queue_free()
	await process_frame

func frames(count: int = 6) -> void:
	for i in count: await process_frame

func resize(target: Vector2i) -> void:
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
	root.size = target
	await frames(12)
	expect(root.size == target, "window retains requested size")
	print("LAYOUT physical=", root.size, " logical=", root.get_visible_rect().size)

func pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await frames(2)

func click(point: Vector2) -> void:
	await pointer(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await frames(2)

func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)

func check_layout(game: Node, chart: Control, label: String) -> void:
	var rect := chart.get_global_rect()
	var top_bar: Control = game.get_node("HUD/TopBar")
	expect(chart.is_visible_in_tree(), label + " chart visible")
	expect(rect.position.y >= top_bar.get_global_rect().end.y + 6, label + " below top bar")
	var hud: Control = game.get_node("HUD/Root")
	var right_edge := maxf(game._player_hp_ui.get_global_rect().end.x, game._enemy_hp_ui.get_global_rect().end.x)
	expect(is_equal_approx(rect.end.x, right_edge), label + " right aligned with the HP plates")
	expect(is_equal_approx(root.get_visible_rect().size.x - rect.end.x, 16.0), label + " 16 px from the right edge")
	var lowest := 0.0
	for plate: Control in [game._player_hp_ui, game._enemy_hp_ui,
			hud.get_node_or_null("VersusEnergy"), hud.get_node_or_null("VersusTension"),
			game.run_director.threat.get_parent() if game.encounter_kind != "versus" else null]:
		if is_instance_valid(plate) and plate.is_visible_in_tree():
			var plate_rect := plate.get_global_rect()
			expect(not rect.intersects(plate_rect), label + " avoids " + plate.name)
			if plate_rect.end.x > rect.position.x and plate_rect.position.x < rect.end.x:
				lowest = maxf(lowest, plate_rect.end.y)
	expect(is_equal_approx(rect.position.y, lowest + 8.0), label + " sits 8 px under the lowest plate")
	for name in ["DeckDrawButton", "EndTurnButton", "PlansBox", "GraveyardButton"]:
		var corner: Control = hud.get_node(name)
		if corner.is_visible_in_tree():
			expect(not rect.intersects(corner.get_global_rect()), label + " avoids " + name)
	expect(game._view_forward_btn.position == Vector2(24, 88), label + " W stays at its original place")
	expect(game._view_back_btn.position == Vector2(72, 88), label + " S stays at its original place")
	expect(rect.end.y < root.get_visible_rect().size.y * 0.72, label + " chart stays above hand region")
	var outline := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
	for card in game.get_hand_cards():
		var polygon: PackedVector2Array = game.hand_card_polygon(card, false)
		expect(Geometry2D.intersect_polygons(outline, polygon).is_empty(), label + " avoids actual hand card")
	print("CHART ", label, " rect=", rect, " collapsed=", chart.collapsed)

func capture(label: String) -> void:
	if "--render" not in OS.get_cmdline_user_args(): return
	if DisplayServer.get_name() == "headless": return
	await frames(4)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../docs/notes/type-chart-shots")
	DirAccess.make_dir_recursive_absolute(folder)
	var image := root.get_texture().get_image()
	expect(image.get_size() == root.size, "screenshot matches requested dimensions")
	expect(image.save_png(folder.path_join(label + ".png")) == OK, "screenshot saved: " + label)
