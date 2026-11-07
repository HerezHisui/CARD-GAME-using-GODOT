extends SceneTree

# Crosswind picker must stay clear of the Tension plate at two window sizes.
class RecordingLink:
	extends "res://scripts/lan_session.gd"
	func request_action(_msg) -> void:
		pass

const Decks = preload("res://scripts/versus_decks.gd")
const View = preload("res://scripts/lan_view.gd")
var failures := 0
var checks := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.presentation.automated_choice = 0
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_waiting = true
	game.set_seats("local", "remote")
	game._set_phase(game.Phase.ENEMY)
	game.tension = 6
	game.disaster_actions.begin_turn()
	var ally: Node = game.Card3DScene.instantiate()
	game.add_child(ally)
	ally.add_to_group("cards")
	ally.setup({"id": "a", "name": "a", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 3})
	ally.place_on_slot(game._threat_slots()[0])
	var data: Dictionary = Decks.pool("disaster").base.crosswind.duplicate(true)
	game.enemy_hand.assign([data])
	await game.disaster_actions.play_base(data, game._threat_slots()[1])
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	link.attach_panel(panel)
	var board: Node = preload("res://scripts/lan_board_3d.gd").new()
	root.add_child(board)
	for card in get_nodes_in_group("cards"): card.hide()
	board.setup(game, game.run_director, link, panel, "disaster")
	var private_view := View.build(game)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		link.push_view(private_view)
		await frames(15)
		var picker: Control = board.relocation_box
		expect(picker != null, "Picker exists at %s" % size)
		if picker == null: continue
		for step in 2:
			# Step 1 lists the ally lanes, step 2 the empty destinations.
			var tension: Rect2 = board.resource_plate.get_global_rect()
			var rect := picker.get_global_rect()
			print("%s step %d picker %s tension %s" % [size, step, rect, tension])
			expect(not rect.intersects(tension), "Picker clear of Tension at %s step %d" % [size, step])
			expect(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect), "Picker on screen at %s step %d" % [size, step])
			if step == 0:
				board.click_lane(0)
				await frames(5)
				picker = board.relocation_box
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: lan_crosswind_layout_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
