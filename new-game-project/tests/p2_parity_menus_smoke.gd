extends SceneTree
## p2-parity Part 2. The LAN client (Player 2) screens use the game's UI: the wait before the first view,
## the coin page buttons and the Esc menu (the host's ui_menu.tscn with its dark skin). The old 2D panel
## stays hidden in a normal match. Real loopback: the real client lan_title joins a plain LanSession host.

const LanSession = preload("res://scripts/lan_session.gd")
const MenuSkin = preload("res://scripts/suspended_menu.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24781
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title, the client
var other: Node  # the plain LanSession host
var other_joins: Array = []
var other_lefts: Array = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await process_frame
	make_other()
	director.show_title()
	director.add_lan_buttons(director.content.get_child(0))
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_p2_parity_menus_smoke.cfg"
	expect(VersusMatch.LAN_BOARD_3D, "flag: the 3D board is on")
	await join_and_start()
	check_waiting()
	await check_coin()
	await check_menu()
	await check_prep_seat()
	await check_leave()
	other.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lan.cfg_path))
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("p2_parity_menus_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: p2_parity_menus_smoke (%d checks)" % checks)
	quit(0)


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))
	other.peer_left.connect(func(id: int) -> void: other_lefts.append(id))


func join_and_start() -> void:
	expect(other.host_game(TEST_PORT) == OK, "the other side hosts")
	lan.show_join()
	director.content.find_child("IpEdit", true, false).text = "127.0.0.1"
	await frames(3)
	await click(find_button("Connect"))
	expect(await wait_until(func() -> bool: return other_joins.size() == 1), "the host accepted the client")
	expect(await wait_until(func() -> bool: return lan.room == "client"), "the client waits in the room")
	other.send_event("start", {})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), "the client layer is made")
	await frames(3)


# Before any coin event: the cover says it waits, in the game font. The old 2D panel is hidden.
func check_waiting() -> void:
	expect(not lan.client_panel.visible, "waiting: the old 2D panel is hidden")
	var title: Label = lan.client_cover.find_child("WaitingTitle", true, false)
	expect(title != null and title.is_visible_in_tree(), "waiting: the cover shows a title")
	expect(title != null and title.text == "WAITING FOR THE HOST", "waiting: the title text")
	expect(lan.client_cover.theme == director.root.theme, "waiting: the cover uses the game theme")


# The coin page side buttons use the game theme, so they are not Godot's grey default.
func check_coin() -> void:
	other.lobby = true
	other.send_event("coin", {"stage": "choosing", "call": 0, "result": 1, "winner": 2})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.coin_page)), "coin: the page shows")
	await frames(2)
	expect(lan.coin_page.theme == director.root.theme, "coin: the page uses the game theme")
	var button: Button = lan.coin_page.find_child("PreparednessButton", true, false)
	expect(button != null and button.get_theme_stylebox("normal") == director.root.theme.get_stylebox(
		"normal", "Button"), "coin: the side button draws with the game's button style")


# Esc opens the host's menu with the same labels. Resume closes it.
func check_menu() -> void:
	await key(KEY_ESCAPE)
	var menu: Control = lan.esc_menu
	expect(is_instance_valid(menu), "menu: Esc opens it")
	if not is_instance_valid(menu): return
	expect(lan.client_layer.get_child(-1) == menu, "menu: on top of the coin page")
	expect(menu.theme == director.root.theme, "menu: the game theme")
	var frame: StyleBox = menu.get_theme_stylebox("panel")
	expect(frame is StyleBoxFlat and frame.bg_color == MenuSkin.frame_fill(), "menu: the host's dark frame")
	expect(menu.find_child("SuspendedFrame", true, false) != null, "menu: the straps above the frame")
	var labels: Array = menu.find_children("*", "Label", true, false).map(func(label: Label) -> String:
		return label.text)
	expect("MIDNIGHT DRRILLS" in labels, "menu: the host's title")
	expect(labels.any(func(text: String) -> bool: return text.begins_with("Counters:")), "menu: the counters rule")
	var buttons: Array = menu.find_children("*", "Button", true, false).filter(func(b: Button) -> bool:
		return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)
	expect(buttons == ["Resume", "Return to starting screen", "Quit game"], "menu: Resume, return, quit")
	await frames(2)
	expect(menu.get_global_rect().size.x <= 560.0 and lan.client_layer.get_child(-1) == menu, "menu: size")
	var viewport := root.get_visible_rect()
	expect(viewport.encloses(menu.get_global_rect()), "menu: inside the screen")
	await click(menu.find_child("KeepButton", true, false))
	expect(not is_instance_valid(lan.esc_menu), "menu: Resume closes it")


# The seat as Preparedness: the old prep panel is hidden too. The first view turns on the board.
func check_prep_seat() -> void:
	other.lobby = false
	other.send_event("seat", {"side": "preparedness"})
	expect(await wait_until(func() -> bool: return lan.client_side == "preparedness"), "seat: the client is seated")
	await frames(2)
	expect(is_instance_valid(lan.client_panel) and not lan.client_panel.visible, "seat: the old prep panel is hidden")
	expect(lan.client_cover.visible, "seat: the waiting cover stays until the first view")
	var view := {
		"round": 1, "first_side": "response", "coin": {}, "side": "preparedness", "phase": "play",
		"turn_side": "preparedness", "is_prep_turn": true, "prep_hand": [],
		"sides": {
			"response": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 3},
			"disaster": {"hp": 20, "max_hp": 20, "barrier": 0, "resource": 3, "resource_cap": 3},
		},
		"lanes": {"response": ["", "", "", ""], "disaster": ["", "", "", ""]}, "cards": {}, "hints": [],
		"counts": {}, "energy": 3, "energy_cap": 3, "plan_tokens": 0, "armed": "", "tactics": [],
	}
	lan.session.view_received.emit(view)
	await frames(3)
	expect(lan.board_3d.shown and not lan.client_cover.visible, "seat: the first view shows the board")
	expect(not lan.client_panel.visible, "seat: the old panel stays hidden under the board")


# The menu's return button leaves the match and shows the title, like before.
func check_leave() -> void:
	await key(KEY_ESCAPE)
	expect(is_instance_valid(lan.esc_menu), "leave: Esc opens the menu on the board")
	await click(lan.esc_menu.find_child("LeaveButton", true, false) if is_instance_valid(lan.esc_menu) else null)
	expect(await wait_until(func() -> bool: return not is_instance_valid(lan.client_layer)), "leave: layer closed")
	expect(director.screen == "title", "leave: back on the title")
	expect(await wait_until(func() -> bool: return other_lefts.size() == 1), "leave: the host hears it")


func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call():
			return true
		if Time.get_ticks_msec() - start > 10000:
			return false
		await process_frame
	return check.call()


func frames(count: int) -> void:
	for i in count:
		await process_frame


# A real mouse click: motion first, then press and release on the middle of the control.
func click(control: Control) -> void:
	if control == null:
		expect(false, "click: control exists")
		return
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await frames(3)


func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await frames(2)


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null
