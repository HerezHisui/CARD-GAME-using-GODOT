extends SceneTree
## LAN Part E: Host LAN and Join LAN on the title screen (scripts/lan_title.gd).
## LAN_ENABLED is a const and stays false, so the title has no LAN buttons here. The test adds them
## with run_director.add_lan_buttons, the same call show_title makes when the flag is true.
## The other side of each link is a plain LanSession in its own subtree, as in lan_smoke.gd.

const LanSession = preload("res://scripts/lan_session.gd")
const LanTitle = preload("res://scripts/lan_title.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")

# Not the game port and not the lan_smoke port.
const TEST_PORT := 24693
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession on the other side
var other_joined := false
var other_lost := false
var other_refused := ""
var other_over := ""
var other_views := 0
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
	check_address_filter()
	check_title_without_lan()
	make_other()
	await check_real_buttons()
	await check_host_starts_match()
	await check_match_over()
	await check_peer_left()
	await check_version_refused()
	await check_client_flow()
	await check_client_refused()
	lan.session.close()
	other.close()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_title_smoke (%d checks)" % checks)
	quit(0)


func check_address_filter() -> void:
	var lines: Array = LanTitle.host_addresses(["127.0.0.1", "192.168.1.20", "169.254.3.4", "26.10.20.30",
		"fe80::1", "10.0.0.5", "26.1.1.1"])
	expect(lines == ["Radmin  26.10.20.30", "Radmin  26.1.1.1", "LAN  192.168.1.20", "LAN  10.0.0.5"],
		"address list: no 127.x, 169.254.x or IPv6, Radmin first")
	expect(LanTitle.host_addresses([]).is_empty(), "address list: empty stays empty")


# The real title, built the way the game builds it. No Host or Join button with the flag false.
func check_title_without_lan() -> void:
	expect(VersusMatch.LAN_ENABLED == false, "LAN_ENABLED is false in the repo")
	director.show_title()
	expect(find_button("Host LAN") == null, "title: no Host LAN button with the flag false")
	expect(find_button("Join LAN") == null, "title: no Join LAN button with the flag false")
	expect(not is_instance_valid(director.lan_title), "title: no lan_title node with the flag false")
	expect(find_button("Versus") != null, "title: the Versus button is there")


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
	other.match_over.connect(func(winner: String) -> void: other_over = winner)
	other.view_received.connect(func(_view: Dictionary) -> void: other_views += 1)
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))
	other.peer_left.connect(func(id: int) -> void: other_lefts.append(id))


# Real mouse input on the LAN buttons: Host LAN, its Cancel, then Join LAN and its Cancel.
func check_real_buttons() -> void:
	director.show_title()
	var title_screen: Control = director.content.get_child(0)
	director.add_lan_buttons(title_screen)
	lan = director.lan_title
	lan.port = TEST_PORT
	expect(is_instance_valid(lan), "buttons: lan_title made")
	var host_button := find_button("Host LAN")
	var join_button := find_button("Join LAN")
	expect(host_button != null and join_button != null, "buttons: Host LAN and Join LAN added")
	var menu: Node = title_screen.get_node("%Menu")
	var versus_index: int = title_screen.get_node("%VersusButton").get_index()
	expect(host_button.get_parent() == menu and host_button.get_index() == versus_index + 1,
		"buttons: Host LAN sits under Versus")
	expect(join_button.get_index() == versus_index + 2, "buttons: Join LAN sits under Host LAN")
	await frames(3)
	await click(host_button)
	expect(director.screen == "title_help" and lan.session.is_open() and lan.session.is_host,
		"buttons: Host LAN opens the host panel and listens")
	expect(find_label("Port %d" % TEST_PORT) != null, "host panel: shows the port")
	expect(find_label_part("Windows Firewall") != null, "host panel: shows the firewall line")
	await frames(3)
	await click(find_button("Cancel"))
	expect(not lan.session.is_open(), "host panel: Cancel closes the session")
	expect(director.screen == "title", "host panel: Cancel goes back to the title")
	title_screen = director.content.get_child(0)
	director.add_lan_buttons(title_screen)
	await frames(3)
	await click(find_button("Join LAN"))
	expect(director.screen == "title_help" and find_node_named("IpEdit") != null,
		"buttons: Join LAN opens the join panel with an IP field")
	await frames(3)
	await click(find_button("Cancel"))
	expect(director.screen == "title", "join panel: Cancel goes back to the title")


# Host starts a session, the other side joins, the Versus match starts with the fixed seats.
func check_host_starts_match() -> void:
	await host_and_join()
	expect(director.versus_match.running, "host: the Versus match started")
	expect(game.seat_prep == "local" and game.seat_disaster == "remote", "host: seats are local / remote")
	expect(game.lan_remote_disaster and game.disaster_is_human, "host: the Disaster is remote and human")
	expect(await wait_until(func() -> bool: return other_views > 0), "host: the client got a view")
	var prep_turn := [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]
	expect(await wait_until(func() -> bool: return game.phase in prep_turn),
		"host: no coin, the Preparedness turn starts")
	expect(game.player_first, "host: Preparedness goes first")
	expect(not game.versus_hand_hidden, "host: the Preparedness hand shows")


func check_match_over() -> void:
	director.battle_finished(true)
	expect(not director.versus_match.running, "match over: the host match ended")
	expect(await wait_until(func() -> bool: return other_over == "preparedness"), "match over: reaches the client")
	other.close()
	lan.session.close()
	await frames(5)


func check_peer_left() -> void:
	await host_and_join()
	expect(director.versus_match.running, "peer left: match running before")
	other.close()
	expect(await wait_until(func() -> bool: return not director.versus_match.running),
		"peer left: the host match ended")
	expect(director.screen == "result" and find_label("OPPONENT LEFT") != null, "peer left: host shows Opponent left")
	expect(not lan.session.is_open(), "peer left: the host closed the session")
	expect(not lan.in_match, "peer left: lan_title is out of the match")
	await frames(5)


func check_version_refused() -> void:
	director.show_title()
	lan.show_host()
	other_refused = ""
	other_lost = false
	other.build = "0|old build"
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, "version: join starts")
	expect(await wait_until(func() -> bool: return other_refused == "version"), "version: the client is refused")
	expect(await wait_until(func() -> bool: return other_lost), "version: the host drops the client")
	expect(not lan.in_match and not director.versus_match.running, "version: no match started")
	other.build = LanSession.build_string()
	other.close()
	lan.session.close()
	await frames(5)


# Join LAN against a plain host: real clicks on Connect, Esc, Leave match.
func check_client_flow() -> void:
	expect(other.host_game(TEST_PORT) == OK, "client: the other side hosts")
	other_joins.clear()
	other_lefts.clear()
	director.show_title()
	lan.show_join()
	var edit: LineEdit = find_node_named("IpEdit")
	edit.text = "127.0.0.1"
	await frames(3)
	await click(find_button("Connect"))
	expect(lan.last_ip == "127.0.0.1", "client: the IP is kept in memory")
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), "client: panel shows")
	expect(not director.visible, "client: the title is hidden")
	expect(await wait_until(func() -> bool: return other_joins.size() == 1), "client: the host accepted the build")
	other.send_match_over("disaster")
	expect(await wait_until(func() -> bool: return lan.client_panel.over_text != ""), "client: match_over shows")
	expect(lan.client_panel.header.text.contains("Disaster wins"), "client: the panel names the winner")
	await key(KEY_ESCAPE)
	expect(is_instance_valid(lan.esc_menu), "client: Esc opens the menu")
	await frames(3)
	await click(find_in(lan.esc_menu, "LeaveButton"))
	expect(await wait_until(func() -> bool: return director.screen == "title"), "client: Leave match goes to the title")
	expect(director.visible and not is_instance_valid(lan.client_layer), "client: the panel is gone")
	expect(not lan.session.is_open(), "client: the session is closed")
	expect(await wait_until(func() -> bool: return other_lefts.size() == 1), "client: the host saw the client leave")
	edit = null
	director.show_title()
	lan.show_join()
	edit = find_node_named("IpEdit")
	expect(edit.text == "127.0.0.1", "client: the join panel remembers the last IP")
	lan.session.close()
	director.show_title()


# The host has another build: the client shows Different game version.
func check_client_refused() -> void:
	other.build = "0|old build"
	director.show_title()
	lan.show_join()
	find_node_named("IpEdit").text = "127.0.0.1"
	lan.connect_to_host()
	expect(await wait_until(func() -> bool: return find_label("JOIN LAN") != null \
		and find_label_part("Different game version") != null), "refused: the client shows Different game version")
	expect(not is_instance_valid(lan.client_layer) and director.visible, "refused: back on a title screen")
	expect(not lan.session.is_open(), "refused: the client session is closed")
	other.build = LanSession.build_string()
	other.close()
	await frames(5)


func host_and_join() -> void:
	director.show_title()
	lan.show_host()
	other_joined = false
	other_views = 0
	other_over = ""
	expect(lan.session.is_open(), "join: host listens")
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, "join: client starts joining")
	expect(await wait_until(func() -> bool: return other_joined and lan.in_match), "join: host accepted the client")


# --- helpers ---

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


func key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null


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
