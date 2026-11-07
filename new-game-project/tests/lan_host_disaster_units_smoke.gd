extends SceneTree
## LAN bug fix: a host that plays the Disaster must see the units the remote Preparedness client plays.
## The host hides its hand container for the whole match (game_3d_manager.hide_versus_hand).
## A unit played over LAN starts in that container, so it must leave it when it lands on the board.
## Host and client run in one process over loopback, as in lan_prep_smoke.gd.

const LanSession = preload("res://scripts/lan_session.gd")

# Not the game port and not a port of another LAN suite.
const TEST_PORT := 24791
const MAX_FRAMES := 3000

var failures := 0
var checks := 0
var game: Node
var director: Node
var host: Node
var client: Node
var client_joined := false
var host_results: Array = []


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
	setup_sides()
	await check_connect()
	await check_unit_visible("fresh match")
	# A second match in the same session: the reset and the hidden hand come back the same way.
	await check_unit_visible("second match")
	host.close()
	client.close()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_host_disaster_units_smoke (%d checks)" % checks)
	quit(0)


# Wait frame by frame until the check is true. Gives up after MAX_FRAMES or 10 seconds.
func wait_until(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	for i in MAX_FRAMES:
		if check.call():
			return true
		if Time.get_ticks_msec() - start > 10000:
			return false
		await process_frame
	return check.call()


func unit(id: String) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": 1,
		"attack": 1, "health": 30}


func make_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = LanSession.new()
	session.name = "LanSession"
	holder.add_child(session)
	return session


func setup_sides() -> void:
	host = make_side("Host")
	client = make_side("Client")
	client.joined_host.connect(func() -> void: client_joined = true)
	host.action_done.connect(func(result: Dictionary) -> void: host_results.append(result))


func check_connect() -> void:
	host.game = game
	expect(host.host_game(TEST_PORT) == OK, "host listens")
	expect(client.join_game("127.0.0.1", TEST_PORT) == OK, "client starts joining")
	expect(await wait_until(func() -> bool: return client_joined and host.disaster_peer != 0), "client joins")
	host.seat_client("preparedness")


# Send one message from the client and wait until the host has handled it.
func send(msg: Dictionary) -> Dictionary:
	var before := host_results.size()
	client.request_action(msg)
	if not await wait_until(func() -> bool: return host_results.size() > before):
		return {"ok": false, "reason": "timeout"}
	return host_results[before]


# The host plays the Disaster (local), the client plays Preparedness (remote).
func host_disaster_fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.set_seats("remote", "local")
	game.disaster_is_human = true
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 3
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	# Same call resume_coin makes. The host-as-Disaster never reveals it (see lan_lobby_smoke.gd).
	game.hide_versus_hand()
	game._set_phase(game.Phase.PLAYER_PLAY)


func check_unit_visible(name: String) -> void:
	host_disaster_fixture()
	expect(not game.hand_container.visible, name + ": the host hides the Preparedness hand")
	game.add_card_to_hand(unit("u_" + name.left(1)))
	var card: Node = game.get_hand_cards()[0]
	var result: Dictionary = await send({"kind": "play", "hand": 0, "lane": 1})
	expect(result.get("ok", false), name + ": the client plays a unit into lane 2")
	var placed = game._get_card_in_slot(game._response_slots()[1])
	expect(placed == card, name + ": the unit is in lane 2 on the host")
	expect(is_instance_valid(card) and card.is_visible_in_tree(), name + ": the host sees the unit")
	expect(is_instance_valid(card) and card.get_parent() != game.hand_container,
		name + ": the unit left the hidden hand container")
