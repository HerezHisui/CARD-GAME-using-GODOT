extends SceneTree
## UI_CARD_PICKER. Card choices show as a compact grid of card tiles; a click on the card picks it.
## Real card tiles, hidden entries as backs, no separate Pick button, panel sized to the cards.

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
	for i in count:
		if i == 2 and count > 3: candidates.append({"handle": i})
		else: candidates.append({"handle": i, "card": {"name": "Quick Dash", "type": "response", "element": "evac", "cost": 1, "attack": 1, "health": 2}})
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

func check(size: Vector2i, count: int) -> void:
	root.size = size
	await frames()
	var label := "%dx%d, %d candidates: " % [size.x, size.y, count]
	picked.clear()
	cancelled = 0
	session.view_received.emit(make_view(count))
	await frames(6)
	var box: Control = board.choice_box
	expect(is_instance_valid(box), label + "the choice box is up")
	if not is_instance_valid(box): return
	var screen: Rect2 = board.hud.get_global_rect()
	expect(screen.encloses(box.get_global_rect()), label + "panel inside the viewport")
	var scroll: ScrollContainer = box.find_child("ChoiceScroll", true, false)
	expect(scroll != null, label + "tiles sit in a ScrollContainer")
	if scroll == null: return
	for handle in count:
		var entry: Button = box.find_child("ChoiceEntry%d" % handle, true, false)
		expect(entry != null and entry.text != "" and entry.flat, label + "entry %d is a flat overlay on its card, named in text" % handle)
	var faces := box.find_children("*", "TextureRect", true, false)
	expect(faces.size() >= count, label + "every candidate shows a card face or back")
	if count == 3:
		expect(box.get_global_rect().size.y < screen.size.y * 0.65, label + "a short list gives a short panel")
	var first: Button = box.find_child("ChoiceEntry0", true, false)
	await mouse_click(first.get_global_rect().get_center())
	expect(picked == [0], label + "a click on the first card picks it")
	var cancel: Button = box.find_child("ChoiceCancel", true, false)
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
		for count in [3, 9, 21]:
			await check(size, count)
	board.free()
	cover.free()
	panel.free()
	session.queue_free()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("ui_card_picker_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: ui_card_picker_smoke (%d checks)" % checks)
	quit(0)
