extends Node
## LAN link for Versus (Part A: connect, ping, disconnect). Not an autoload.
## Only used when VersusMatch.LAN_ENABLED is true. The host listens, one client joins by IP.
## Uses the multiplayer API of its own subtree, so a test can run a host and a client in one process.
## Part C: the client sends Disaster actions, the host checks and applies them, then sends a new view.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")

# UDP port the host listens on. Open it in the Windows firewall for private networks.
const PORT := 24680

signal peer_joined(id: int)
signal peer_left(id: int)
signal joined_host
signal join_failed
signal host_lost
signal pong_received(number: int)
# Client: a new board view or an event (for example "reject") came from the host.
signal view_received(view: Dictionary)
signal event_received(kind: String, data: Dictionary)
# Host: an action message was handled. result is {ok, reason}.
signal action_done(result: Dictionary)

var is_host := false
var peer: ENetMultiplayerPeer
var game: Node  # host only: the running Versus board
var disaster_peer := 0  # host only: the client id that plays the Disaster, 0 when none
var was_waiting := false  # host only: game.disaster_waiting at the last frame
var panel: Control  # client only: lan_client_panel.gd, set by attach_panel
var last_view: Dictionary = {}  # client only: the newest view from the host
var picked_hand := -1  # client only: the hand card picked on the panel
var picked_lanes: Array = []  # client only: sacrifice lanes picked so far for an evolution


func _ready() -> void:
	# Keep the link alive while the tree is paused (menu open).
	process_mode = Node.PROCESS_MODE_ALWAYS


# Host: send a new view when the Disaster turn starts or ends.
func _process(_delta: float) -> void:
	if not is_host or game == null or not is_instance_valid(game):
		return
	if game.disaster_waiting != was_waiting:
		was_waiting = game.disaster_waiting
		send_view()


# Start listening. Returns OK or the ENet error.
func host_game(port: int = PORT) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1)
	if error != OK:
		peer = null
		return error
	is_host = true
	_use_peer()
	return OK


# Connect to a host by IP. Returns OK if the attempt started; joined_host or join_failed follows.
func join_game(ip: String, port: int = PORT) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		peer = null
		return error
	is_host = false
	_use_peer()
	return OK


func is_open() -> bool:
	return peer != null


# Clean exit: the host tells each client first, so they learn at once instead of after
# the ENet timeout (about 30 seconds). Needs a few frames, so await it.
func leave() -> void:
	if peer == null:
		return
	if is_host:
		for id in multiplayer.get_peers():
			peer.disconnect_peer(id)
		for i in 10:
			await get_tree().process_frame
	close()


# Drop the link at once and go back offline.
func close() -> void:
	if peer == null:
		return
	_disconnect_signals()
	peer.close()
	peer = null
	is_host = false
	disaster_peer = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# Ask the other side to answer with the same number.
func send_ping(number: int) -> void:
	if peer == null:
		return
	ping.rpc(number)


@rpc("any_peer", "reliable")
func ping(number: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), number)


@rpc("any_peer", "reliable")
func pong(number: int) -> void:
	pong_received.emit(number)


# --- Part C: actions and views ---

# Host: send the board the Disaster may see to the Disaster client.
func send_view() -> void:
	if not is_host or disaster_peer == 0 or game == null or not is_instance_valid(game):
		return
	push_view.rpc_id(disaster_peer, LanView.build(game))


# Client: ask the host to do one Disaster action. See lan_actions.gd for the messages.
func request_action(msg) -> void:
	if peer == null or is_host:
		return
	send_action.rpc_id(1, msg)


# Host: one action from the client. The sender id comes from the network, never from the message.
# Untyped on purpose: a bad message must be refused here, not dropped by the RPC layer.
@rpc("any_peer", "reliable")
func send_action(msg) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var result: Dictionary
	# A local call has sender 0, and disaster_peer is 0 before anyone joins: refuse both.
	if sender == 0 or sender != disaster_peer:
		result = {"ok": false, "reason": "not_disaster_peer"}
	elif game == null or not is_instance_valid(game):
		result = {"ok": false, "reason": "no_match"}
	else:
		result = await LanActions.apply(game, msg)
	# The client may have left while the action played.
	if peer != null and sender in multiplayer.get_peers():
		if not result.ok:
			push_event.rpc_id(sender, "reject", {"reason": result.reason})
		if sender == disaster_peer:
			send_view()
	action_done.emit(result)


@rpc("authority", "reliable")
func push_view(view: Dictionary) -> void:
	last_view = view
	_clear_pick()
	if is_instance_valid(panel):
		panel.show_view(view)
	view_received.emit(view)


@rpc("authority", "reliable")
func push_event(kind: String, data: Dictionary) -> void:
	if kind == "reject" and is_instance_valid(panel):
		panel.show_reject(str(data.get("reason", "")))
	event_received.emit(kind, data)


# Client: turn panel clicks into action messages.
# A base needs a hand card, then a lane. An evolution needs as many lanes as its cost;
# it goes into the last lane clicked. A spell is sent at once; a spell that needs a target
# takes the first target the host allows (the client cannot see the Preparedness hand).
func attach_panel(new_panel: Control) -> void:
	panel = new_panel
	panel.hand_pressed.connect(_on_hand_pressed)
	panel.lane_pressed.connect(_on_lane_pressed)
	panel.end_turn_pressed.connect(func() -> void: request_action({"kind": "end"}))
	if not last_view.is_empty():
		panel.show_view(last_view)


func _on_hand_pressed(index: int) -> void:
	_clear_pick()
	if index < 0 or index >= last_view.get("hints", []).size():
		return
	var hint: Dictionary = last_view.hints[index]
	if not _hand_definition(index).get("utility", false):
		picked_hand = index
		return
	var target := -1
	if hint.needs_target and not hint.targets.is_empty():
		target = hint.targets[0]
	request_action({"kind": "cast", "hand": index, "target": target})


func _on_lane_pressed(lane: int) -> void:
	if picked_hand < 0 or lane in picked_lanes:
		return
	var cost := int(_hand_definition(picked_hand).get("cost", 0))
	if cost < 1:
		request_action({"kind": "base", "hand": picked_hand, "lane": lane})
		_clear_pick()
		return
	picked_lanes.append(lane)
	if picked_lanes.size() < cost:
		return
	request_action({"kind": "evolve", "hand": picked_hand, "lane": lane, "sacrifices": picked_lanes.duplicate()})
	_clear_pick()


func _hand_definition(index: int) -> Dictionary:
	var id: String = last_view.disaster_hand[index]
	return last_view.cards[id].definition


func _clear_pick() -> void:
	picked_hand = -1
	picked_lanes.clear()


func _use_peer() -> void:
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _disconnect_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	# The client also sees the host (id 1) connect; only the host reports joiners.
	if is_host:
		# The first client to join plays the Disaster.
		if disaster_peer == 0:
			disaster_peer = id
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		if id == disaster_peer:
			disaster_peer = 0
		peer_left.emit(id)


func _on_connected_to_server() -> void:
	joined_host.emit()


func _on_connection_failed() -> void:
	join_failed.emit()


func _on_server_disconnected() -> void:
	host_lost.emit()
