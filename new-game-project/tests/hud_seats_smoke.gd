extends SceneTree
## One Versus HUD for every seat: host hot-seat (P1 and P2 Preparedness, the Disaster seat), the LAN host as the
## Disaster, and the LAN client (lan_board_3d.gd) as Preparedness and as the Disaster.
## At 1280x720 and 1920x1080: HP, Energy and Tension bars have one height and one caption font, Preparedness bars
## use the gold HP fill and Disaster bars the crimson fill, and no two HUD pieces overlap.
## Headless it checks the layout. With a window it also saves a frame per case to SHOT_DIR (when set).

class RecordingLink:
	extends "res://scripts/lan_session.gd"
	func request_action(_msg) -> void:
		pass

const View = preload("res://scripts/lan_view.gd")
const VersusHud = preload("res://scripts/versus_hud.gd")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

var failures := 0
var checks := 0
var game: Node
var director: Node
var shots := OS.get_environment("SHOT_DIR")


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int = 5) -> void:
	for i in count: await process_frame


func run() -> void:
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	game.presentation.automated_choice = 0
	await frames()
	for size in SIZES:
		root.size = size
		await check_host(size, "preparedness", false, "host P1 prep")
		await check_host(size, "disaster", false, "host P2 prep")
		await check_host(size, "disaster", true, "host P1 disaster seat")
		await check_lan_host_disaster(size)
		await check_client(size, "preparedness")
		await check_client(size, "disaster")
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: hud_seats_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)


func versus_state(p1_side: String) -> void:
	game.clear_battle()
	game.set_seats("local", "local")
	# The first call starts the match. Later calls do nothing (it is running), so the state is set here.
	director.start_versus_match()
	game.encounter_kind = "versus"
	director.battle_active = true
	director.screen = ""
	director.modal.visible = false
	director.privacy_screen.hide()
	game.versus_hand_hidden = false
	director.versus_match.player1_side = p1_side
	director.versus_match.player2_side = "disaster" if p1_side == "preparedness" else "preparedness"
	game.turn = 2
	game.energy_cap = 3
	game.preparedness = 2
	game.tension = 4


# Hot-seat on the host. seat_on: the Disaster seat is up (its turn), so its controls replace Plans and Graveyard.
func check_host(size: Vector2i, p1_side: String, seat_on: bool, label: String) -> void:
	versus_state(p1_side)
	game._set_phase(game.Phase.ENEMY if seat_on else game.Phase.PLAYER_PLAY)
	game.disaster_seat_on = seat_on
	await frames(8)
	var hud: Node = director.versus_hud
	var name := "%s %dx%d" % [label, size.x, size.y]
	var prep_tag := "P1" if p1_side == "preparedness" else "P2"
	expect(game._player_hp_ui.get_node("HealthMark").text == prep_tag, name + ": Preparedness tag " + prep_tag)
	check_meters(name, [game._player_hp_ui, hud.energy_plate], [game._enemy_hp_ui, hud.tension_plate])
	var pieces: Array = [game._player_hp_ui, game._enemy_hp_ui, hud.energy_plate, hud.tension_plate,
		game._end_turn_btn, game.get_node("HUD/Root/DeckDrawButton"), hud.turn_plate,
		director.plans_button, director.graveyard_button, hud.disaster_plans, hud.disaster_grave]
	check_no_overlap(name, pieces)
	await capture(label.replace(" ", "-"), size)
	game.disaster_seat_on = false
	director.battle_active = false
	await frames()


# LAN host that plays the Disaster: its plate sits on the left, the same widgets.
func check_lan_host_disaster(size: Vector2i) -> void:
	versus_state("disaster")
	game.set_seats("remote", "local")
	game._set_phase(game.Phase.ENEMY)
	await frames(8)
	var hud: Node = director.versus_hud
	var name := "LAN host disaster %dx%d" % [size.x, size.y]
	expect(game._enemy_hp_ui.get_global_rect().position.x < game._player_hp_ui.get_global_rect().position.x,
		name + ": the Disaster plate is on the left")
	check_meters(name, [game._player_hp_ui, hud.energy_plate], [game._enemy_hp_ui, hud.tension_plate])
	check_no_overlap(name, [game._player_hp_ui, game._enemy_hp_ui, hud.energy_plate, hud.tension_plate,
		game._end_turn_btn, game.get_node("HUD/Root/DeckDrawButton"), hud.turn_plate,
		director.plans_button, director.graveyard_button, hud.disaster_plans, hud.disaster_grave])
	await capture("lan-host-disaster", size)
	game.set_seats("local", "local")
	director.battle_active = false
	await frames()


# The LAN client table. The client is Player 2 and builds the host's pieces.
func check_client(size: Vector2i, seat: String) -> void:
	game.clear_battle()
	director.battle_active = true
	director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	if seat == "preparedness": game.set_seats("remote", "local")
	else: game.set_seats("local", "remote")
	game.turn = 2
	game.energy_cap = 3
	game.preparedness = 2
	game.tension = 4
	game._set_phase(game.Phase.PLAYER_PLAY)
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = (preload("res://scripts/lan_prep_panel.gd").new() if seat == "preparedness"
		else preload("res://scripts/lan_client_panel.gd").new())
	root.add_child(panel)
	if seat == "preparedness": link.attach_prep_panel(panel)
	else: link.attach_panel(panel)
	var board: Node = preload("res://scripts/lan_board_3d.gd").new()
	root.add_child(board)
	board.setup(game, director, link, panel, seat)
	link.push_view(View.build_prep(game) if seat == "preparedness" else View.build(game, seat))
	await frames(15)
	var name := "client %s %dx%d" % [seat, size.x, size.y]
	expect(board.me_plate.mark.text == "P2" and board.foe_plate.mark.text == "P1", name + ": P2 / P1 tags")
	var own: Array = [board.me_plate.box, board.resource_plate]
	var foe: Array = [board.foe_plate.box, board.foe_resource]
	if seat == "preparedness": check_meters(name, own, foe)
	else: check_meters(name, foe, own)
	expect(board.me_plate.box.get_global_rect().position.x < board.foe_plate.box.get_global_rect().position.x,
		name + ": own plate on the left")
	check_no_overlap(name, [board.me_plate.box, board.foe_plate.box, board.resource_plate, board.foe_resource,
		board.end_button, board.draw_button, board.turn_plate, board.plans_toggle, board.prep_grave,
		board.disaster_plans, board.disaster_grave])
	if seat == "preparedness":
		expect(not board.plans_open(), name + ": the Plans screen starts closed")
		board.plans_toggle.pressed.emit()
		await frames(3)
		expect(board.plans_open() and board.tactic_box.get_child_count() > 0,
			name + ": the Plans icon opens the Plans screen")
		# p2-plans: the host's modal screen now, so it covers the HUD like the host's. It must fit the window.
		expect(root.get_visible_rect().encloses(board.plans_panel.get_global_rect()),
			name + ": the Plans screen fits the window")
		board.close_plans()
	await capture("client-" + seat, size)
	board.free()
	panel.free()
	link.free()
	game.set_seats("local", "local")
	await frames()


# prep and disaster: [HP widget, resource widget] of each role.
func check_meters(name: String, prep: Array, disaster: Array) -> void:
	var meters: Array = prep + disaster
	var height: float = meters[0].get_node("Bar").get_global_rect().size.y
	var font: Font = meters[0].get_node("Caption").get_theme_font("font")
	var font_size: int = meters[0].get_node("Caption").get_theme_font_size("font_size")
	for meter: Control in meters:
		expect(meter.visible, name + ": %s shows" % meter.name)
		expect(is_equal_approx(meter.get_node("Bar").get_global_rect().size.y, height),
			name + ": %s bar height %.1f = %.1f" % [meter.name, meter.get_node("Bar").get_global_rect().size.y, height])
		var caption: Label = meter.get_node("Caption")
		expect(caption.get_theme_font("font") == font and caption.get_theme_font_size("font_size") == font_size,
			name + ": %s caption font" % meter.name)
	var gold: StyleBox = game._player_hp_ui.get_node("Bar").get_theme_stylebox("fill")
	var crimson: Color = VersusHud.disaster_fill().bg_color
	for meter: Control in prep:
		expect(meter.get_node("Bar").get_theme_stylebox("fill") == gold, name + ": %s gold fill" % meter.name)
	for meter: Control in disaster:
		var fill: StyleBox = meter.get_node("Bar").get_theme_stylebox("fill")
		expect(fill is StyleBoxFlat and fill.bg_color == crimson, name + ": %s crimson fill" % meter.name)


# Every visible piece pairwise: no overlap, and on screen.
func check_no_overlap(name: String, pieces: Array) -> void:
	var shown: Array = pieces.filter(func(piece) -> bool:
		return is_instance_valid(piece) and piece.is_visible_in_tree())
	# The UI is laid out in the stretched base size, so the visible rect is the screen.
	var screen := root.get_visible_rect()
	for i in shown.size():
		var a: Rect2 = shown[i].get_global_rect()
		expect(screen.encloses(a), name + ": %s on screen %s" % [shown[i].name, a])
		for j in range(i + 1, shown.size()):
			var b: Rect2 = shown[j].get_global_rect()
			expect(not a.grow(-1.0).intersects(b.grow(-1.0)),
				name + ": %s %s clear of %s %s" % [shown[i].name, a, shown[j].name, b])


func capture(label: String, size: Vector2i) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless": return
	await create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/hud-%s-%d.png" % [shots, label, size.x])
