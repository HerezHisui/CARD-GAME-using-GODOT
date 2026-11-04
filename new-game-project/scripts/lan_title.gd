extends Node
## LAN Part E: Host LAN and Join LAN from the title screen. Child of run_director, made once.
## Only made when VersusMatch.LAN_ENABLED is true. Sides are fixed for now:
## the host plays Preparedness, the client plays the Disaster.
## Later (D2-b..d) a coin result can pass other seats to start_lan_match.
## D2-d: the sides are no longer fixed. The host is Player 1 and calls the coin, the toss winner picks
## a side, then the host plays Player 1's side and the client the other one.

const LanSession = preload("res://scripts/lan_session.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const LanPrepPanel = preload("res://scripts/lan_prep_panel.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
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
var esc_menu: Control
var coin_stage := ""  # host: the last coin stage sent to the client
var coin_page: Control  # client: the coin screen over the panel, until the host seats this client
var client_side := ""  # client: the side the host gave this client, "" during the coin


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
	session.event_received.connect(_on_event)


# --- Host ---

func show_host() -> void:
	_ensure_session()
	in_match = false
	remote_id = 0
	var error: Error = session.host_game(port)
	director.reset_panel("HOST LAN", "Waiting for a player...", "title_help")
	var box: VBoxContainer = director.content
	if error != OK:
		box.add_child(director.label("Could not open port %d (error %d)." % [port, error], 18, UI.TEXT, true))
	else:
		box.add_child(director.label("Port %d" % port, 18))
		var lines := host_addresses(Array(IP.get_local_addresses()))
		if lines.is_empty():
			lines = ["No network address found"]
		for line in lines:
			box.add_child(director.label(line, 18))
		var firewall := "Allow UDP %d in Windows Firewall (Private and Radmin networks)." % port
		box.add_child(director.label(firewall, 16, UI.MUTED, true))
	director.button("Cancel", cancel_host, box).name = "CancelButton"


func cancel_host() -> void:
	session.close()
	director.show_title()


func _on_peer_joined(id: int) -> void:
	if not session.is_host or in_match:
		return
	remote_id = id
	start_lan_match("local", "remote")


## Starts the Versus match with these seats. Part E: host = "local" Preparedness, "remote" Disaster.
## D2-d: these seats only last through the coin. The side pick sets the real seats.
func start_lan_match(prep_seat: String, disaster_seat: String) -> void:
	in_match = true
	coin_stage = ""
	session.lobby = true
	game.set_seats(prep_seat, disaster_seat)
	director.start_versus_match()
	session.game = game
	session.send_view()


func _on_peer_left(id: int) -> void:
	if not session.is_host or not in_match or id != remote_id:
		return
	in_match = false
	remote_id = 0
	session.game = null
	session.close()
	director.versus_match.abort("OPPONENT LEFT", "The other player left the match.")


# Host: during the coin, tell the client what the host screen shows. After the side pick, seat the client.
func _process(_delta: float) -> void:
	if session == null or not session.is_host or not in_match or not session.lobby:
		return
	var versus: Node = director.versus_match
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
	ended = false
	match_over_seen = false
	client_side = ""
	session.last_view = {}
	status_label.text = "Connecting..."
	if session.join_game(last_ip, port) != OK:
		status_label.text = "Could not connect"


func cancel_join() -> void:
	session.close()
	director.show_title()


func _on_joined_host() -> void:
	if session.is_host:
		return
	if is_instance_valid(status_label):
		status_label.text = "Connected"
	_show_client_panel()


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
	client_panel = LanClientPanel.new()
	client_layer.add_child(client_panel)
	client_panel.back_pressed.connect(back_to_title)
	session.attach_panel(client_panel)
	director.visible = false


func _close_client_panel() -> void:
	if is_instance_valid(client_layer):
		client_layer.queue_free()
	client_layer = null
	client_panel = null
	esc_menu = null
	coin_page = null
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
	if session.is_host or not is_instance_valid(client_layer):
		return
	if kind == "coin" and client_side == "":
		_show_coin_page(data)
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


# The host gave this client a side. A Preparedness client gets the Preparedness panel instead.
func _on_seat(side: String) -> void:
	client_side = side
	_close_coin_page()
	if side != "preparedness":
		return
	if is_instance_valid(client_panel):
		client_panel.queue_free()
	client_panel = LanPrepPanel.new()
	client_layer.add_child(client_panel)
	if is_instance_valid(esc_menu):
		client_layer.move_child(esc_menu, -1)
	client_panel.back_pressed.connect(back_to_title)
	session.attach_prep_panel(client_panel)


# Show what went wrong, with a button back to the title.
func _client_message(text: String) -> void:
	if ended or session.is_host:
		return
	ended = true
	session.close()
	_close_client_panel()
	director.reset_panel("JOIN LAN", text, "title_help")
	director.button("Back to title", director.show_title, director.content).name = "BackButton"
