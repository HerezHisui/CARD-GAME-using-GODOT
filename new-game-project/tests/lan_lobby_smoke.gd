extends SceneTree
## LAN D2-d: the coin before a LAN match (scripts/lan_title.gd, lan_session.gd, game_3d_manager.resume_coin).
## The host is Player 1 and calls. The toss winner picks a side. Then the host plays Player 1's side
## and the client the other one. Four combinations: Player 1 or Player 2 wins, and picks either side.
## Part 1: the real host lan_title with a plain LanSession client, as in lan_title_smoke.gd.
## Part 2: the real client lan_title with a plain LanSession host that sends the coin events by hand.

const LanSession = preload("res://scripts/lan_session.gd")
const LanTitle = preload("res://scripts/lan_title.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24695
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var lan: Node  # the director's lan_title
var other: Node  # the plain LanSession on the other side
var other_joined := false
var other_over := ""
var other_views := 0
var other_events: Array = []  # [kind, data] from the host
var other_sides: Array = []  # host side: sides the client sent
var other_joins: Array = []


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
	await process_frame
	check_texts()
	make_other()
	director.show_title()
	director.add_lan_buttons(director.content.get_child(0))
	lan = director.lan_title
	lan.port = TEST_PORT
	lan.cfg_path = "user://test_lan_lobby_smoke.cfg"  # lobby step: never the real user://lan.cfg
	# The four combinations, each once with match_over and once with a disconnect.
	for ending in ["over", "left"]:
		await check_combo(true, "preparedness", ending)
		await check_combo(true, "disaster", ending)
		await check_combo(false, "preparedness", ending)
		await check_combo(false, "disaster", ending)
	await check_leave_during_coin()
	await check_leave_during_banner()
	await check_client("preparedness")
	await check_client("disaster")
	lan.session.close()
	other.close()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_lobby_smoke (%d checks)" % checks)
	quit(0)


func check_texts() -> void:
	expect(LanTitle.coin_texts({"stage": "calling"})[0] == "PLAYER 1 IS CALLING", "texts: calling")
	var tossed: Array = LanTitle.coin_texts({"stage": "tossed", "call": 1, "result": 0, "winner": 2})
	expect(tossed == ["HEADS", "Player 1 called Tails. Player 2 wins the toss."], "texts: tossed")
	expect(LanTitle.coin_texts({"stage": "choosing", "winner": 1})[0] == "PLAYER 1 IS CHOOSING", "texts: P1 chooses")
	expect(LanTitle.coin_texts({"stage": "choosing", "winner": 2})[0] == "PLAYER 2, PICK A SIDE", "texts: P2 picks")


func make_other() -> void:
	var holder := Node.new()
	holder.name = "Other"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	other = LanSession.new()
	other.name = "LanSession"
	holder.add_child(other)
	other.joined_host.connect(func() -> void: other_joined = true)
	other.match_over.connect(func(winner: String) -> void: other_over = winner)
	other.view_received.connect(func(_view: Dictionary) -> void: other_views += 1)
	other.event_received.connect(func(kind: String, data: Dictionary) -> void: other_events.append([kind, data]))
	other.side_requested.connect(func(side: String) -> void: other_sides.append(side))
	other.peer_joined.connect(func(id: int) -> void: other_joins.append(id))


static func other_side_of(side: String) -> String:
	return "disaster" if side == "preparedness" else "preparedness"


# --- Part 1: host ---

func check_combo(host_wins: bool, winner_side: String, ending: String) -> void:
	var name := "P%d wins, picks %s, %s" % [1 if host_wins else 2, winner_side, ending]
	await host_and_join()
	var versus: Node = director.versus_match
	expect(await wait_until(coin_screen_ready), name + ": the host coin screen shows")
	expect(await wait_until(func() -> bool: return last_coin_stage() == "calling"),
		name + ": the client hears Player 1 is calling")
	# Nothing works for the client during the coin.
	other.request_action({"kind": "end"})
	expect(await wait_until(func() -> bool: return has_event("reject", "lobby")), name + ": an action is refused")
	# Real click on Heads or Tails on the host.
	var call: int = game.coin_result if host_wins else 1 - game.coin_result
	await frames(3)
	await click(game.presentation.choice_buttons[call])
	expect(await wait_until(func() -> bool: return versus.prematch_active), name + ": the side pick starts")
	expect(versus.coin_winner == (1 if host_wins else 2), name + ": the right player wins the toss")
	expect(await wait_until(func() -> bool: return last_coin_stage() == "choosing"),
		name + ": the client hears who is choosing")
	expect(int(last_coin().get("winner", 0)) == versus.coin_winner, name + ": the client knows the winner")
	expect(other_views == 0, name + ": no view during the coin")
	var buttons: Array = game.presentation.side_buttons
	var index := 0 if winner_side == "preparedness" else 1
	await frames(3)
	if host_wins:
		expect(not buttons[0].disabled and not buttons[1].disabled, name + ": the host side buttons are on")
		other.request_side(other_side_of(winner_side))
		await frames(10)
		expect(versus.prematch_active, name + ": a side from the client is ignored when Player 1 won")
		await click(buttons[index])
	else:
		expect(buttons[0].disabled and buttons[1].disabled, name + ": the host side buttons are off")
		expect(side_hint_has("Player 2 is choosing"), name + ": the host says Player 2 is choosing")
		await click(buttons[index])
		lan.session.pick_side(winner_side)
		other.request_side("spectator")
		await frames(10)
		expect(versus.prematch_active, name + ": the host, a local call and a bad side cannot pick")
		other.request_side(winner_side)
	expect(await wait_until(func() -> bool: return not versus.prematch_active), name + ": the side is picked")
	var host_side: String = winner_side if host_wins else other_side_of(winner_side)
	var client_side := other_side_of(host_side)
	expect(versus.player1_side == host_side and versus.player2_side == client_side, name + ": sides assigned")
	var host_prep := host_side == "preparedness"
	expect(game.seat_prep == ("local" if host_prep else "remote"), name + ": seat_prep")
	expect(game.seat_disaster == ("remote" if host_prep else "local"), name + ": seat_disaster")
	expect(game.player_first == (winner_side == "preparedness"), name + ": the picked side goes first")
	expect(await wait_until(func() -> bool: return has_event("seat", client_side)), name + ": the client hears its side")
	expect(lan.session.seat_of(lan.remote_id) == client_side, name + ": seat_client from the result")
	expect(not lan.session.lobby, name + ": the lobby is over")
	expect(await wait_until(func() -> bool: return other_views > 0), name + ": the client gets a view")
	if client_side == "preparedness":
		expect(other.last_view.get("side", "") == "preparedness" and not other.last_view.has("disaster_hand"),
			name + ": the client view is the Preparedness view")
	else:
		expect(other.last_view.has("disaster_hand") and not other.last_view.has("prep_hand"),
			name + ": the client view is the Disaster view")
	await frames(30)
	if host_prep:
		expect(not game.versus_hand_hidden and game.hand_container.visible, name + ": the host shows its hand")
	else:
		expect(game.versus_hand_hidden and not game.hand_container.visible,
			name + ": the host-as-Disaster screen never shows the Preparedness hand")
	if ending == "over":
		director.battle_finished(true)
		expect(not versus.running, name + ": the host match ended")
		expect(await wait_until(func() -> bool: return other_over == "preparedness"),
			name + ": match_over reaches the client")
		other.close()
		lan.session.close()
	else:
		other.close()
		expect(await wait_until(func() -> bool: return not versus.running), name + ": the host match ended on leave")
		expect(director.screen == "result" and find_label("OPPONENT LEFT") != null, name + ": the host shows Opponent left")
		expect(not lan.session.is_open() and not lan.in_match, name + ": the host closed the session")
	await frames(5)


# The client leaves while the toss winner picks a side: the side screen goes away.
func check_leave_during_coin() -> void:
	await host_and_join()
	var versus: Node = director.versus_match
	expect(await wait_until(coin_screen_ready), "leave in coin: the coin screen shows")
	await frames(3)
	await click(game.presentation.choice_buttons[1 - game.coin_result])
	expect(await wait_until(func() -> bool: return versus.prematch_active), "leave in coin: Player 2 is choosing")
	other.close()
	expect(await wait_until(func() -> bool: return not versus.running), "leave in coin: the match ended")
	await frames(5)
	expect(director.screen == "result" and find_label("OPPONENT LEFT") != null, "leave in coin: Opponent left shows")
	expect(not is_instance_valid(game.presentation.side_root), "leave in coin: the side screen is gone")
	expect(not versus.prematch_active, "leave in coin: no side wait is left")
	await frames(5)


# The client leaves during the opening banner: no coin screen starts after that.
func check_leave_during_banner() -> void:
	await host_and_join()
	var versus: Node = director.versus_match
	other.close()
	expect(await wait_until(func() -> bool: return not versus.running), "leave in banner: the match ended")
	await frames(120)
	expect(director.screen == "result", "leave in banner: the result screen stays")
	expect(not is_instance_valid(game.presentation.coin_root), "leave in banner: no coin screen starts")
	await frames(5)


# --- Part 2: client ---

# Real Join, then the plain host sends the coin events. A real click on the client's side button.
func check_client(seat: String) -> void:
	var name := "client " + seat
	expect(other.host_game(TEST_PORT) == OK, name + ": the other side hosts")
	other_joins.clear()
	other_sides.clear()
	director.show_title()
	lan.show_join()
	find_node_named("IpEdit").text = "127.0.0.1"
	await frames(3)
	await click(find_button("Connect"))
	expect(await wait_until(func() -> bool: return other_joins.size() == 1), name + ": the host accepted the client")
	# Lobby step: the client waits in the room until the host sends "start".
	expect(await wait_until(func() -> bool: return lan.room == "client"), name + ": waits in the room")
	other.send_event("start", {})
	expect(await wait_until(func() -> bool: return is_instance_valid(lan.client_panel)), name + ": panel after start")
	expect(is_instance_valid(lan.client_panel), name + ": the client panel shows")
	other.lobby = true
	other.send_event("coin", {"stage": "calling"})
	expect(await wait_until(func() -> bool: return coin_title() == "PLAYER 1 IS CALLING"), name + ": Player 1 is calling")
	other.send_event("coin", {"stage": "tossed", "call": 0, "result": 1, "winner": 2})
	expect(await wait_until(func() -> bool: return coin_title() == "TAILS"), name + ": the toss result shows")
	expect(coin_hint() == "Player 1 called Heads. Player 2 wins the toss.", name + ": the toss hint")
	if seat == "disaster":
		other.send_event("coin", {"stage": "choosing", "call": 0, "result": 1, "winner": 1})
		expect(await wait_until(func() -> bool: return coin_title() == "PLAYER 1 IS CHOOSING"),
			name + ": the waiting laptop says Player 1 is choosing")
		expect(find_in(lan.coin_page, "SideButtons") == null, name + ": no side buttons while Player 1 chooses")
	other.send_event("coin", {"stage": "choosing", "call": 0, "result": 1, "winner": 2})
	expect(await wait_until(func() -> bool: return coin_title() == "PLAYER 2, PICK A SIDE"), name + ": Player 2 picks")
	var button := find_in(lan.coin_page, seat.capitalize() + "Button")
	expect(button != null, name + ": the side button is there")
	await frames(3)
	await click(button)
	expect(await wait_until(func() -> bool: return other_sides == [seat]), name + ": a real click sends the side")
	await click(button)
	await frames(10)
	expect(other_sides == [seat], name + ": a second click sends nothing")
	other.lobby = false
	other.seat_client(seat)
	other.send_event("seat", {"side": seat})
	expect(await wait_until(func() -> bool: return lan.client_side == seat and not is_instance_valid(lan.coin_page)),
		name + ": the seat closes the coin page")
	if seat == "preparedness":
		expect(lan.client_panel is LanPrepPanel and lan.session.panel == lan.client_panel,
			name + ": the Preparedness panel shows")
	else:
		expect(lan.client_panel is LanClientPanel, name + ": the Disaster panel stays")
	other.send_match_over("disaster")
	expect(await wait_until(func() -> bool: return lan.client_panel.over_text != ""), name + ": match_over shows")
	await key(KEY_ESCAPE)
	expect(is_instance_valid(lan.esc_menu), name + ": Esc opens the menu")
	await frames(3)
	await click(find_in(lan.esc_menu, "LeaveButton"))
	expect(await wait_until(func() -> bool: return director.screen == "title"), name + ": Leave match goes to the title")
	expect(not lan.session.is_open(), name + ": the client session is closed")
	other.close()
	await frames(5)


# --- helpers ---

func host_and_join() -> void:
	director.show_title()
	lan.show_host()
	other_joined = false
	other_views = 0
	other_over = ""
	other_events.clear()
	expect(lan.session.is_open(), "join: host listens")
	expect(other.join_game("127.0.0.1", TEST_PORT) == OK, "join: client starts joining")
	# Lobby step: the join no longer starts the match. The host presses Start match.
	expect(await wait_until(func() -> bool: return other_joined and lan.room_connected()),
		"join: host accepted the client")
	lan.start_match()
	expect(lan.in_match, "join: Start match starts the match")


func coin_screen_ready() -> bool:
	return director.screen == "coin" and game.presentation.blocking and not game.presentation.coin_busy \
		and is_instance_valid(game.presentation.coin_root) and game.presentation.choice_buttons.size() == 2


func last_coin() -> Dictionary:
	for i in range(other_events.size() - 1, -1, -1):
		if other_events[i][0] == "coin":
			return other_events[i][1]
	return {}


func last_coin_stage() -> String:
	return str(last_coin().get("stage", ""))


# An event of this kind came. For "reject" the value is the reason, for "seat" the side.
func has_event(kind: String, value: String) -> bool:
	for event in other_events:
		if event[0] != kind:
			continue
		if str(event[1].get("reason", event[1].get("side", ""))) == value:
			return true
	return false


func side_hint_has(text: String) -> bool:
	var side_root: Node = game.presentation.side_root
	if not is_instance_valid(side_root):
		return false
	for node in side_root.find_children("*", "Label", true, false):
		if node.text.contains(text):
			return true
	return false


func coin_title() -> String:
	var node := find_in(lan.coin_page, "CoinTitle")
	return node.text if node != null else ""


func coin_hint() -> String:
	var node := find_in(lan.coin_page, "CoinHint")
	return node.text if node != null else ""


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


func find_node_named(node_name: String) -> Node:
	return director.content.find_child(node_name, true, false)


func find_in(parent: Node, node_name: String) -> Control:
	return parent.find_child(node_name, true, false) if is_instance_valid(parent) else null
