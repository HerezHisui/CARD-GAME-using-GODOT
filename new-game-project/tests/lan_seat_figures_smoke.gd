extends SceneTree
## Covers: the Versus figure pick over LAN (docs/notes/versus-deck-pick-plan.md section 4).
## The client sends "figure" on its deck message, the host checks it (lan_title._on_deck_requested),
## both views carry "foe_figure" (lan_view.gd), the client board stands the host's figure (lan_board_3d._reveal).
## The hook is on only with game.seat_figures_override = {"versus": true}; SEAT_FIGURES_VERSUS stays false.
## Rendered frames: run without --headless and add "-- --shot=<folder>" to save 1280x720 pictures.

const LanSession = preload("res://scripts/lan_session.gd")
const LanTitle = preload("res://scripts/lan_title.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const Decks = preload("res://scripts/versus_decks.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
const StandeeFigure = preload("res://scripts/standee_figure.gd")
const PrepFigure = preload("res://scripts/preparedness_figure.gd")

const TEST_PORT := 24811
const MAX_FRAMES := 600
const SAVE_PATH := "user://test_lan_seat_figures_smoke.cfg"
const HOOK := {"versus": true}

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node # the director's lan_title
var other: Node # the plain LanSession on the other side
var other_joined := false
var other_events: Array = [] # [kind, data] from the host
var other_decks: Array = [] # host side: decks the client sent
var other_joins: Array = []
var shot_folder := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot_folder = arg.trim_prefix("--shot=")
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	Decks.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	await frames(3)
	check_protocol()
	# The client boards first, on a clean table, like tests/preparedness_figure_smoke.gd.
	for seat in ["disaster", "preparedness"]:
		for foe: Variant in ["robin", "nobody", null]:
			await check_client_board(seat, foe)
	make_other()
	director.show_title()
	director.ensure_lan_title()
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_lan_seat_figures_smoke_lan.cfg"
	await check_host()
	await check_client_page()
	lan.session.close()
	other.close()
	game.seat_figures_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_seat_figures_smoke (%d checks)" % checks)
	quit(0)


# ---------------------------------------------------------------- helpers
func frames(count: int) -> void:
	for i in count: await process_frame


func wait_until(check: Callable) -> bool:
	for i in MAX_FRAMES:
		if check.call(): return true
		await process_frame
	return check.call()


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.joined_host.connect(func() -> void: other_joined = true)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.deck_requested.connect(func(deck) -> void: other_decks.append(deck))
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))


func has_kind(kind: String) -> bool:
	for event in other_events:
		if event[0] == kind: return true
	return false


func click(control: Control) -> void:
	expect(control != null, "click: the control exists")
	if control == null: return
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = center
		event.global_position = center
		root.push_input(event, true)
		await process_frame


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree(): return node
	return null


func find_in(parent: Node, node_name: String) -> Node:
	return parent.find_child(node_name, true, false) if is_instance_valid(parent) else null


func coin_screen_ready() -> bool:
	return director.screen == "coin" and game.presentation.blocking and not game.presentation.coin_busy \
		and is_instance_valid(game.presentation.coin_root) and game.presentation.choice_buttons.size() == 2


## A legal Preparedness deck that differs from the preset (one main card swapped).
func custom_prep() -> Dictionary:
	var deck: Dictionary = Decks.preset(Decks.SIDE_PREP).duplicate(true)
	for id: String in Decks.pool(Decks.SIDE_PREP).base:
		if deck.main.count(id) == 0:
			deck.main[0] = id
			break
	deck.tactics = ["brace", "supply", "flank"]
	return deck


## The figure's box in world space.
func figure_box(figure: Node3D) -> AABB:
	var mesh := figure.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return mesh.global_transform * mesh.get_aabb()


func slot_box(slot: Node3D) -> AABB:
	return AABB(slot.global_position - Vector3(0.6, 0.2, 0.8), Vector3(1.2, 0.4, 1.6))


## Standees anywhere under the game that are not on their way out.
func standees() -> int:
	var count := 0
	for node in game.find_children("*", "Node3D", true, false):
		if node.get_script() == StandeeFigure and not node.is_queued_for_deletion(): count += 1
	return count


func capture(shot_name: String) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1280, 720)
	# This fixture never leaves the title screen. In a real match lan_title closes it; here it hides for the shot.
	var title_shown: bool = director.root.visible
	director.root.visible = false
	await frames(8)
	var path := shot_folder.path_join(shot_name + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, shot_name + " frame saved")
	director.root.visible = title_shown


# ---------------------------------------------------------------- checks
## 1. The flag is off in the repo: PROTOCOL and the build string are today's.
func check_protocol() -> void:
	expect(not VersusMatch.SEAT_FIGURES_VERSUS, "Protocol: SEAT_FIGURES_VERSUS is false")
	expect(LanSession.PROTOCOL == 6, "Protocol: PROTOCOL is 6")
	expect(LanSession.build_string().begins_with("6|") and LanSession.build_string().ends_with("|crosswind1|lists1"),
		"Protocol: the build string is today's, got " + LanSession.build_string())


## A small LAN view with one card per row (tests/preparedness_figure_smoke.gd make_view).
func make_view(seat: String) -> Dictionary:
	var unit := {"definition": {"name": "Ally", "type": "response", "element": "evac", "cost": 0, "attack": 1,
		"health": 3}, "runtime": {"max_health": 3, "statuses": {}, "modifiers": []}}
	var foe := {"definition": {"name": "Threat", "type": "disaster", "element": "fire", "cost": 0, "attack": 1,
		"health": 3, "tension_cost": 0}, "runtime": {"max_health": 3, "statuses": {}, "modifiers": []}}
	var view := {
		"round": 2, "first_side": "response", "coin": {},
		"sides": {
			"response": {"hp": 14, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 17, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["a", "", "", ""], "disaster": ["x", "", "", ""]},
		"cards": {"a": unit, "x": foe}, "hints": [],
	}
	if seat == "preparedness":
		view.side = "preparedness"
		view.is_prep_turn = true
		view.prep_hand = []
		view.counts = {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8}
		view.energy = 3
		view.energy_cap = 5
		view.plan_tokens = 0
		view.armed = ""
		view.tactics = []
	else:
		view.is_disaster_turn = true
		view.disaster_hand = []
		view.counts = {"response_hand": 5, "response_draw": 9, "disaster_draw": 8}
		view.actions_left = 3
	return view


## 8. The client board at a seat with "foe_figure" robin, "nobody" or no key (null).
func check_client_board(seat: String, foe: Variant) -> void:
	var label := "Client %s, foe %s: " % [seat, str(foe)]
	var session: Node = LanSession.new()
	root.add_child(session)
	var panel: Control = LanPrepPanel.new() if seat == "preparedness" else LanClientPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board: Node = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, director, session, panel, seat, cover)
	var view := make_view(seat)
	if foe != null: view["foe_figure"] = foe
	session.view_received.emit(view)
	await frames(3)
	expect(board.shown, label + "the table is shown")
	var robin: bool = foe == "robin"
	if seat == "disaster":
		var figure: Node3D = board.prep_figure
		expect(is_instance_valid(figure) and figure.visible, label + "a figure is shown across the table")
		var want: Script = StandeeFigure if robin else PrepFigure
		expect(is_instance_valid(figure) and figure.get_script() == want, label + "the figure is the right kind")
		check_place(figure, label)
		expect(board.foe_standee == null, label + "no far standee at the Disaster seat")
		if robin: await capture("lan-client-disaster-1280")
	else:
		var mesh: Node3D = board.janitor.find_child("JanitorMesh", true, false)
		expect(mesh.visible != robin, label + "the client's Janitor mesh shows only without a standee")
		expect(board.prep_figure == null, label + "no extra figure at the player's own seat")
		if robin:
			var standee: Node3D = board.foe_standee
			expect(is_instance_valid(standee) and standee.visible, label + "the standee shows")
			var anchor: Node3D = game.find_child("OpponentPosition", true, false)
			var flat := Vector2(standee.global_position.x - anchor.global_position.x,
				standee.global_position.z - anchor.global_position.z)
			expect(flat.length() < 0.01, label + "the standee stands on OpponentPosition")
			await capture("lan-client-prep-1280")
		else:
			expect(board.foe_standee == null, label + "no standee")
	await frames(120)
	expect(board.shown, label + "120 frames")
	board.queue_free()
	cover.queue_free()
	session.queue_free()
	await frames(3)
	expect(standees() == 0, label + "queue_free leaves no standee")


func check_place(figure: Node3D, label: String) -> void:
	if not is_instance_valid(figure): return
	var seat: Node3D = game.find_child("PlayerPosition", true, false)
	var flat := Vector2(figure.global_position.x - seat.global_position.x,
		figure.global_position.z - seat.global_position.z)
	expect(flat.length() < 0.01, label + "the figure stands on PlayerPosition")
	expect(figure.find_children("*", "CollisionObject3D", true, false).is_empty(), label + "no collision")
	var box := figure_box(figure)
	for slot: Node3D in game._threat_slots() + game._response_slots():
		expect(not box.intersects(slot_box(slot)), label + "the figure is clear of " + slot.name)


## Host, join, Start match, call the coin, and give Player 1 (the host) host_side. Waits for the deck step.
func host_to_deck_step(name: String, host_side: String) -> Node:
	director.show_title()
	lan.show_host()
	other_joined = false
	other_events.clear()
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, name + ": the client starts joining")
	expect(await wait_until(func() -> bool: return other_joined and lan.room_connected()), name + ": joined")
	lan.start_match()
	var versus: Node = director.versus_match
	versus.deck_choice = true
	versus.automated_deck = "standard"
	versus.automated_figure = "warden"
	expect(await wait_until(coin_screen_ready), name + ": the coin screen shows")
	await frames(3)
	await click(game.presentation.choice_buttons[0])
	expect(await wait_until(func() -> bool: return versus.prematch_active), name + ": the side pick starts")
	var other_side := Decks.SIDE_PREP if host_side == Decks.SIDE_DISASTER else Decks.SIDE_DISASTER
	versus.choose_side(host_side if versus.coin_winner == 1 else other_side)
	if not await wait_until(func() -> bool: return has_kind("deck_step")):
		expect(false, name + ": the client hears the deck step")
		return null
	return versus


## 7. The host reads "figure" from the client's deck. Hook on, the client on Preparedness.
func check_host() -> void:
	var name := "Host"
	game.seat_figures_override = HOOK
	var versus: Node = await host_to_deck_step(name, Decks.SIDE_DISASTER)
	if versus == null: return
	expect(versus.player2_side == Decks.SIDE_PREP, name + ": the client plays Preparedness")
	other.request_deck({"figure": "robin"})
	expect(await wait_until(func() -> bool: return has_kind("seat")), name + ": the client is seated")
	expect(versus.seat_figures == {"p1": "warden", "p2": "robin"}, name + ": p1 warden, p2 robin")
	expect(versus.custom_decks.is_empty() and not has_kind("deck_note"), name + ": Standard, no deck note")
	versus.automated_deck = ""
	versus.automated_figure = ""
	check_views(versus)
	# The same handler through its signal, the step opened again. Bad figures give "" and today's deck.
	var side: String = versus.player2_side
	for bad: Variant in [5, "nobody", "guardian", "r".repeat(5000)]:
		var label := name + ", figure %s: " % str(bad).left(12)
		var notes: int = await send_again(versus, {"figure": bad})
		expect(versus.seat_figures.p2 == "" and versus.deck_ready[side], label + "p2 is empty, the side is ready")
		expect(versus.custom_decks.is_empty() and notes == 0, label + "Standard, no deck note")
	var custom := custom_prep()
	expect(Decks.validate(side, custom).ok, "Fixture: the custom Preparedness deck is legal")
	var with_figure := custom.duplicate(true)
	with_figure["figure"] = "robin"
	var notes: int = await send_again(versus, with_figure)
	expect(versus.seat_figures.p2 == "robin" and notes == 0, name + ", custom: robin kept, no deck note")
	expect(versus.custom_decks.get(side, {}).get("main", []) == custom.main, name + ", custom: the custom deck")
	expect(not versus.custom_decks.get(side, {}).has("figure"), name + ", custom: no figure key in the deck")
	# Hook off: the key is not read. The deck is handled as today (an unknown shape is refused).
	game.seat_figures_override = null
	notes = await send_again(versus, {"figure": "robin"})
	expect(versus.seat_figures.p2 == "" and versus.deck_ready[side], name + ", hook off: p2 is not set")
	expect(versus.custom_decks.is_empty() and notes == 1, name + ", hook off: Standard with a deck note, as today")
	game.seat_figures_override = HOOK
	other.close()
	expect(await wait_until(func() -> bool: return not versus.running), name + ": the match ended")
	expect(versus.seat_figures == {"p1": "", "p2": ""}, name + ": the match end empties the figures")
	lan.session.close()
	game.seat_figures_override = null
	await frames(5)


## Opens the deck step again and hands the host this deck through deck_requested. Returns the deck notes sent.
func send_again(versus: Node, deck: Dictionary) -> int:
	versus.start_deck_step()
	versus.seat_figures.p2 = ""
	other_events.clear()
	lan.session.deck_requested.emit(deck)
	versus.end_deck_step()
	await frames(10)
	var notes := 0
	for event in other_events:
		if event[0] == "deck_note": notes += 1
	return notes


## 1 and 12. Both views carry "foe_figure" only when the hook is on; with it erased they are today's views.
func check_views(versus: Node) -> void:
	game.seat_figures_override = null
	var off_disaster: Dictionary = LanView.build(game)
	var off_prep: Dictionary = LanView.build(game, "preparedness")
	expect(not off_disaster.has("foe_figure") and not off_prep.has("foe_figure"), "Views, hook off: no foe_figure")
	game.seat_figures_override = HOOK
	var on_disaster: Dictionary = LanView.build(game)
	var on_prep: Dictionary = LanView.build(game, "preparedness")
	expect(on_disaster.get("foe_figure") == "warden" and on_prep.get("foe_figure") == "warden",
		"Views, hook on: both carry the host's figure")
	on_disaster.erase("foe_figure")
	on_prep.erase("foe_figure")
	expect(on_disaster == off_disaster and on_prep == off_prep, "Views, hook on: the rest equals the hook-off view")


## The client's deck page with the hook on: the leader row, a real click, "figure" on the deck message.
func check_client_page() -> void:
	var name := "Client page"
	game.seat_figures_override = HOOK
	expect(other.host_game(TEST_PORT) == OK, name + ": the other side hosts")
	other_joins.clear()
	other_decks.clear()
	director.show_title()
	lan.show_join()
	director.content.find_child("IpEdit", true, false).text = "127.0.0.1"
	await frames(3)
	await click(find_button("Connect"))
	expect(await wait_until(func() -> bool: return other_joins.size() == 1), name + ": the host accepted the client")
	expect(await wait_until(func() -> bool: return lan.room == "client"), name + ": waits in the room")
	other.send_event("start", {})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), name + ": panel after start")
	other.lobby = true
	other.send_event("coin", {"stage": "choosing", "call": 0, "result": 1, "winner": 1})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.coin_page)), name + ": the coin page shows")
	other.send_event("deck_step", {"side": "preparedness"})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.deck_page)), name + ": the deck page shows")
	await frames(5)
	var row: Node = find_in(lan.deck_page, "FigureRow")
	var names: Array = row.get_children().map(func(button): return button.text) if row else []
	expect(names == ["SAM", "ROBIN", "SAGE", "KAI"], name + ": four leaders in order, got %s" % str(names))
	var standard: Button = find_in(lan.deck_page, "StandardButton")
	expect(standard.disabled and find_in(lan.deck_page, "CustomizeButton").disabled, name + ": deck buttons off")
	await click(standard)
	await frames(10)
	expect(other_decks.is_empty(), name + ": an off Standard sends nothing")
	await click(find_in(row, "Figure_robin"))
	expect(not standard.disabled, name + ": a pick turns the deck buttons on")
	await click(standard)
	expect(await wait_until(func() -> bool: return other_decks.size() == 1), name + ": a real click sends the deck")
	expect(other_decks[0] is Dictionary and other_decks[0] == {"figure": "robin"}, name + ": Standard with robin")
	other.lobby = false
	other.seat_client("preparedness")
	other.send_event("seat", {"side": "preparedness"})
	expect(await wait_until(func() -> bool: return lan.client_side == "preparedness"), name + ": seated")
	lan.back_to_title()
	other.close()
	game.seat_figures_override = null
	await frames(5)
