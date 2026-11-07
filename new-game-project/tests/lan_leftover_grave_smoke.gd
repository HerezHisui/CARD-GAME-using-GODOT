extends SceneTree
## LAN leftovers part 1: the Disaster graveyard as a list over LAN, behind LAN_PREP_UTILITIES.
## Flag on: the Disaster view carries the list in order, the Preparedness view never does.
## Flag off: the view keeps the count only. The Disaster table shows the list or the count note.

const LanSession = preload("res://scripts/lan_session.gd")
const LanClientPanel = preload("res://scripts/lan_client_panel.gd")
const LanBoard3D = preload("res://scripts/lan_board_3d.gd")
const LanView = preload("res://scripts/lan_view.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node
var session: Node


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
	session = LanSession.new()
	root.add_child(session)
	check_views()
	await check_table(true)
	await check_table(false)
	session.queue_free()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_leftover_grave_smoke (%d checks)" % checks)
	quit(0)


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 4, "tension_cost": 1}


func fixture(flag: bool) -> void:
	paused = false
	game.clear_battle()
	game.set_seats("remote", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.lan_prep_utilities_override = flag
	game.player_first = true
	game.turn = 2
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 5
	game.preparedness = 5
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.disaster_graveyard.clear()
	game.record_disaster_definition(threat("a"), "Destroyed")
	game.record_disaster_definition(threat("b"), "Cast")
	game.record_disaster_definition(threat("c"), "Destroyed")


func names_of(list: Array) -> Array:
	return list.map(func(entry: Dictionary) -> String: return str(entry.name))


func check_views() -> void:
	fixture(true)
	var disaster: Dictionary = LanView.build(game, "disaster")
	expect(disaster.has("disaster_graveyard_list"), "flag on: the Disaster view carries the list")
	var list: Array = disaster.disaster_graveyard_list
	expect(names_of(list) == ["Threat a", "Threat b", "Threat c"], "list is in graveyard order")
	expect(str(list[1].graveyard_reason) == "Cast", "list keeps the reason")
	expect(int(disaster.counts.disaster_graveyard) == 3, "count is still sent")
	# The list is a copy: changing it never touches the host graveyard.
	list[0].name = "Changed"
	expect(game.disaster_graveyard[0].name == "Threat a", "the list is a copy")
	var prep: Dictionary = LanView.build(game, "preparedness")
	expect(not prep.has("disaster_graveyard_list"), "the Preparedness view has no list")
	expect(int(prep.counts.disaster_graveyard) == 3, "the Preparedness view keeps the count")
	expect(not str(prep).contains("Threat a"), "no graveyard card name in the Preparedness view")
	fixture(false)
	var off: Dictionary = LanView.build(game, "disaster")
	expect(not off.has("disaster_graveyard_list"), "flag off: no list")
	expect(int(off.counts.disaster_graveyard) == 3, "flag off: the count stays")
	# The production default is flag on, so the list is there. The flag-off case is above.
	game.lan_prep_utilities_override = null
	expect(LanView.build(game, "disaster").has("disaster_graveyard_list"), "default flag: the list is sent")


func check_table(flag: bool) -> void:
	fixture(flag)
	var label := "flag %s: " % flag
	var panel := LanClientPanel.new()
	var cover := ColorRect.new()
	root.add_child(cover)
	game.visible = false
	var board := LanBoard3D.new()
	root.add_child(board)
	board.setup(game, director, session, panel, "disaster", cover)
	session.view_received.emit(LanView.build(game, "disaster"))
	await process_frame
	await process_frame
	board.show_disaster_graveyard()
	await process_frame
	var note: Node = board.grave_note
	expect(is_instance_valid(note), label + "the graveyard notice opens")
	var scroll: Node = note.find_child("GraveList", true, false)
	if flag:
		expect(scroll != null, label + "the list is shown")
		var grid: Node = scroll.get_child(0) if scroll != null else null
		expect(grid != null and grid.get_child_count() == 3, label + "three card tiles")
		expect(note.get_parent().get_child_count() > 0, label + "the notice sits in the HUD")
	else:
		expect(scroll == null, label + "no list without the flag")
		expect(find_text(note, "unavailable"), label + "the count note is shown")
	board.free()
	cover.free()
	panel.free()
	await process_frame


func find_text(node: Node, part: String) -> bool:
	if node is Label and part in node.text: return true
	for child in node.get_children():
		if find_text(child, part): return true
	return false
