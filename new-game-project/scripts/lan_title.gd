extends Node
## LAN Part E: Host LAN and Join LAN from the title screen. Child of run_director, made once.
## Only made when VersusMatch.LAN_ENABLED is true. Sides are fixed for now:
## the host plays Preparedness, the client plays the Disaster.
## Later (D2-b..d) a coin result can pass other seats to start_lan_match.
## D2-d: the sides are no longer fixed. The host is Player 1 and calls the coin, the toss winner picks
## a side, then the host plays Player 1's side and the client the other one.
## Lobby step: LAN Versus opens a hub (Host a game / Join a game). Both players wait in a room
## that shows who is connected. Only the host's Start match begins the match.

const LanSession = preload("res://scripts/lan_session.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
const VersusDecks = preload("res://scripts/versus_decks.gd")
const DeckBuilder = preload("res://scripts/deck_builder.gd")
const UI = preload("res://scripts/ui_theme.gd")

var director: Node
var game: Node
var port := LanSession.PORT  # a test may use another port
var link: Node  # holds the session, with its own multiplayer API
var session: Node
var last_ip := ""  # the last IP typed on Join, kept in memory only
var remote_id := 0  # host: the client id that plays the Disaster
var in_match := false  # host: a LAN match is running
var ended := false  # client: a message already replaced the client panel
var match_over_seen := false  # client: the host said who won
var status_label: Label
var ip_edit: LineEdit
var client_layer: CanvasLayer
var client_panel: Control
var client_cover: ColorRect  # client: the opaque cover over the idle game
var board_3d: Node  # client: the 3D table mirror (LAN_BOARD_3D)
var esc_menu: Control
var coin_stage := ""  # host: the last coin stage sent to the client
var coin_page: Control  # client: the coin screen over the panel, until the host seats this client
var client_side := ""  # client: the side the host gave this client, "" during the coin
# Deck builder Part 3.
const DECK_NOTE := "Your deck was not valid. You play the Standard deck."
const MAX_PILE := 40  # longest pile the host reads from the client, before validate
var deck_step_sent := false  # host: "deck_step" went out for this step
var deck_page: Control  # client: Standard or Customize, over the coin page, until the seat
var deck_builder: Control  # client: the builder inside the deck page
var deck_side := ""  # client: the side of the deck step

# Lobby step: the room before the match. Not session.lobby, which means "the coin is running".
const PING_EVERY := 2.0  # seconds between pings in a room
var cfg_path := "user://lan.cfg"  # the last IP typed on Join; a test uses a temporary file
var room := ""  # "host" or "client" while a room shows, "" otherwise
var ping_ms := -1  # the last ping in a room, -1 when none yet
var ping_wait := 0.0
var room_status: Label  # the Connected / Waiting / Disconnected line at the top of a room
var player1_row: Label  # client room: the host's row
var player2_row: Label  # host room: the client's row
var start_button: Button  # host room


func setup(owner_director: Node) -> void:
	director = owner_director
	game = director.game


# The scene reloads on Back to title. Close the link so the port is free again.
func _exit_tree() -> void:
	if session != null and session.is_open():
		session.close()


## The host's IPv4 addresses for the panel. No 127.x or 169.254.x. Radmin (26.x) first.
static func host_addresses(addresses: Array) -> Array:
	var radmin: Array = []
	var lan: Array = []
	for address in addresses:
		var text := str(address)
		# IPv4 only: an IPv6 address has a colon.
		if not text.is_valid_ip_address() or ":" in text:
			continue
		if text.begins_with("127.") or text.begins_with("169.254."):
			continue
		if text.begins_with("26."):
			radmin.append("Radmin  " + text)
		else:
			lan.append("LAN  " + text)
	return radmin + lan


# One session for this title, under its own multiplayer API, so the RPC path is "LanSession" on both computers.
func _ensure_session() -> void:
	if session != null:
		return
	link = Node.new()
	link.name = "LanLink"
	add_child(link)
	get_tree().set_multiplayer(SceneMultiplayer.new(), link.get_path())
	session = LanSession.new()
	session.name = "LanSession"
	link.add_child(session)
	session.peer_joined.connect(_on_peer_joined)
	session.peer_left.connect(_on_peer_left)
	session.joined_host.connect(_on_joined_host)
	session.join_failed.connect(_on_join_failed)
	session.host_lost.connect(_on_host_lost)
	session.join_refused.connect(_on_join_refused)
	session.match_over.connect(_on_match_over)
	session.side_requested.connect(_on_side_requested)
	session.deck_requested.connect(_on_deck_requested)
	session.event_received.connect(_on_event)
	session.pong_received.connect(_on_pong)


# --- Lobby hub and rooms ---

## The LAN lobby hub: Host a game, Join a game, Back to the title.
func show_lobby() -> void:
	room = ""
	if session != null and session.is_open():
		session.close()
	director.reset_panel("LAN LOBBY", "Host a game, or join a game another player hosts.", "title_help")
	var box: VBoxContainer = director.content
	var status: Label = director.label("Not connected", 18, UI.MUTED)
	status.name = "StatusLine"
	box.add_child(status)
	director.button("Host a game", show_host, box).name = "HostButton"
	director.button("Join a game", show_join, box).name = "JoinButton"
	director.button("Back", director.show_title, box).name = "BackButton"


# The one-line status at the top of a room.
func _add_room_status(box: VBoxContainer) -> void:
	room_status = director.label("", 20, UI.AMBER)
	room_status.name = "StatusLine"
	box.add_child(room_status)


# A room row label, for example "PLAYER 2   Waiting for a player...".
func _add_row(box: VBoxContainer, row_name: String, text: String) -> Label:
	var row: Label = director.label(text, 18)
	row.name = row_name
	box.add_child(row)
	return row


# Host: Player 2 has joined and has the same build.
func room_connected() -> bool:
	if room == "host":
		return remote_id != 0
	return room == "client"


# Update the status line, the rows and the Start button. Text changes only when it differs.
func _refresh_room() -> void:
	var connected := room_connected()
	var text := "Connected" if connected else "Waiting"
	var color: Color = UI.GOLD if connected else UI.AMBER
	if room == "":
		text = "Disconnected"
		color = UI.DANGER
	var ping_text := "" if ping_ms < 0 else "  %d ms" % ping_ms
	if is_instance_valid(room_status) and room_status.text != text:
		room_status.text = text
		room_status.add_theme_color_override("font_color", color)
	if room == "host" and is_instance_valid(player2_row):
		var row_text := "PLAYER 2   Connected" + ping_text if connected else "PLAYER 2   Waiting for a player..."
		if player2_row.text != row_text:
			player2_row.text = row_text
	if is_instance_valid(start_button):
		start_button.disabled = room != "host" or not connected
	if room == "client" and is_instance_valid(player1_row):
		var host_text := "PLAYER 1 (host, %s)   Connected%s" % [last_ip, ping_text]
		if player1_row.text != host_text:
			player1_row.text = host_text


# In a room, ping the other side every 2 seconds. Counted with the _process delta, no timer.
func _room_ping(delta: float) -> void:
	if room == "" or session == null or not session.is_open():
		return
	ping_wait += delta
	if ping_wait < PING_EVERY:
		return
	ping_wait = 0.0
	session.send_ping(Time.get_ticks_msec())


# The ping number is the send time, so the answer gives the round trip in ms.
func _on_pong(number: int) -> void:
	if room == "":
		return
	ping_ms = maxi(0, Time.get_ticks_msec() - number)
	_refresh_room()


## The last IP typed on Join, or "" if the file is missing or broken.
static func read_last_ip(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	var ip := str(cfg.get_value("join", "last_ip", ""))
	return ip if ip.is_valid_ip_address() else ""


static func save_last_ip(path: String, ip: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("join", "last_ip", ip)
	cfg.save(path)


# --- Host ---

func show_host() -> void:
	_ensure_session()
	in_match = false
	remote_id = 0
	ping_ms = -1
	var error: Error = session.host_game(port)
	room = "host" if error == OK else ""
	director.reset_panel("LAN ROOM", "You host. Start the match when Player 2 is connected.", "title_help")
	var box: VBoxContainer = director.content
	_add_room_status(box)
	start_button = null
	if error != OK:
		box.add_child(director.label("Could not open port %d (error %d)." % [port, error], 18, UI.TEXT, true))
	else:
		_add_row(box, "Player1Row", "PLAYER 1 (you, host)   Ready")
		player2_row = _add_row(box, "Player2Row", "")
		box.add_child(director.label("Port %d" % port, 18))
		var lines := host_addresses(Array(IP.get_local_addresses()))
		if lines.is_empty():
			lines = ["No network address found"]
		for line in lines:
			box.add_child(director.label(line, 18))
		var firewall := "Allow UDP %d in Windows Firewall (Private and Radmin networks)." % port
		box.add_child(director.label(firewall, 16, UI.MUTED, true))
		start_button = director.button("Start match", start_match, box)
		start_button.name = "StartButton"
	director.button("Cancel", cancel_host, box).name = "CancelButton"
	_refresh_room()


# Lobby step: Cancel goes back to the hub, not the title.
func cancel_host() -> void:
	room = ""
	session.close()
	show_lobby()


# Lobby step: a join no longer starts the match. The room shows Player 2 and turns Start match on.
func _on_peer_joined(id: int) -> void:
	if not session.is_host or in_match:
		return
	remote_id = id
	ping_ms = -1
	ping_wait = PING_EVERY  # ping at once
	_refresh_room()


## Host: the Start match button. The only way a LAN match begins.
## The client gets "start" first, so its panel exists before the first coin event (RPCs keep their order).
func start_match() -> void:
	if room != "host" or remote_id == 0 or in_match:
		return
	session.send_event("start", {})
	start_lan_match("local", "remote")


## Starts the Versus match with these seats. Part E: host = "local" Preparedness, "remote" Disaster.
## D2-d: these seats only last through the coin. The side pick sets the real seats.
func start_lan_match(prep_seat: String, disaster_seat: String) -> void:
	room = ""
	in_match = true
	coin_stage = ""
	session.lobby = true
	game.set_seats(prep_seat, disaster_seat)
	director.start_versus_match()
	# Part 3: the client sends its own deck in the deck step.
	director.versus_match.remote_deck_choice = true
	deck_step_sent = false
	session.game = game
	session.send_view()


func _on_peer_left(id: int) -> void:
	if not session.is_host or id != remote_id:
		return
	# Lobby step: Player 2 left the room. Wait for another player; the port stays open.
	if room == "host":
		remote_id = 0
		ping_ms = -1
		_refresh_room()
		return
	if not in_match:
		return
	in_match = false
	remote_id = 0
	session.game = null
	session.close()
	director.versus_match.abort("OPPONENT LEFT", "The other player left the match.")


# Host: during the coin, tell the client what the host screen shows. After the side pick, seat the client.
# Lobby step: first the room ping, on both sides.
func _process(delta: float) -> void:
	_room_ping(delta)
	if session == null or not session.is_host or not in_match or not session.lobby:
		return
	var versus: Node = director.versus_match
	# Deck builder Part 2: no seat and no first view before the deck step and the re-deal are done.
	# Part 3: the client hears the step once, with its side only. Never the host's deck.
	if versus.deck_step_active:
		if not deck_step_sent:
			deck_step_sent = true
			session.send_event("deck_step", {"side": versus.player2_side})
		return
	deck_step_sent = false
	if versus.player1_side != "":
		_seat_from_coin()
		return
	var stage := ""
	var data := {}
	if versus.prematch_active:
		stage = "choosing"
		data = {"call": versus.coin_call, "result": game.coin_result, "winner": versus.coin_winner}
	elif director.screen == "coin" and game.coin_pick < 0:
		stage = "calling"
	elif director.screen == "coin":
		var toss_winner := VersusMatch.resolve_winner(game.coin_pick, game.coin_result)
		stage = "tossed"
		data = {"call": game.coin_pick, "result": game.coin_result, "winner": toss_winner}
	if stage == "" or stage == coin_stage:
		return
	coin_stage = stage
	data.stage = stage
	session.send_event("coin", data)


# Host: the client plays Player 2's side. game_3d_manager already set the host seats.
func _seat_from_coin() -> void:
	var side: String = director.versus_match.player2_side
	session.seat_client(side)
	session.lobby = false
	session.send_event("seat", {"side": side})
	session.send_view()


# Host: the client won the toss and sent its side. Ignored unless Player 2 is choosing now.
func _on_side_requested(side: String) -> void:
	var versus: Node = director.versus_match
	if not in_match or not versus.prematch_active or versus.coin_winner != 2:
		return
	versus.choose_side(side)


## True when a deck from the network has the right shape: a Dictionary whose "main", "evolutions" and
## "tactics" are each missing or an Array of Strings, at most MAX_PILE long. validate() checks the rest.
static func deck_shape_ok(deck) -> bool:
	if not deck is Dictionary:
		return false
	for key in ["main", "evolutions", "tactics"]:
		if not deck.has(key):
			continue
		var pile = deck[key]
		if not pile is Array or pile.size() > MAX_PILE:
			return false
		for id in pile:
			if not id is String:
				return false
	return true


# Host: the client sent its deck. Ignored outside the step or after the client already chose.
# A bad deck means the Standard deck, and the client hears why.
func _on_deck_requested(deck) -> void:
	var versus: Node = director.versus_match
	if not in_match or not versus.deck_step_active:
		return
	var side: String = versus.player2_side
	if not versus.deck_ready.has(side) or versus.deck_ready[side]:
		return
	var ok := deck_shape_ok(deck)
	if ok and not deck.is_empty():
		ok = VersusDecks.validate(side, deck).ok
	if not ok:
		versus.choose_deck(side, {})
		session.send_event("deck_note", {"text": DECK_NOTE})
		return
	versus.choose_deck(side, deck)


## run_director.battle_finished calls this when a Versus match ends.
func match_finished(winner: String) -> void:
	if not in_match:
		return
	in_match = false
	session.send_match_over(winner)


# --- Client ---

func show_join() -> void:
	_ensure_session()
	ended = false
	room = ""
	# Lobby step: the last IP comes from user://lan.cfg the first time.
	if last_ip == "":
		last_ip = read_last_ip(cfg_path)
	director.reset_panel("JOIN LAN", "Type the host's IP address.", "title_help")
	var box: VBoxContainer = director.content
	ip_edit = LineEdit.new()
	ip_edit.name = "IpEdit"
	ip_edit.text = last_ip
	ip_edit.placeholder_text = "for example 26.12.34.56"
	ip_edit.custom_minimum_size = Vector2(320, 40)
	ip_edit.text_submitted.connect(func(_text: String) -> void: connect_to_host())
	box.add_child(ip_edit)
	status_label = director.label("", 18, UI.MUTED, true)
	box.add_child(status_label)
	director.button("Connect", connect_to_host, box).name = "ConnectButton"
	director.button("Cancel", cancel_join, box).name = "CancelButton"


func connect_to_host() -> void:
	last_ip = ip_edit.text.strip_edges()
	if not last_ip.is_valid_ip_address():
		status_label.text = "Type an IP address, for example 26.12.34.56."
		return
	save_last_ip(cfg_path, last_ip)
	ended = false
	match_over_seen = false
	client_side = ""
	session.last_view = {}
	status_label.text = "Connecting..."
	if session.join_game(last_ip, port) != OK:
		status_label.text = "Could not connect"


# Lobby step: Cancel goes back to the hub, not the title.
func cancel_join() -> void:
	session.close()
	show_lobby()


# Lobby step: connected. Wait in the client room until the host presses Start match.
func _on_joined_host() -> void:
	if session.is_host:
		return
	if is_instance_valid(status_label):
		status_label.text = "Connected"
	_show_client_room()


func _show_client_room() -> void:
	room = "client"
	ping_ms = -1
	ping_wait = PING_EVERY  # ping at once
	director.reset_panel("LAN ROOM", "You joined. The host starts the match.", "title_help")
	var box: VBoxContainer = director.content
	_add_room_status(box)
	start_button = null
	player1_row = _add_row(box, "Player1Row", "")
	_add_row(box, "Player2Row", "PLAYER 2 (you)   Ready")
	box.add_child(director.label("Waiting for the host to start...", 18, UI.MUTED))
	director.button("Leave", leave_room, box).name = "LeaveButton"
	_refresh_room()


# Client room: Leave closes the link and goes back to the hub.
func leave_room() -> void:
	room = ""
	ended = true
	session.close()
	show_lobby()


# The Disaster board fills the screen. The title stays hidden under it.
func _show_client_panel() -> void:
	_close_client_panel()
	client_layer = CanvasLayer.new()
	client_layer.layer = director.layer + 10
	add_child(client_layer)
	var background := ColorRect.new()
	background.color = UI.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	client_layer.add_child(background)
	client_cover = background
	client_panel = LanClientPanel.new()
	client_layer.add_child(client_panel)
	client_panel.setup_evolutions(director)
	client_panel.back_pressed.connect(back_to_title)
	session.attach_panel(client_panel)
	_mount_board_3d("disaster")
	director.visible = false


# LAN_BOARD_3D: the 3D table takes over once the first view arrives. The 2D panel stays under it, hidden.
func _mount_board_3d(side: String) -> void:
	_free_board_3d()
	if not VersusMatch.LAN_BOARD_3D:
		return
	board_3d = LanBoard3D.new()
	client_layer.add_child(board_3d)
	board_3d.setup(game, director, session, client_panel, side, client_cover)


func _free_board_3d() -> void:
	if is_instance_valid(board_3d):
		board_3d.queue_free()
	board_3d = null


func _close_client_panel() -> void:
	_free_board_3d()
	if is_instance_valid(client_layer):
		client_layer.queue_free()
	client_layer = null
	client_panel = null
	client_cover = null
	esc_menu = null
	coin_page = null
	deck_page = null
	deck_builder = null
	director.visible = true


# Esc on the client panel opens a small menu with Leave match.
func _input(event: InputEvent) -> void:
	if not is_instance_valid(client_layer):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		toggle_esc_menu()


func toggle_esc_menu() -> void:
	if is_instance_valid(esc_menu):
		esc_menu.queue_free()
		esc_menu = null
		return
	esc_menu = PanelContainer.new()
	esc_menu.name = "EscMenu"
	esc_menu.set_anchors_preset(Control.PRESET_CENTER)
	client_layer.add_child(esc_menu)
	var box := VBoxContainer.new()
	esc_menu.add_child(box)
	box.add_child(director.label("MENU", 22, UI.GOLD))
	director.button("Leave match", leave_match, box).name = "LeaveButton"
	director.button("Keep playing", toggle_esc_menu, box).name = "KeepButton"


func leave_match() -> void:
	ended = true
	await session.leave()
	back_to_title()


func back_to_title() -> void:
	ended = true
	session.close()
	_close_client_panel()
	director.show_title()


func _on_join_failed() -> void:
	_client_message("Could not connect")


func _on_join_refused(reason: String) -> void:
	_client_message("Different game version" if reason == "version" else "The host refused: " + reason)


func _on_host_lost() -> void:
	# After the match ended the panel already says who won; it keeps its Back to title button.
	if match_over_seen:
		session.close()
		return
	# Lobby step: the host left before Start match. Back to the hub, not the title.
	if room == "client":
		_client_message("The host left.", true)
		return
	_client_message("The host left the match.")


func _on_match_over(winner: String) -> void:
	match_over_seen = true
	if is_instance_valid(client_panel):
		client_panel.show_match_over(winner)


# --- Client: coin and seat (D2-d) ---

## The coin screen text on the client, [title, hint]. The client is always Player 2.
static func coin_texts(data: Dictionary) -> Array:
	var call_text := "Heads" if int(data.get("call", 0)) == 0 else "Tails"
	var winner := int(data.get("winner", 0))
	match str(data.get("stage", "")):
		"calling":
			return ["PLAYER 1 IS CALLING", "Player 1 calls Heads or Tails. The toss winner picks a side."]
		"tossed":
			var result_text := "HEADS" if int(data.get("result", 0)) == 0 else "TAILS"
			return [result_text, "Player 1 called %s. Player %d wins the toss." % [call_text, winner]]
		"choosing":
			if winner == 2:
				return ["PLAYER 2, PICK A SIDE", "You won the toss. The side you pick takes the first turn."]
			return ["PLAYER 1 IS CHOOSING", "Player 1 won the toss and is picking a side."]
	return ["", ""]


func _on_event(kind: String, data: Dictionary) -> void:
	if session.is_host:
		return
	# Lobby step: the host pressed Start match. The panel is made here, before any coin event arrives.
	if kind == "start":
		if room == "client":
			room = ""
			_show_client_panel()
		return
	if not is_instance_valid(client_layer):
		return
	if kind == "coin" and client_side == "":
		_show_coin_page(data)
	if kind == "deck_step" and client_side == "":
		_show_deck_page(str(data.get("side", "")))
	if kind == "deck_note" and is_instance_valid(deck_page):
		_deck_hint().text = str(data.get("text", ""))
	if kind == "seat":
		_on_seat(str(data.get("side", "")))


func _show_coin_page(data: Dictionary) -> void:
	_close_coin_page()
	coin_page = ColorRect.new()
	coin_page.name = "CoinPage"
	coin_page.color = UI.BACKGROUND
	coin_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	client_layer.add_child(coin_page)
	# The Esc menu stays on top.
	if is_instance_valid(esc_menu):
		client_layer.move_child(esc_menu, -1)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	coin_page.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var texts := coin_texts(data)
	var title: Label = director.label(texts[0], 34, UI.GOLD)
	title.name = "CoinTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint: Label = director.label(texts[1], 19)
	hint.name = "CoinHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	if str(data.get("stage", "")) != "choosing" or int(data.get("winner", 0)) != 2:
		return
	var buttons := HBoxContainer.new()
	buttons.name = "SideButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	for side in ["preparedness", "disaster"]:
		var button: Button = director.button(side.capitalize(), _pick_side.bind(side), buttons)
		button.name = side.capitalize() + "Button"
		button.custom_minimum_size = Vector2(240, 56)


# One click sends the side. The buttons turn off so a second click does nothing.
func _pick_side(side: String) -> void:
	if not is_instance_valid(coin_page):
		return
	var buttons: Node = coin_page.find_child("SideButtons", true, false)
	for button in buttons.get_children():
		if button.disabled:
			return
		button.disabled = true
	session.request_side(side)


func _close_coin_page() -> void:
	if is_instance_valid(coin_page):
		coin_page.queue_free()
	coin_page = null
	# Part 3: the seat also ends the deck step.
	_close_deck_page()


# --- Client: deck step (deck builder Part 3) ---

# The deck page over the coin page: Standard deck or Customize deck for this client's side.
func _show_deck_page(side: String) -> void:
	_close_deck_page()
	deck_side = side
	deck_page = ColorRect.new()
	deck_page.name = "DeckPage"
	deck_page.color = UI.BACKGROUND
	deck_page.theme = director.root.theme
	deck_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_page.mouse_filter = Control.MOUSE_FILTER_STOP
	client_layer.add_child(deck_page)
	# The Esc menu stays on top.
	if is_instance_valid(esc_menu):
		client_layer.move_child(esc_menu, -1)
	var center := CenterContainer.new()
	center.name = "DeckCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	deck_page.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title: Label = director.label("PLAYER 2: %s DECK" % side.to_upper(), 34, UI.GOLD)
	title.name = "DeckTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint: Label = director.label("Play the Standard deck, or build your own.", 19)
	hint.name = "DeckHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.name = "DeckButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	var standard: Button = director.button("Standard deck", _pick_standard_deck, buttons)
	standard.name = "StandardButton"
	var custom: Button = director.button("Customize deck", _open_deck_builder, buttons)
	custom.name = "CustomizeButton"
	for button: Button in [standard, custom]:
		button.custom_minimum_size = Vector2(240, 56)


func _deck_hint() -> Label:
	return deck_page.find_child("DeckHint", true, false)


func _deck_buttons_off() -> bool:
	var buttons: Node = deck_page.find_child("DeckButtons", true, false)
	return buttons.get_child(0).disabled


func _pick_standard_deck() -> void:
	if not is_instance_valid(deck_page) or _deck_buttons_off():
		return
	_send_deck({})


# Customize: the builder opens on the saved custom deck (Standard the first time).
func _open_deck_builder() -> void:
	if not is_instance_valid(deck_page) or is_instance_valid(deck_builder) or _deck_buttons_off():
		return
	deck_page.find_child("DeckCenter", true, false).hide()
	deck_builder = DeckBuilder.new()
	deck_builder.name = "DeckBuilder"
	deck_builder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deck_page.add_child(deck_builder)
	deck_builder.setup(deck_side, VersusDecks.load_custom(deck_side), director)
	deck_builder.done.connect(_on_deck_builder_done)
	deck_builder.back.connect(_close_deck_builder)


# Done saves the deck on this computer, then sends it to the host.
func _on_deck_builder_done(deck: Dictionary) -> void:
	VersusDecks.save_custom(deck_side, deck)
	_close_deck_builder()
	_send_deck(deck)


# Back: the builder closes and the two buttons show again.
func _close_deck_builder() -> void:
	if is_instance_valid(deck_builder):
		deck_builder.hide()
		deck_builder.queue_free()
	deck_builder = null
	if is_instance_valid(deck_page):
		deck_page.find_child("DeckCenter", true, false).show()


# One choice per step. The buttons turn off and the page waits for the seat.
func _send_deck(deck: Dictionary) -> void:
	for button in deck_page.find_child("DeckButtons", true, false).get_children():
		button.disabled = true
	_deck_hint().text = "Waiting for Player 1..."
	session.request_deck(deck)


func _close_deck_page() -> void:
	if is_instance_valid(deck_page):
		deck_page.queue_free()
	deck_page = null
	deck_builder = null


# The host gave this client a side. A Preparedness client gets the Preparedness panel instead.
func _on_seat(side: String) -> void:
	client_side = side
	_close_coin_page()
	if side != "preparedness":
		return
	_free_board_3d()
	if is_instance_valid(client_panel):
		client_panel.queue_free()
	client_panel = LanPrepPanel.new()
	client_layer.add_child(client_panel)
	if is_instance_valid(esc_menu):
		client_layer.move_child(esc_menu, -1)
	client_panel.back_pressed.connect(back_to_title)
	session.attach_prep_panel(client_panel)
	_mount_board_3d("preparedness")


# Show what went wrong, with a button back to the title (or to the lobby hub when to_hub is true).
func _client_message(text: String, to_hub := false) -> void:
	if ended or session.is_host:
		return
	ended = true
	room = ""
	session.close()
	_close_client_panel()
	director.reset_panel("JOIN LAN", text, "title_help")
	if to_hub:
		director.button("Back to lobby", show_lobby, director.content).name = "BackButton"
		return
	director.button("Back to title", director.show_title, director.content).name = "BackButton"
