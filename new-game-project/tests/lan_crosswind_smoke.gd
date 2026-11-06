extends SceneTree

class RecordingLink:
	extends "res://scripts/lan_session.gd"
	var sent: Array = []
	func request_action(msg) -> void:
		sent.append(msg.duplicate(true))

const Decks = preload("res://scripts/versus_decks.gd")
const Actions = preload("res://scripts/lan_actions.gd")
const View = preload("res://scripts/lan_view.gd")
var failures := 0
var checks := 0
var game: Node
var rendered := false
var output := "C:/Users/0stef/Downloads/drrills-crosswind-checks"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func fixture(remote: bool = true) -> void:
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_waiting = true
	game.set_seats("local", "remote" if remote else "local")
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()
	game._set_phase(game.Phase.ENEMY)
	game.tension = 6
	game.disaster_actions.begin_turn()

func unit(id: String, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": id, "name": id, "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 3})
	card.place_on_slot(game._threat_slots()[lane])
	return card

func crosswind(lane: int) -> Node:
	var data: Dictionary = Decks.pool("disaster").base.crosswind.duplicate(true)
	game.enemy_hand.assign([data])
	expect((await game.disaster_actions.play_base(data, game._threat_slots()[lane])).ok, "Crosswind play accepted")
	return game._get_card_in_slot(game._threat_slots()[lane])

func request(ally: int, destination: int) -> Dictionary:
	var choice: Dictionary = game.disaster_relocation.view()
	return {"kind": "move_ally", "choice": choice.get("choice", -1),
		"encounter": choice.get("encounter", -1), "ally": ally, "lane": destination}

func run() -> void:
	rendered = "--render-crosswind" in OS.get_cmdline_user_args()
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.presentation.automated_choice = 0
	expect(game.get("disaster_relocation") != null, "Human Crosswind has authoritative pending relocation")
	if game.get("disaster_relocation") == null:
		quit(1)
		return
	fixture()
	var ally := unit("Ally", 0)
	var source := await crosswind(1)
	var relocation: RefCounted = game.disaster_relocation
	expect(relocation.pending(), "Crosswind creates pending choice")
	expect(ally.current_slot == game._threat_slots()[0], "Host does not move an ally automatically")
	var private_view: Dictionary = View.build(game)
	expect(private_view.relocation.allies == [0] and private_view.relocation.destinations == [2, 3],
		"Private view exposes legal ally and destination lanes")
	expect(not View.build(game, "preparedness").has("relocation"), "Preparedness never receives pending choice")
	expect(game.disaster_actions.end_turn().reason == "busy", "Pending choice blocks End turn")
	var extra: Dictionary = Decks.pool("disaster").base.ember.duplicate(true)
	game.enemy_hand.append(extra)
	expect(game.disaster_actions.card_problem(extra) == "busy", "Pending choice blocks other plays")
	var used: int = game.disaster_actions.actions_used
	var tension: int = game.tension
	var valid := request(0, 2)
	game.disaster_actions.busy = true
	expect((await Actions.apply(game, valid)).reason == "busy", "Move waits for Crosswind animation to finish")
	game.disaster_actions.busy = false
	for payload in [{}, {"ally": "0"}, {"lane": 99}, {"ally": 1}, {"lane": 1},
			{"encounter": -1}, {"choice": -1}, {"ally": 2}, {"lane": 0}]:
		var bad := valid.duplicate()
		bad.merge(payload, true)
		if payload.is_empty(): bad.erase("choice")
		var result: Dictionary = await Actions.apply(game, bad)
		expect(not result.ok and relocation.pending(), "Forged or illegal relocation preserves pending choice")
	var result: Dictionary = await Actions.apply(game, valid, "preparedness")
	expect(not result.ok, "Preparedness cannot relocate Disaster cards")
	result = await Actions.apply(game, valid)
	expect(result.ok and ally.current_slot == game._threat_slots()[2], "Host accepts selected ally and destination")
	expect(not relocation.pending(), "Choice consumed once")
	expect(game.tension == tension and game.disaster_actions.actions_used == used, "Relocation costs no extra action")
	expect(not (await Actions.apply(game, valid)).ok, "Replayed choice refused")
	fixture()
	source = await crosswind(0)
	expect(not relocation.pending(), "No ally means no pending choice")
	fixture()
	for lane in 3: unit("Full%d" % lane, lane)
	await crosswind(3)
	expect(not relocation.pending(), "Full board means no pending choice")
	fixture()
	ally = unit("Stale ally", 0)
	source = await crosswind(1)
	valid = request(0, 2)
	source.remove_from_group("cards")
	source.queue_free()
	await frames()
	expect(not (await Actions.apply(game, valid)).ok and not relocation.pending(), "Freed source invalidates choice")
	fixture()
	unit("Reset ally", 0)
	await crosswind(1)
	valid = request(0, 2)
	game.clear_battle()
	expect(not relocation.pending() and not (await Actions.apply(game, valid)).ok, "Reset invalidates choice")
	await check_local()
	await check_client()
	await check_plain_client()
	await check_network()
	await check_invalidations()
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: lan_crosswind_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button: result.append(node)
	for child in node.get_children(): result += buttons(child)
	return result

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
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

func capture(name: String) -> void:
	if not rendered: return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.5, true).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, "Capture " + name)

func check_local() -> void:
	fixture(false)
	var ally := unit("Local Ally", 0)
	await crosswind(1)
	await frames()
	var director: Node = game.run_director
	expect(director.screen == "disaster_relocation" and director.modal.visible, "Local owner gets a chooser")
	expect(not paused, "Local choice keeps network processing unpaused")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await frames()
	expect(game.disaster_relocation.pending() and director.screen == "disaster_relocation",
		"Esc cannot discard the mandatory local choice")
	await capture("host-choose-ally")
	var choices: Array = buttons(director.content)
	expect(choices.size() == 1 and choices[0].text.begins_with("Lane 1"), "Local ally chooser excludes Crosswind")
	await click(choices[0])
	await frames()
	choices = buttons(director.content)
	expect(choices.size() == 2 and choices[0].text == "Lane 3", "Local destination chooser lists empty lanes")
	await capture("host-choose-destination")
	await click(choices[0])
	await frames()
	expect(ally.current_slot == game._threat_slots()[2] and not game.disaster_relocation.pending(),
		"Actual local clicks relocate the selected ally")
	expect(not director.modal.visible, "Successful local choice closes chooser")

func check_client() -> void:
	fixture()
	var ally := unit("Remote Ally", 0)
	await crosswind(1)
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	link.attach_panel(panel)
	var board: Node = preload("res://scripts/lan_board_3d.gd").new()
	root.add_child(board)
	for card in get_nodes_in_group("cards"): card.hide()
	board.setup(game, game.run_director, link, panel, "disaster")
	var private_view := View.build(game)
	link.push_view(private_view)
	await frames(15)
	expect(board.end_button.disabled, "Remote End turn is disabled during relocation")
	expect(board._open_lanes() == [0], "Only remote ally lane is lit initially")
	await capture("client-choose-ally")
	await click(buttons(board.relocation_box)[0])
	await frames()
	expect(panel.relocation_ally == 0 and board._open_lanes() == [2, 3], "Remote ally click reveals empty lanes")
	link.push_view(private_view)
	await frames()
	expect(panel.relocation_ally == 0, "Repeated pending view preserves selected ally")
	await capture("client-choose-destination")
	await click(buttons(board.relocation_box)[0])
	await frames()
	expect(link.sent.size() == 1 and link.sent[0].kind == "move_ally", "Remote UI sends a relocation action")
	expect(ally.current_slot == game._threat_slots()[0], "Client does not move authoritative card")
	if not link.sent.is_empty():
		var result: Dictionary = await Actions.apply(game, link.sent[0])
		expect(result.ok and ally.current_slot == game._threat_slots()[2], "Host validates remote UI payload")
	link.push_view(View.build(game))
	await frames()
	expect(board.relocation_box == null, "Resolved view removes remote choice UI")
	link.push_view(private_view)
	link.push_event("match_over", {"winner": "preparedness"})
	await frames()
	expect(board.relocation_box == null and board._open_lanes().is_empty(), "Match end removes remote chooser")
	board.queue_free()
	panel.queue_free()
	link.queue_free()
	await frames()



func network_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var link: Node = preload("res://scripts/lan_session.gd").new()
	link.name = "LanSession"
	holder.add_child(link)
	return link

func wait_until(predicate: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < 10000:
		await process_frame
	return predicate.call()

func check_network() -> void:
	fixture()
	var ally := unit("Network Ally", 0)
	await crosswind(1)
	var host := network_side("CrosswindHost")
	var client := network_side("CrosswindClient")
	var refusals: Array = []
	var results: Array = []
	client.join_refused.connect(func(reason: String): refusals.append(reason))
	host.action_done.connect(func(result: Dictionary): results.append(result))
	expect(host.host_game(24717) == OK, "Crosswind network host starts")
	client.build = "3|" + Engine.get_version_info().string
	expect(client.join_game("127.0.0.1", 24717) == OK, "Older protocol-3 build starts negotiation")
	expect(await wait_until(func(): return not refusals.is_empty()), "Old protocol-3 build receives refusal")
	expect(refusals == ["version"] and host.disaster_peer == 0, "Missing Crosswind capability is refused")
	client.close()
	await frames(15)
	client.build = host.build
	expect(client.join_game("127.0.0.1", 24717) == OK, "Updated client connects")
	expect(await wait_until(func(): return host.disaster_peer != 0), "Updated client receives Disaster seat")
	host.game = game
	host.send_view()
	expect(await wait_until(func(): return client.last_view.has("relocation")), "Pending choice delivered over ENet")
	var msg := request(0, 2)
	host.seat_client("preparedness")
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() >= 1), "Wrong-seat action receives reply")
	expect(not results[0].ok and game.disaster_relocation.pending(), "Wrong network seat cannot resolve choice")
	host.seat_client("disaster")
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() >= 2), "Disaster move receives reply")
	expect(results[1].ok and ally.current_slot == game._threat_slots()[2], "Real network action moves chosen ally")
	client.request_action(msg)
	expect(await wait_until(func(): return results.size() >= 3), "Replay receives reply")
	expect(not results[2].ok, "Network replay refused")
	fixture()
	unit("Disconnect Ally", 0)
	await crosswind(1)
	expect(game.disaster_relocation.pending(), "Choice pending before disconnect")
	client.close()
	expect(await wait_until(func(): return not game.disaster_relocation.pending()), "Disconnect clears pending choice")
	host.close()
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await frames()

func check_invalidations() -> void:
	fixture()
	unit("Game over Ally", 0)
	await crosswind(1)
	game._set_phase(game.Phase.GAME_OVER)
	expect(not game.disaster_relocation.pending(), "Game over clears choice")
	fixture()
	unit("Changed encounter Ally", 0)
	await crosswind(1)
	game.encounter_serial += 1
	expect(not game.disaster_relocation.pending(), "Encounter change clears choice")
	fixture()
	unit("Replaced source Ally", 0)
	var source := await crosswind(1)
	var old := request(0, 2)
	game.disaster_relocation.begin(source)
	expect(not (await Actions.apply(game, old)).ok and game.disaster_relocation.pending(),
		"New source choice rejects old token within the same encounter")
	fixture()
	var ally := unit("Occupied destination Ally", 0)
	await crosswind(1)
	var msg := request(0, 2)
	unit("New blocker", 2)
	expect(not (await Actions.apply(game, msg)).ok and ally.current_slot == game._threat_slots()[0],
		"Host rechecks destination occupancy after view delivery")
	fixture()
	ally = unit("AI Ally", 0)
	game.disaster_is_human = false
	await crosswind(1)
	expect(not game.disaster_relocation.pending(), "AI Disaster keeps automatic legacy path")
	fixture()
	game.encounter_kind = "battle"
	unit("Singleplayer Ally", 0)
	await crosswind(1)
	expect(not game.disaster_relocation.pending(), "Singleplayer keeps automatic legacy path")


func check_plain_client() -> void:
	fixture()
	unit("Panel Ally", 0)
	await crosswind(1)
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	link.attach_panel(panel)
	link.push_view(View.build(game))
	await frames()
	expect(panel.relocation_lanes() == [0] and panel.end_button.disabled, "Plain panel offers ally selection")
	await click(panel.disaster_row.get_child(0))
	await frames()
	expect(panel.relocation_lanes() == [2, 3], "Plain panel switches to empty destinations")
	await click(panel.disaster_row.get_child(2))
	await frames()
	expect(link.sent.size() == 1 and link.sent[0].ally == 0 and link.sent[0].lane == 2,
		"Plain panel clicks send the same move_ally payload")
	panel.pick_relocation(3)
	expect(link.sent.size() == 1, "Pending reply suppresses duplicate UI submissions")
	link.push_view(View.build(game))
	panel.show_match_over("preparedness")
	expect(panel.relocation_lanes().is_empty(), "Match end disables plain panel relocation")
	panel.queue_free()
	link.queue_free()
	await frames()
