extends SceneTree
## Covers: the standee figure (scripts/standee_figure.gd) behind game.standee_override. With the override null the
## player's seat keeps the Preparedness figure. With "robin" a flat standee stands there instead, under the same
## seat contract: on PlayerPosition, no collision, the Janitor's height, clear of the lanes, no shadow, and shown
## only from the Disaster seat. Two fixtures put a second standee at the Janitor's place for frames only.
## Rendered frames: run without --headless and add "-- --shot=<folder>".

const StandeeFigure = preload("res://scripts/standee_figure.gd")
const PrepFigure = preload("res://scripts/preparedness_figure.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
## The two new pictures together must add 0.5 MB or less.
const PICTURES := ["res://assets/portraits/robin.png", "res://assets/characters/standees/robin.png"]
const SIZE_LIMIT := 524288

var failures := 0
var checks := 0
var shot_folder := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot_folder = arg.trim_prefix("--shot=")
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func frames(count: int = 3) -> void:
	for i in count: await process_frame


func make_game(override: Variant) -> Node:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	# The override must be set before the game enters the tree: the figure is made in _ready.
	game.standee_override = override
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await frames()
	return game


func run() -> void:
	# Override null: the Preparedness figure, exactly as before.
	var old_game: Node = await make_game(null)
	expect(old_game.opponent_hand.figure.get_script() == PrepFigure, "Override null: the Preparedness figure")
	await to_disaster_seat(old_game)
	await capture("old-1280")
	await free_game(old_game)
	# Override "robin": the standee.
	var game: Node = await make_game("robin")
	var figure: Node3D = game.opponent_hand.figure
	expect(figure.get_script() == StandeeFigure, "Override robin: the figure is a standee")
	expect(not figure.visible, "Override robin: hidden at start")
	check_unknown_id(game)
	check_size()
	check_single_player(game, figure)
	await check_boss_seats(game)
	await check_local_versus(game, figure)
	await check_battle_frames(game, figure)
	await free_game(game)
	if failures > 0:
		quit(1)
		return
	print("PASS: standee_figure_smoke (%d checks)" % checks)
	quit(0)


func free_game(game: Node) -> void:
	game.queue_free()
	await frames()


## Copied from preparedness_figure_smoke.gd: the figure's box in world space (its first mesh).
func figure_box(figure: Node3D) -> AABB:
	var mesh := figure.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return mesh.global_transform * mesh.get_aabb()


## Copied from preparedness_figure_smoke.gd: a card-sized box around a lane slot.
func slot_box(slot: Node3D) -> AABB:
	return AABB(slot.global_position - Vector3(0.6, 0.2, 0.8), Vector3(1.2, 0.4, 1.6))


## Copied from preparedness_figure_smoke.gd: seat, collision and lane checks.
func check_place(game: Node, figure: Node3D, label: String) -> void:
	expect(is_instance_valid(figure), label + "figure exists")
	if not is_instance_valid(figure): return
	var seat: Node3D = game.find_child("PlayerPosition", true, false)
	var flat := Vector2(figure.global_position.x - seat.global_position.x,
		figure.global_position.z - seat.global_position.z)
	expect(flat.length() < 0.01, label + "figure stands on PlayerPosition")
	expect(figure.find_children("*", "CollisionObject3D", true, false).is_empty(),
		label + "figure has no collision, so mouse rays pass")
	var box := figure_box(figure)
	var janitor: Node3D = game.opponent_hand.character
	expect(absf(box.size.y - 2.0 * janitor.scale.y) < 0.05, label + "figure is the Janitor's height")
	for slot: Node3D in game._threat_slots() + game._response_slots():
		expect(not box.intersects(slot_box(slot)), label + "figure clear of " + slot.name)


func check_unknown_id(game: Node) -> void:
	game.standee_override = "nobody"
	var other: Node3D = StandeeFigure.make_for(game)
	expect(other.get_script() == PrepFigure, "Unknown id: the Preparedness figure")
	other.free()
	game.standee_override = "robin"


func check_size() -> void:
	var total := 0
	for path: String in PICTURES:
		total += FileAccess.get_file_as_bytes(path).size()
	print("New pictures: %d bytes" % total)
	expect(total > 0 and total <= SIZE_LIMIT, "The two new pictures are 0.5 MB or less")


func check_single_player(game: Node, figure: Node3D) -> void:
	game.clear_battle()
	game.encounter_kind = "battle"
	game.run_director.battle_active = true
	check_place(game, figure, "Single-player: ")
	expect(not figure.visible, "Single-player: standee hidden from the player's own seat")
	for mesh: MeshInstance3D in figure.find_children("*", "MeshInstance3D", true, false):
		expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "No shadow from " + mesh.name)
	game.run_director.battle_active = false


## A second standee at the Janitor's place, seen from the player's own seat. Frames only, no game code.
func check_boss_seats(game: Node) -> void:
	var director: Node = game.run_director
	game.clear_battle()
	game.encounter_kind = "battle"
	# close_modal opens the map when no battle is active, so the battle comes first.
	director.battle_active = true
	director.screen = ""
	director.close_modal()
	var character: Node3D = game.opponent_hand.character
	var was_visible: bool = character.visible
	var was_count: int = character.hand_count
	var was_running: bool = character.cloth.running
	character.set_encounter(true)
	game._apply_view(game.DESK_VIEW)
	var stand: Node3D = StandeeFigure.new()
	stand.build("robin")
	game.add_child(stand)
	# Base on the Janitor's floor line, facing the player (+Z, like the Janitor's mesh).
	stand.place_at(game.find_child("OpponentPosition", true, false))
	stand.rotation_degrees.y = 0.0
	stand.show()
	# (a) Boss seat: the Janitor hidden, the standee in his place.
	character.hide()
	await capture("boss-seat-1280")
	# (b) Dealer seat: the Janitor live with only his body hidden, three backs in the fan.
	character.show()
	var body: Node3D = character.find_child("JanitorMesh", true, false)
	body.hide()
	# opponent_hand.refresh() sets the fan from enemy_hand every frame, so the hand holds three cards too.
	var was_hand: Array[Dictionary] = game.enemy_hand.duplicate()
	for i in 3:
		game.enemy_hand.append({"id": "fixture", "name": "Fixture", "type": "disaster", "cost": 0,
			"attack": 1, "health": 2, "element": "fire", "tension_cost": 0})
	character.set_hand_count(3)
	character.cloth.running = false
	await frames()
	expect(character.holding.get_child_count() == 3, "Dealer seat: the fan holds three backs")
	expect(not body.visible, "Dealer seat: the JanitorMesh is hidden")
	var offset: Vector3 = character.holding.global_position - stand.global_position
	print("Dealer seat: fan offset from the standee centre x %.2f, y %.2f, z %.2f" % [offset.x, offset.y, offset.z])
	await capture("dealer-seat-1280")
	# Put the Janitor back as he was.
	body.show()
	game.enemy_hand.assign(was_hand)
	character.set_hand_count(was_count)
	character.cloth.running = was_running
	character.visible = was_visible
	stand.queue_free()
	director.battle_active = false
	await frames()
	expect(body.visible and character.visible == was_visible, "Janitor restored after the fixture")
	expect(character.hand_count == was_count, "Janitor hand count restored")


## The Disaster seat in local Versus (the fixture of preparedness_figure_smoke.gd, check_local_versus).
func to_disaster_seat(game: Node) -> void:
	var director: Node = game.run_director
	director.start_versus_match()
	director.screen = ""
	director.close_modal()
	game.disaster_is_human = true
	await frames()
	director.versus_hud.update()
	director.battle_active = true
	game.disaster_seat_view = true
	game.phase = game.Phase.ENEMY
	game.disaster_waiting = true
	await frames()
	director.versus_hud.update()
	await frames()


func check_local_versus(game: Node, figure: Node3D) -> void:
	var director: Node = game.run_director
	director.start_versus_match()
	director.screen = ""
	director.close_modal()
	game.disaster_is_human = true
	await frames()
	check_place(game, figure, "Local Versus: ")
	director.versus_hud.update()
	expect(not figure.visible, "Local Versus: hidden on the Preparedness turn")
	director.battle_active = true
	game.disaster_seat_view = true
	game.phase = game.Phase.ENEMY
	game.disaster_waiting = true
	await frames()
	director.versus_hud.update()
	await frames()
	expect(figure.visible, "Local Versus: standee shown from the Disaster seat")
	expect(not game.opponent_hand.visible, "Local Versus: the Janitor stays hidden from the Disaster seat")
	var card := {"id": "fixture", "name": "Fixture", "type": "disaster", "cost": 0,
		"attack": 1, "health": 2, "element": "fire", "tension_cost": 0}
	game.enemy_hand.append(card)
	game.disaster_seat._sync_hand()
	await frames()
	expect(not game.disaster_seat.cards.is_empty(), "Local Versus: the Disaster seat hand has a card")
	var box := figure_box(figure)
	for seat_card: Node3D in game.disaster_seat.cards:
		expect(not box.has_point(seat_card.global_position), "Local Versus: standee clear of a Disaster hand card")
	expect(not box.has_point(game.camera.global_position), "Local Versus: the Disaster camera is not inside it")
	await capture("seat-1280")
	await capture("seat-1920", Vector2i(1920, 1080))
	figure.unshaded = true
	figure.apply_shading()
	await capture("seat-1280-unshaded")
	figure.unshaded = false
	figure.apply_shading()
	await capture_edge(game, figure)
	game.disaster_waiting = false
	await frames()
	director.versus_hud.update()
	await frames()
	expect(not figure.visible, "Local Versus: hidden again after the Disaster turn")


## The card edge. The side-by-side camera (versus_match.gd seat_camera) puts the standee at the frame's edge,
## behind the type panel, so this frame looks 45 degrees to the side of the standee instead.
func capture_edge(game: Node, figure: Node3D) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	var view: Dictionary = VersusMatch.seat_camera(true)
	var pivot: Node3D = game.get_node("CameraPivot")
	pivot.position = figure.global_position
	# The standee faces -Z (turned 180), so 180 + 45 looks at its front from one side.
	pivot.rotation_degrees = Vector3(-10, 225, 0)
	game.camera.position = Vector3(0, 0, view.dist)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = view.fov
	await capture("edge-1280")
	game._apply_view(game.DESK_VIEW)


## 120 battle frames with the standee on screen; the suite log must show no SCRIPT ERROR.
func check_battle_frames(game: Node, figure: Node3D) -> void:
	game.disaster_waiting = true
	await frames()
	game.run_director.versus_hud.update()
	await frames(120)
	expect(is_instance_valid(figure) and figure.visible, "120 battle frames with the standee shown")
	game.disaster_waiting = false
	await frames()
	game.run_director.versus_hud.update()
	await frames()


## Saves a frame when a --shot folder is given and the run is not headless.
func capture(shot_name: String, size := Vector2i(1280, 720)) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	root.size = size
	# The pass-the-laptop cover would hide the table.
	current_scene.run_director.privacy_screen.hide()
	await frames(8)
	var path := shot_folder.path_join(shot_name + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, shot_name + " frame saved")
