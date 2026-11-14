extends SceneTree
## LAN lobby step: Multiplayer on the title, the lobby hub, the host room and the client room
## (scripts/lan_title.gd, run_director.open_lan_lobby). The other side of each link is a plain
## LanSession in its own subtree, as in lan_title_smoke.gd.

const LanSession = preload("res://scripts/lan_session.gd")
const LanTitle = preload("res://scripts/lan_title.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
const UI = preload("res://scripts/ui_theme.gd")

# Not the game port and not a port another LAN suite uses.
const TEST_PORT := 24701
const MAX_FRAMES := 3000
const WAITING := "Waiting for a player..."
const CFG_PATH := "user://test_lan_room_smoke.cfg"  # never the real user://lan.cfg

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession on the other side
var other_joined := false
var other_lost := false
var other_refused := ""
var other_events: Array = []  # [kind, data] from the host
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
	game.presentation.automated_choice = 0
	await process_frame
	remove_cfg()
	check_last_ip_file()
	check_title()
	make_other()
	await check_host_room()
	await check_host_version_refused()
	await check_client_room()
	await check_client_leave()
	await check_host_left_in_room()
	await check_client_version_refused()
	lan.session.close()
	other.close()
	remove_cfg()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_room_smoke (%d checks)" % checks)
	quit(0)


# The last IP file: missing, saved and read back, broken.
func check_last_ip_file() -> void:
	expect(LanTitle.read_last_ip(CFG_PATH) == "", "ip file: missing file gives an empty IP")
	LanTitle.save_last_ip(CFG_PATH, "26.12.34.56")
	expect(LanTitle.read_last_ip(CFG_PATH) == "26.12.34.56", "ip file: saved IP reads back")
	var file := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	file.store_string("[[[ not a config file")
	file.close()
	expect(LanTitle.read_last_ip(CFG_PATH) == "", "ip file: broken file gives an empty IP")
	remove_cfg()


# The real title: one Multiplayer button, no LAN Versus, Host LAN or Join LAN button.
func check_title() -> void:
	expect(VersusMatch.LAN_ENABLED, "title: LAN_ENABLED is true in the repo")
	director.show_title()
	expect(count_buttons("Multiplayer") == 1, "title: one Multiplayer button")
	expect(count_buttons("LAN Versus") == 0, "title: no LAN Versus button")
	expect(find_button("Host LAN") == null and find_button("Join LAN") == null, "title: no Host LAN or Join LAN")
	director.ensure_lan_title()
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = CFG_PATH


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.joined_host.connect(func() -> void: other_joined = true)
	other.host_lost.connect(func() -> void: other_lost = true)
	other.join_refused.connect(func(reason: String) -> void: other_refused = reason)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))
	other.peer_left.connect(func(id: int) -> void: other_lefts.append(id))


# Real clicks: Multiplayer, LAN Versus, Host a game, Start match. Waiting, Connected, leave, rejoin, start.
func check_host_room() -> void:
	director.show_title()
	await frames(3)
	await click(find_button("Multiplayer"))
	expect(find_label("MULTIPLAYER") != null, "hub: Multiplayer opens the panel")
	await frames(3)
	await click(find_button("LAN Versus"))
	expect(find_label("LAN VERSUS") != null, "hub: LAN Versus opens the hub")
	expect(find_button("Host a game") != null and find_button("Join a game") != null, "hub: Host and Join buttons")
	expect(find_button("Back") != null, "hub: Back button")
	await frames(3)
	await click(find_button("Host a game"))
	expect(lan.room == "host" and lan.session.is_open() and lan.session.is_host, "host room: listening")
	expect(status_text() == WAITING, "host room: status Waiting")
	expect(status_color() == UI.AMBER, "host room: Waiting in the theme amber")
	expect(find_label_part("Port %d" % TEST_PORT) != null, "host room: shows the port")
	expect(find_label_part("Windows Firewall") == null, "host room: no firewall paragraph")
	expect(find_in(director.content, "Player1Row") == null, "host room: no player rows")
	var start: Button = find_in(director.content, "StartButton")
	expect(start != null and start.disabled, "host room: Start match is off before a join")
	await frames(3)
	await click(start)
	expect(not lan.in_match and not versus_running(), "host room: a click on the off button does nothing")
	await join_host_room()
	expect(not lan.in_match and not versus_running(), "host room: a join does not start the match")
	expect(status_text().begins_with("Player 2 connected"), "host room: status Connected")
	expect(status_color() == UI.GOLD, "host room: Connected in the theme gold")
	expect(not start.disabled, "host room: Start match is on after the join")
	expect(await wait_until(func() -> bool: return status_text().ends_with(" ms")),
		"host room: the status line shows the ping in ms")
	# Player 2 leaves the room: back to Waiting, the port stays open.
	other.close()
	expect(await wait_until(func() -> bool: return lan.remote_id == 0), "host room: the host saw Player 2 leave")
	expect(status_text() == WAITING, "host room: back to Waiting")
	expect(start.disabled, "host room: Start match is off again")
	expect(lan.room == "host" and lan.session.is_open() and lan.session.is_host, "host room: the port stays open")
	expect(not lan.in_match and not versus_running(), "host room: nothing started")
	await join_host_room()
	expect(not start.disabled, "host room: a new player can join")
	other_events.clear()
	await frames(3)
	await click(start)
	expect(lan.in_match and versus_running(), "start: Start match starts the match")
	expect(lan.room == "", "start: the room is closed")
	expect(await wait_until(func() -> bool: return not other_events.is_empty()), "start: the client got an event")
	expect(other_events[0][0] == "start", "start: the first event is start")
	# Clean up: the client leaves, the host ends the match.
	other.close()
	expect(await wait_until(func() -> bool: return not versus_running()), "start: match ends on leave")
	await frames(5)


# A client with another build is refused. The host room stays at Waiting.
func check_host_version_refused() -> void:
	director.show_title()
	lan.show_host()
	other_refused = ""
	other.build = "0|old build"
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, "host refused: join starts")
	expect(await wait_until(func() -> bool: return other_refused == "version"), "host refused: client is refused")
	expect(lan.room == "host" and lan.remote_id == 0 and status_text() == WAITING, "host refused: still Waiting")
	other.build = LanSession.build_string()
	other.close()
	lan.session.close()
	await frames(5)


# The real client room against a plain host. Start comes, then a coin event right after it.
func check_client_room() -> void:
	await join_as_client()
	expect(status_text().begins_with("Connected to 127.0.0.1"), "client room: status shows Connected and the host IP")
	expect(status_color() == UI.GOLD, "client room: Connected in the theme gold")
	expect(find_button("Leave") != null, "client room: Leave button")
	expect(await wait_until(func() -> bool: return status_text().ends_with(" ms")),
		"client room: the status line shows the ping in ms")
	expect(not is_instance_valid(lan.client_panel), "client room: no panel before start")
	expect(LanTitle.read_last_ip(CFG_PATH) == "127.0.0.1", "client room: the last IP is saved")
	# Start and the first coin event back to back, as the host sends them.
	other.send_event("start", {})
	other.send_event("coin", {"stage": "calling"})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), "start: the panel shows")
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.coin_page)),
		"start: the coin event right after start reaches the panel")
	expect(lan.room == "", "start: the client room is closed")
	lan.back_to_title()
	expect(await wait_until(func() -> bool: return other_lefts.size() == 1), "start: the host saw the client go")
	other.close()
	await frames(5)


# Leave in the client room closes the client and goes back to the hub. The last IP comes from the file.
func check_client_leave() -> void:
	lan.last_ip = ""
	await join_as_client()
	await frames(3)
	await click(find_button("Leave"))
	expect(not lan.session.is_open(), "leave: the client session is closed")
	expect(lan.room == "" and find_label("LAN VERSUS") != null, "leave: back to the hub")
	expect(await wait_until(func() -> bool: return other_lefts.size() == 1), "leave: the host saw the client leave")
	other.close()
	await frames(5)


# The host goes away while the client waits in the room: The host left, and a button back to the hub.
func check_host_left_in_room() -> void:
	await join_as_client()
	# leave() tells the client at once; close() alone waits for the ENet timeout.
	await other.leave()
	expect(await wait_until(func() -> bool: return find_label_part("The host left.") != null),
		"host left: the client shows The host left")
	expect(not lan.session.is_open() and lan.room == "", "host left: the client session is closed")
	await frames(3)
	await click(find_button("Back to lobby"))
	expect(find_label("LAN VERSUS") != null, "host left: the button goes back to the hub")
	await frames(5)


# The host has another build: the client sees Different game version.
func check_client_version_refused() -> void:
	other.build = "0|old build"
	expect(other.host_game(TEST_PORT) == OK, "client refused: the other side hosts")
	director.show_title()
	lan.show_join()
	find_node_named("IpEdit").text = "127.0.0.1"
	lan.connect_to_host()
	expect(await wait_until(func() -> bool: return find_label_part("Different game version") != null),
		"client refused: the client shows Different game version")
	expect(not lan.session.is_open() and lan.room == "", "client refused: the client session is closed")
	other.build = LanSession.build_string()
	other.close()
	await frames(5)


# --- helpers ---

func join_host_room() -> void:
	other_joined = false
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, "join: the client starts joining")
	expect(await wait_until(func() -> bool: return other_joined and lan.room_connected()), "join: host room has P2")


# The real lan_title joins a plain host and waits in the client room. The IP field is filled from the file.
func join_as_client() -> void:
	expect(other.host_game(TEST_PORT) == OK, "client: the other side hosts")
	other_joins.clear()
	other_lefts.clear()
	director.show_title()
	lan.show_lobby()
	await frames(3)
	await click(find_button("Join a game"))
	var edit: LineEdit = find_node_named("IpEdit")
	if edit.text == "":
		edit.text = "127.0.0.1"
	else:
		expect(edit.text == "127.0.0.1", "client: the IP field has the last IP")
	await frames(3)
	await click(find_button("Connect"))
	expect(await wait_until(func() -> bool: return other_joins.size() == 1 and lan.room == "client"),
		"client: waits in the room")


# The Versus match node is made on the first match, so it can be null here.
func versus_running() -> bool:
	return is_instance_valid(director.versus_match) and director.versus_match.running


func remove_cfg() -> void:
	if FileAccess.file_exists(CFG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))


func status_text() -> String:
	var status: Label = find_in(director.content, "StatusLine")
	return status.text if status != null else ""


func status_color() -> Color:
	var status: Label = find_in(director.content, "StatusLine")
	return status.get_theme_color("font_color") if status != null else Color.BLACK


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
	await process_frame


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null


func count_buttons(text: String) -> int:
	var count := 0
	for node in director.find_children("*", "Button", true, false):
		if node.text == text:
			count += 1
	return count


func find_label(text: String) -> Label:
	for node in director.content.find_children("*", "Label", true, false):
		if node.text == text:
			return node
	return null


func find_label_part(text: String) -> Label:
	for node in director.content.find_children("*", "Label", true, false):
		if node.text.contains(text):
			return node
	return null


func find_node_named(node_name: String) -> Node:
	return director.content.find_child(node_name, true, false)


func find_in(parent: Node, node_name: String) -> Control:
	return parent.find_child(node_name, true, false) if is_instance_valid(parent) else null
