extends SceneTree

class RecordingLink:
	extends "res://scripts/lan_session.gd"
	var sent: Array = []
	func request_action(msg) -> void:
		sent.append(msg.duplicate(true))

const View = preload("res://scripts/lan_view.gd")
const Actions = preload("res://scripts/lan_actions.gd")
const Decks = preload("res://scripts/versus_decks.gd")
var game: Node
var checks := 0
var failures := 0
var rendered := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int = 8) -> void:
	for i in count: await process_frame

func buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button: result.append(node)
	for child in node.get_children(): result += buttons(child)
	return result

func click(button: Button) -> void:
	await click_point(button.get_global_rect().get_center())

func click_point(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func capture(label: String) -> void:
	if not rendered: return
	await frames(30)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../docs/notes/lanA-part3")
	DirAccess.make_dir_recursive_absolute(folder)
	expect(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"Rendered " + label)

func run() -> void:
	rendered = "--render-lan-evolution-ui" in OS.get_cmdline_user_args()
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	var versus: Node = preload("res://scripts/versus_match.gd").new()
	game.run_director.add_child(versus)
	game.run_director.versus_match = versus
	versus.setup(game.run_director)
	fixture()
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	expect(panel.has_method("setup_evolutions"), "Client has a private evolution chooser and browser")
	var has_ui: bool = panel.has_method("setup_evolutions")
	panel.queue_free()
	await frames()
	if has_ui:
		await check_client(true)
		await check_client(false)
	game.clear_battle()
	game.queue_free()
	paused = false
	await frames()
	print("%s: lan_evolution_ui_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func fixture() -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.lan_evolution_picks_override = true
	game.set_seats("local", "remote")
	game.phase = game.Phase.SETUP
	game.turn = 1
	game.tension = 6
	game.disaster_waiting = true
	game.run_director.close_modal()
	game.run_director.battle_active = false
	game.run_director.visible = false
	game.disaster_actions.begin_turn()
	var pool: Dictionary = Decks.pool("disaster")
	game.enemy_evolution_deck.assign([pool.evolutions.wildfire.duplicate(true),
		pool.evolutions.worldbreaker.duplicate(true), pool.evolutions.wildfire.duplicate(true)])
	game.enemy_hand.assign([pool.base.ember.duplicate(true)])
	for lane in 2:
		var card: Node = game.Card3DScene.instantiate()
		game.add_child(card)
		card.add_to_group("cards")
		card.setup(pool.base.ember.duplicate(true))
		card.place_on_slot(game._threat_slots()[lane])
		card.hide()
	game.enemy_draw_evolutions(1)

func check_client(use_board: bool) -> void:
	fixture()
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	panel.setup_evolutions(game.run_director)
	link.attach_panel(panel)
	var board: Node = null
	if use_board:
		board = preload("res://scripts/lan_board_3d.gd").new()
		root.add_child(board)
		board.setup(game, game.run_director, link, panel, "disaster")
	link.push_view(View.build(game))
	await frames(20)
	expect(panel.evolution_open(), "Opening offer renders before the Disaster turn")
	expect(panel.evolution_choices.get_child_count() == 3, "Choice screen renders three physical candidates")
	expect(not panel.evolution_cancel.visible, "Mandatory choice cannot be cancelled")
	expect(panel.end_button.disabled, "Plain End Turn is locked during offer")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await frames()
	expect(panel.evolution_open(), "Escape cannot dismiss mandatory offer")
	panel._on_hand_pressed(0)
	link._on_lane_pressed(0)
	if use_board:
		board.click_hand(0)
		board.click_lane(0)
		board.click_end()
		expect(board._open_lanes().is_empty() and board.end_button.disabled, "Board inputs lock during mandatory pick")
	expect(link.sent.is_empty(), "Pending offer cannot send ordinary actions")
	if use_board: await capture("remote-offer")
	var choice: RefCounted = game.evolution_choice
	var selected_id := ""
	# Pick a Wildfire rather than the four-sacrifice fixture finisher.
	for entry in choice.offer:
		if entry.definition.id == "wildfire": selected_id = entry.id
	var choose: Button
	for tile in panel.evolution_choices.get_children():
		if tile.get_meta("evolution_id") == selected_id:
			choose = tile.get_node("Box/ActionButton")
	expect(choose != null, "Each physical tile has a Choose button")
	if choose != null: await click(choose)
	expect(link.sent.size() == 1, "Real Choose click sends one message")
	if link.sent.is_empty():
		link.close()
		if use_board: board.queue_free()
		panel.queue_free()
		link.queue_free()
		return
	var msg: Dictionary = link.sent[0]
	expect(msg == {"kind": "evolution_pick", "match_id": choice.match_id,
		"offer_id": choice.offer_id, "id": selected_id}, "Choice sends IDs only, never definitions")
	expect(choice.held.is_empty() and choice.pending(), "Client never consumes the host reserve")
	if choose != null: await click(choose)
	expect(link.sent.size() == 1, "In-flight choice cannot be sent twice")
	expect((await Actions.apply(game, msg)).ok, "Host accepts actual UI pick")
	link.push_view(View.build(game))
	await frames()
	expect(not panel.evolution_open(), "Accepted view closes the offer")
	game.phase = game.Phase.ENEMY
	link.push_view(View.build(game))
	await frames()
	if use_board:
		expect(board.disaster_plans.tooltip_text == "Evolution", "Board placeholder becomes Evolution browser")
		await click(board.disaster_plans)
	else:
		await click(panel.evolution_button)
	await frames()
	expect(panel.evolution_open() and panel.evolution_cancel.visible, "Held browser opens and can be closed")
	if use_board: await capture("remote-held")
	var held_choose: Button = buttons(panel.evolution_choices).filter(func(button): return button.text == "Choose")[0]
	await click(held_choose)
	await frames()
	expect(link.picked_held == selected_id and not panel.evolution_open(), "Held browser selects physical source")
	if use_board: await capture("remote-held-hand")
	var before := link.sent.size()
	for lane in [0, 1]:
		if use_board:
			await click_point(game.camera.unproject_position(game._threat_slots()[lane].global_position))
		else:
			await click(panel.disaster_row.get_child(lane))
	await frames()
	expect(link.sent.size() == before + 1, "Sacrifice clicks send one held evolution play")
	if link.sent.size() > before:
		msg = link.sent[-1]
		expect(msg == {"kind": "evolve", "source": "held_evolutions", "match_id": choice.match_id,
			"id": selected_id, "lane": 1, "sacrifices": [0, 1]}, "Held play sends source ID and sacrifice lanes")
		expect((await Actions.apply(game, msg)).ok, "Host validates held UI sacrifice play")
	link.push_view(View.build(game))
	await frames()
	expect(choice.held.is_empty(), "Accepted play consumes one held copy")
	# New offers replace stale held browsers, and every lifecycle boundary erases private state.
	game.enemy_draw_evolutions(1)
	link.push_view(View.build(game))
	await frames()
	expect(panel.evolution_open(), "Scheduled offer replaces held UI")
	link.push_event("seat", {"side": "preparedness"})
	await frames()
	expect(not panel.evolution_open() and link.picked_held.is_empty(), "Seat change clears private UI and selection")
	if use_board: expect(board.selected_held.is_empty(), "Seat change clears board held source")
	link.push_view(View.build(game))
	await frames()
	link._on_server_disconnected()
	await frames()
	expect(not panel.evolution_open() and link.last_view.is_empty(), "Disconnect clears offer, held UI and cached view")
	fixture()
	link.push_view(View.build(game))
	await frames()
	var identity: String = choice.match_id
	fixture()
	link.push_view(View.build(game))
	await frames()
	expect(panel.view.match_id != identity and link.picked_held.is_empty(), "New match forgets prior held selection")
	var ended_view: Dictionary = View.build(game)
	link.push_event("match_over", {"winner": "preparedness"})
	await frames()
	expect(not panel.evolution_open(), "Match over clears private chooser")
	expect(not panel.view.has("held_evolutions") and not panel.view.has("evolution_offer"),
		"Lifecycle reset drops cached private panel data")
	link.push_view(ended_view)
	await frames()
	expect(not panel.evolution_open() and link.last_view.is_empty(), "Late ended-match view cannot restore choices")
	fixture()
	link.push_view(View.build(game))
	await frames()
	expect(panel.evolution_open() and panel.over_text.is_empty(), "New match clears the old result UI")
	if use_board: expect(not board.over and not board.over_box.visible, "New match clears board result lock")
	var no_offer: Dictionary = View.build(game)
	no_offer.evolution_offer = {}
	no_offer.evolution_waiting = false
	link.push_view(no_offer)
	panel.show_held_evolutions()
	expect(panel.evolution_open(), "Empty held browser can be inspected")
	fixture()
	game.enemy_evolution_deck.clear()
	choice.reset()
	link.push_view(View.build(game))
	await frames()
	expect(not panel.evolution_open(), "New empty-reserve match closes the previous held browser")
	link.close()
	if use_board: board.queue_free()
	panel.queue_free()
	link.queue_free()
	await frames()
