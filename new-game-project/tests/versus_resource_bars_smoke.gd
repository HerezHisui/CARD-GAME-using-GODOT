extends SceneTree

var checks := 0
var failures := 0
var game: Node
var rendered := false
var output := "C:/Users/0stef/Downloads/drrills-batch3-energy-checks"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	if not rendered: return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, "Capture " + name)

func run() -> void:
	rendered = "--render-energy" in OS.get_cmdline_user_args()
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var director: Node = game.run_director
	director.persistence.enabled = false
	var old_prep_style: StyleBox = director.prep.get_theme_stylebox("fill")
	var old_threat_style: StyleBox = director.threat.get_theme_stylebox("fill")
	game.clear_battle()
	director.battle_active = true
	director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_waiting = true
	game.disaster_seat_view = true
	game.energy_cap = 5
	game.preparedness = 2
	game.tension_cap = 7
	game.tension = 4
	for disaster: bool in [false, true]:
		game._set_phase(game.Phase.ENEMY if disaster else game.Phase.PLAYER_PLAY)
		director.privacy_serial = game.encounter_serial
		director.privacy_last = "disaster" if disaster else "prep"
		director.privacy_screen.hide()
		await frames()
		var hud: Node = director.versus_hud
		expect(hud.get("energy_bar") is ProgressBar and hud.get("tension_bar") is ProgressBar,
			"Both hot-seat resources use continuous bars")
		if not hud.get("energy_bar") is ProgressBar:
			quit(1)
			return
		expect(hud.energy_bar.value == 2 and hud.energy_bar.max_value == 5, "Hot-seat Energy fill uses current/max")
		expect(hud.tension_bar.value == 4 and hud.tension_bar.max_value == 7, "Hot-seat Tension fill uses current/max")
		expect(hud.energy_bar.get_node("Value").text == "2 / 5", "Energy bar shows current/max text")
		expect(hud.tension_bar.get_node("Value").text == "4 / 7", "Tension bar shows current/max text")
		expect(hud.energy_plate.tooltip_text == "Energy: 2 / 5", "Energy tooltip kept available")
		expect(hud.tension_plate.tooltip_text == "Tension: 4 / 7", "Tension tooltip kept available")
		expect(hud.energy_bar.get_theme_stylebox("fill") == game._player_hp_ui.get_node("Bar").get_theme_stylebox("fill"),
			"Energy bar reuses HP fill style")
		await capture("hotseat-disaster" if disaster else "hotseat-preparedness")
	game.preparedness = 0
	game.tension = 0
	await frames()
	expect(director.versus_hud.energy_bar.value == 0 and director.versus_hud.tension_bar.value == 0,
		"Empty resource bars have no fill")
	game.energy_cap = 0
	game.tension_cap = 0
	await frames()
	expect(director.versus_hud.energy_bar.get_node("Value").text == "0 / 0", "Zero-cap text stays accurate")
	game.encounter_kind = "battle"
	await frames()
	expect(not director.versus_hud.energy_plate.visible and not director.versus_hud.tension_plate.visible,
		"Versus bars hide in singleplayer")
	expect(director.prep.get_theme_stylebox("fill") == old_prep_style
		and director.threat.get_theme_stylebox("fill") == old_threat_style, "Singleplayer gauge styles unchanged")
	expect(is_equal_approx(director.prep.get_parent().modulate.a, 1.0), "Singleplayer gauge remains visible")
	director.battle_active = false
	director.modal.hide()
	await check_clients()
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: versus_resource_bars_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func check_clients() -> void:
	var session: Node = load("res://scripts/lan_session.gd").new()
	root.add_child(session)
	for seat in ["preparedness", "disaster"]:
		var panel: Control = load("res://scripts/lan_prep_panel.gd").new() if seat == "preparedness" \
			else load("res://scripts/lan_client_panel.gd").new()
		root.add_child(panel)
		var board: Node = load("res://scripts/lan_board_3d.gd").new()
		root.add_child(board)
		board.setup(game, game.run_director, session, panel, seat)
		var view := make_view(seat)
		session.view_received.emit(view)
		await frames(20)
		var mine: int = 2 if seat == "preparedness" else 4
		var cap: int = 5 if seat == "preparedness" else 7
		expect(board.resource_meter.value.text == "%d / %d" % [mine, cap], "LAN own bar shows current/max")
		expect(is_equal_approx(board.resource_meter.bar.value / board.resource_meter.bar.max_value, float(mine) / cap),
			"LAN own fill ratio correct")
		expect(board.foe_meter.value.text == ("4 / 7" if seat == "preparedness" else "2 / 5"),
			"LAN opponent bar shows current/max")
		expect(not board.resource_plate.tooltip_text.is_empty(), "LAN resource tooltip remains available")
		expect(board.foe_plate.box.tooltip_text == "Hand 3   Deck 9", "Opponent HP hand/deck tooltip preserved")
		await capture("lan-" + seat)
		view.sides.response.resource = 0
		view.sides.disaster.resource = 0
		view.energy = 0
		session.view_received.emit(view)
		await frames()
		expect(board.resource_meter.bar.value == 0 and board.foe_meter.bar.value == 0,
			"Both LAN bars update to empty")
		view.sides.response.resource_cap = 0
		view.sides.disaster.resource_cap = 0
		view.energy_cap = 0
		session.view_received.emit(view)
		await frames()
		expect(board.resource_meter.value.text == "0 / 0" and board.foe_meter.value.text == "0 / 0",
			"LAN zero caps remain accurate")
		board.queue_free()
		panel.queue_free()
		await frames()
	session.queue_free()
	await frames()

func make_view(seat: String) -> Dictionary:
	return {"side": seat, "round": 2, "phase": "play", "turn_side": seat,
		"is_prep_turn": seat == "preparedness", "is_disaster_turn": seat == "disaster",
		"sides": {"response": {"hp": 14, "max_hp": 20, "barrier": 0, "resource": 2, "resource_cap": 5},
			"disaster": {"hp": 17, "max_hp": 20, "barrier": 0, "resource": 4, "resource_cap": 7}},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {}, "hints": [], "prep_hand": [], "disaster_hand": [], "energy": 2, "energy_cap": 5,
		"plan_tokens": 0, "tactics": [], "counts": {"response_hand": 3, "response_draw": 9,
			"disaster_hand": 3, "disaster_draw": 9, "disaster_evolution": 6}, "actions_left": 4}
