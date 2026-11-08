extends SceneTree

var checks := 0
var failures := 0
var sent := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 3) -> void:
	for i in count: await process_frame

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

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.clear_battle()
	game.encounter_kind = "versus"
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.set_seats("remote", "local")
	# LAN_PREP_UTILITIES ships on now. This suite checks the flag-off fallback, so switch it off.
	game.lan_prep_utilities_override = false
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.preparedness = 3
	game.plans.tokens = 2
	game.plans.unlocked.assign(["brace", "supply", "shelter", "extract"])
	game.add_card_to_hand({"id": "supply_cache", "name": "Supply Cache", "type": "response",
		"cost": 1, "utility": true, "effect": "draw", "draw_count": 2})
	var ally: Node = game.Card3DScene.instantiate()
	game.add_child(ally)
	ally.setup({"id": "ally", "name": "Ally", "type": "response", "element": "evac",
		"cost": 0, "attack": 1, "health": 3})
	ally.in_hand = false
	ally.current_slot = game._response_slots()[0]
	ally.position = ally.current_slot.position
	ally.add_to_group("cards")
	var view: Dictionary = preload("res://scripts/lan_view.gd").build(game, "preparedness")
	var panel: Control = preload("res://scripts/lan_prep_panel.gd").new()
	root.add_child(panel)
	panel.show_view(view)
	panel.hand_pressed.connect(func(_index: int): sent += 1)
	panel.tactic_pressed.connect(func(_id: String): sent += 1)
	expect(panel.hand_row.get_child(0).disabled, "Fallback utility remains disabled")
	expect("Not available in LAN" in panel.hand_row.get_child(0).text, "Fallback utility explains restriction")
	panel._on_hand_pressed(0)
	expect(panel.reject_label.text == "Refused: Not available in LAN", "Fallback attempt uses clear refusal")
	for id in ["supply", "shelter", "extract"]:
		panel._on_tactic_pressed(id)
		expect(panel.reject_label.text == "Refused: Not available in LAN", "Fallback refusal for " + id)
	expect(sent == 0, "Unsupported fallback picks send no actions")
	var session: Node = preload("res://scripts/lan_session.gd").new()
	root.add_child(session)
	var board: Node = preload("res://scripts/lan_board_3d.gd").new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness")
	session.view_received.emit(view)
	await frames()
	var before := JSON.stringify(preload("res://scripts/lan_view.gd").build(game, "preparedness"))
	board.click_hand(0)
	expect(board.note_body.text == "Not available in LAN" and board.note.visible, "3D utility refusal is clear")
	# Tactics open from the Plans icon box, as on the host.
	await click(board.plans_toggle)
	for id in ["supply", "shelter", "extract"]:
		if not board.tactic_box.visible: await click(board.plans_toggle)
		await click(board.tactic_box.get_node("Tactic_" + id))
		expect(board.note.visible and board.note_body.text == "Not available in LAN", "Real tactic click: " + id)
	expect(sent == 0 and board.selected_tactic.is_empty(), "Unsupported 3D clicks do not select or send")
	expect(before == JSON.stringify(preload("res://scripts/lan_view.gd").build(game, "preparedness")),
		"Refusals spend no resources and change no authoritative state")
	session.event_received.emit("reject", {"reason": "not_supported"})
	expect(board.note_body.text == "Not available in LAN", "Host refusal uses same client message")
	if "--render-lan-unavailable" in OS.get_cmdline_user_args():
		await frames(15)
		await RenderingServer.frame_post_draw
		var path := "C:/Users/0stef/Downloads/evolution-stage1-checks/lan-not-available.png"
		expect(root.get_texture().get_image().save_png(path) == OK, "Rendered refusal screenshot")
	if not board.tactic_box.visible: await click(board.plans_toggle)
	await click(board.tactic_box.get_node("Tactic_brace"))
	expect(sent == 1 and board.selected_tactic == "brace", "Supported Brace selection remains unchanged")
	board.queue_free()
	panel.queue_free()
	session.queue_free()
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: lan_unavailable_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
