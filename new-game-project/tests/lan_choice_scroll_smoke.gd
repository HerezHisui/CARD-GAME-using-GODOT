extends SceneTree
## Audit A5. A LAN deck search with many candidates stays inside the viewport and scrolls.
## 21 and 40 candidates at 1280x720 and 1920x1080. Mouse only: wheel scroll, pick first, middle, last, cancel.

const LanSession = preload("res://scripts/lan_session.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")

var failures := 0
var checks := 0
var game: Node
var session: Node
var board: Node
var panel: Control
var picked: Array = []
var cancelled := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

func frames(count: int = 3) -> void:
	for i in count: await process_frame

func make_view(count: int) -> Dictionary:
	var candidates: Array = []
	for i in count: candidates.append({"handle": i, "card": {"name": "Candidate %d" % i}})
	var hint := {"can_play": true, "problem": "", "lanes": [0]}
	return {
		"round": 1, "first_side": "response", "coin": {}, "side": "preparedness",
		"is_prep_turn": true, "prep_hand": ["h0"],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 5},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 4},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]},
		"cards": {"h0": {"definition": {"name": "Hand", "type": "response", "element": "evac", "cost": 0,
			"attack": 1, "health": 3}, "runtime": {"max_health": 3, "statuses": {}, "modifiers": []}}},
		"hints": [hint], "counts": {"disaster_hand": 4, "disaster_draw": 9, "response_draw": 8},
		"energy": 3, "energy_cap": 5, "plan_tokens": 0, "armed": "", "tactics": [],
		"pending_choice": {"name": "Search and Rescue", "prompt": "Choose a card from the deck.",
			"stage": "deck", "handles": [], "candidates": candidates},
	}

func mouse_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.global_position = point
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame

func wheel(point: Vector2, times: int) -> void:
	for i in times:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.position = point
		event.global_position = point
		event.pressed = true
		root.push_input(event, true)
		var release: InputEventMouseButton = event.duplicate()
		release.pressed = false
		root.push_input(release, true)
		await process_frame

func open_list(count: int) -> void:
	picked.clear()
	cancelled = 0
	session.view_received.emit(make_view(count))
	await frames()

func check_size(size: Vector2i, count: int) -> void:
	root.size = size
	await frames()
	var label := "%dx%d, %d candidates: " % [size.x, size.y, count]
	await open_list(count)
	var box: Control = board.choice_box
	expect(is_instance_valid(box), label + "the choice box is up")
	if not is_instance_valid(box): return
	var screen: Rect2 = board.hud.get_global_rect()
	var rect := box.get_global_rect()
	expect(screen.encloses(rect), label + "panel inside the viewport %s vs %s" % [str(rect), str(screen)])
	var scroll: ScrollContainer = box.find_child("ChoiceScroll", true, false)
	expect(scroll != null, label + "candidates sit in a ScrollContainer")
	if scroll == null: return
	var cancel: Button = box.find_child("ChoiceCancel", true, false)
	expect(screen.encloses(cancel.get_global_rect()), label + "Cancel is on screen")
	var last: Button = box.find_child("ChoiceEntry%d" % (count - 1), true, false)
	expect(not scroll.get_global_rect().encloses(last.get_global_rect()), label + "the last entry starts hidden")
	# First entry: a real click.
	var first: Button = box.find_child("ChoiceEntry0", true, false)
	await mouse_click(first.get_global_rect().get_center())
	expect(picked == [0], label + "first entry picked by mouse")
	# Wheel scrolls the list.
	picked.clear()
	await wheel(scroll.get_global_rect().get_center(), 6)
	expect(scroll.scroll_vertical > 0, label + "the wheel scrolls the list")
	# Middle entry.
	var middle_index := count / 2
	var middle: Button = box.find_child("ChoiceEntry%d" % middle_index, true, false)
	scroll.ensure_control_visible(middle)
	await frames()
	await mouse_click(middle.get_global_rect().get_center())
	expect(picked == [middle_index], label + "middle entry picked by mouse")
	# Last entry, after scrolling to the end.
	picked.clear()
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await frames()
	expect(scroll.get_global_rect().encloses(last.get_global_rect()), label + "the last entry is reachable")
	await mouse_click(last.get_global_rect().get_center())
	expect(picked == [count - 1], label + "last entry picked by mouse")
	# Cancel.
	await mouse_click(cancel.get_global_rect().get_center())
	expect(cancelled == 1, label + "Cancel clicked by mouse")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	session = LanSession.new()
	root.add_child(session)
	panel = LanPrepPanel.new()
	panel.choice_picked.connect(func(handle: int) -> void: picked.append(handle))
	panel.choice_cancelled.connect(func() -> void: cancelled += 1)
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	board = LanBoard3D.new()
	root.add_child(board)
	board.setup(game, game.run_director, session, panel, "preparedness", cover)
	game.run_director.modal.hide()
	game.run_director.privacy_screen.hide()
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for count in [21, 40]:
			await check_size(size, count)
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("lan_choice_scroll_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: lan_choice_scroll_smoke (%d checks)" % checks)
	quit(0)
