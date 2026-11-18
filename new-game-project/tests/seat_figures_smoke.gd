extends SceneTree
## Covers: the seat-figure hook (scripts/seat_figures.gd, enemy_hand_display.gd _apply_figures) behind
## game.seat_figures_override. With the override null every room keeps the Janitor and the Preparedness figure.
## With a Dictionary the far seat shows the room's figure and the near seat the leader, when a cut-out exists.
## Only Robin has a cut-out, so the checks force "robin" at either seat. That is a fixture, not a rule.
## Rendered frames: run without --headless and add "-- --shot=<folder>".

const SeatFigures = preload("res://scripts/seat_figures.gd")
const StandeeFigure = preload("res://scripts/standee_figure.gd")
const PrepFigure = preload("res://scripts/preparedness_figure.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
## The fan centre must sit this close to the standee's hand point.
const HAND_LIMIT := 0.15
const FIXTURE := {"id": "fixture", "name": "Fixture", "type": "disaster", "cost": 0,
	"attack": 1, "health": 2, "element": "fire", "tension_cost": 0}

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


func make_game() -> Node:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await frames()
	return game


func free_game(game: Node) -> void:
	game.queue_free()
	await frames()


## Starts a real room and waits for the player's turn (cap 600 frames).
func start_room(game: Node, kind: String, floor_level: int, override: Variant) -> void:
	var director: Node = game.run_director
	game.seat_figures_override = override
	game.disaster_is_human = false
	director.floor_number = floor_level
	director.battle_active = true
	game.start_encounter(director.character_deck(0), kind, floor_level, 0)
	director.screen = ""
	director.close_modal()
	for i in 600:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await process_frame
	await frames()


func body(game: Node) -> Node3D:
	return game.opponent_hand.character.find_child("JanitorMesh", true, false)


func standee_count(game: Node) -> int:
	var count := 0
	for child: Node in game.opponent_hand.get_children():
		if child.get_script() == StandeeFigure and not child.is_queued_for_deletion(): count += 1
	return count


func run() -> void:
	check_data()
	var game: Node = await make_game()
	await check_today(game)
	await check_data_rooms(game)
	await check_far_standee(game)
	await check_near(game)
	await check_leader_rows(game)
	await check_unknown(game)
	await check_frames_all_rooms(game)
	await check_versus(game)
	await free_game(game)
	await check_tutorial()
	if failures > 0:
		quit(1)
		return
	print("PASS: seat_figures_smoke (%d checks)" % checks)
	quit(0)


## 2. The data file parses and has the five rooms, each with a figure.
func check_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SeatFigures.DATA_PATH))
	expect(parsed is Dictionary, "seat_figures.json parses")
	if not parsed is Dictionary: return
	var rooms: Dictionary = parsed.get("rooms", {})
	for room: String in ["battle", "tutorial", "elite", "boss", "warden"]:
		expect(rooms.has(room) and rooms[room].has("figure"), "room row with a figure: " + room)
	expect(SeatFigures.hand("robin") != Vector2.INF, "Robin has a hand point in the data")


## 1. Override null: every room is today's.
func check_today(game: Node) -> void:
	var rooms := [["battle", 1], ["elite", 1], ["boss", 1], ["boss", 3]]
	for row: Array in rooms:
		await start_room(game, row[0], row[1], null)
		var label := "Override null, %s floor %d: " % [row[0], row[1]]
		expect_today(game, label)
	await start_room(game, "battle", 1, null)
	await capture("far-janitor-1280")


func expect_today(game: Node, label: String) -> void:
	expect(SeatFigures.far_id(game) == "janitor", label + "far id is janitor")
	expect(SeatFigures.near_id(game) == "", label + "near id is empty")
	expect(body(game).visible, label + "the JanitorMesh is visible")
	expect(game.opponent_hand.far_standee == null and standee_count(game) == 0, label + "no far standee")
	expect(game.opponent_hand.figure.get_script() == PrepFigure, label + "the near figure is today's")


## 3. Override {}: the rows of the data. No cut-out yet, so the Janitor shows.
func check_data_rooms(game: Node) -> void:
	var rooms := [["battle", 1, "dealer"], ["elite", 1, "guardian"], ["boss", 3, "warden"], ["boss", 1, "janitor"]]
	for row: Array in rooms:
		await start_room(game, row[0], row[1], {})
		var label := "Override {}, %s floor %d: " % [row[0], row[1]]
		expect(SeatFigures.far_id(game) == row[2], label + "far id is " + row[2])
		expect(body(game).visible and standee_count(game) == 0, label + "no cut-out, the Janitor shows")


## 4 to 9. A forced far standee.
func check_far_standee(game: Node) -> void:
	await start_room(game, "battle", 1, {"far": "robin"})
	var hand: Node3D = game.opponent_hand
	var character: Node3D = hand.character
	var standee: Node3D = hand.far_standee
	# 4. The body hides, the skeleton stays.
	expect(is_instance_valid(standee) and standee.get_script() == StandeeFigure, "Far robin: a standee")
	if not is_instance_valid(standee): return
	expect(not body(game).visible, "Far robin: the JanitorMesh is hidden")
	expect(character.visible, "Far robin: the character itself is still visible")
	expect(standee.get_parent() == hand, "Far robin: the standee is a child of opponent_hand")
	expect(standee.is_visible_in_tree(), "Far robin: the standee shows in a battle")
	await frames(30)
	expect(not character.cloth.running, "Far robin: the cloth is stopped after 30 frames")
	# 5. The unseen hand: three backs, then a card played and released.
	game.enemy_hand.assign([FIXTURE.duplicate(), FIXTURE.duplicate(), FIXTURE.duplicate()])
	await frames(30)
	expect(character.holding.get_child_count() == 3, "Far robin: the fan holds three backs")
	var gap := fan_gap(game)
	print("Far robin: fan centre %.3f from the hand point" % gap)
	expect(gap < HAND_LIMIT, "Far robin: the fan centre sits at the standee's hand")
	await capture("far-standee-1280")
	await capture("far-standee-1920", Vector2i(1920, 1080))
	hand.play_card(FIXTURE)
	await capture("far-play-1280")
	for i in 600:
		if character.released: break
		await process_frame
	expect(character.released, "Far robin: the played card is released")
	# 6. Contract A.
	check_contract(game, standee)
	# 7. It hides with the far seat.
	game.run_director.modal.show()
	await frames()
	expect(not standee.is_visible_in_tree(), "Far robin: hidden while a modal is open")
	game.run_director.modal.hide()
	await frames()
	expect(standee.is_visible_in_tree(), "Far robin: back after the modal")
	# 8. Back to the Janitor, then the standee once more.
	game.seat_figures_override = {"far": "janitor"}
	await frames()
	expect(body(game).visible, "Far janitor: the JanitorMesh shows again")
	expect(not is_instance_valid(standee) and hand.far_standee == null, "Far janitor: the standee is freed")
	expect(character.position == hand.home, "Far janitor: the Janitor is back at his place")
	expect(character.cloth.running, "Far janitor: the cloth runs again in a live battle")
	game.seat_figures_override = {"far": "robin"}
	await frames()
	expect(standee_count(game) == 1, "Far robin again: one standee, not two")
	# 9. The Warden room.
	await start_room(game, "boss", 3, {"far": "robin"})
	expect(is_instance_valid(game.final_boss), "Warden room: the Warden is there")
	expect(SeatFigures.room(game) == "warden", "Warden room: the room is warden")
	expect(is_instance_valid(hand.far_standee) and hand.far_standee.is_visible_in_tree(),
		"Warden room: the standee shows")
	expect(character.holding.get_child_count() == 0, "Warden room: the fan is empty")
	game.final_boss.resolve_intent()
	await frames()
	expect(is_instance_valid(hand.far_standee), "Warden room: resolve_intent runs with the standee")


## How far the centre of the fan is from the standee's hand point.
func fan_gap(game: Node) -> float:
	var hand: Node3D = game.opponent_hand
	var holding: Node3D = hand.character.holding
	var centre := Vector3.ZERO
	for card: Node3D in holding.get_children():
		centre += card.global_position
	centre /= maxi(holding.get_child_count(), 1)
	var point := SeatFigures.hand("robin")
	var at: Vector3 = hand.far_standee.to_global(Vector3(point.x, point.y, hand.HAND_FRONT))
	return centre.distance_to(at)


## 6. No collision, no shadow, the Janitor's height (all meshes), clear of the lanes.
func check_contract(game: Node, standee: Node3D) -> void:
	expect(standee.find_children("*", "CollisionObject3D", true, false).is_empty(), "Far robin: no collision")
	for mesh: MeshInstance3D in standee.find_children("*", "MeshInstance3D", true, false):
		expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Far robin: no shadow from " + mesh.name)
	var box := figure_box(standee)
	var janitor: Node3D = game.opponent_hand.character
	expect(absf(box.size.y - 2.0 * janitor.scale.y) < 0.05, "Far robin: the Janitor's height")
	for slot: Node3D in game._threat_slots() + game._response_slots():
		expect(not box.intersects(slot_box(slot)), "Far robin: clear of " + slot.name)


## 10. A forced near standee: on PlayerPosition, hidden in singleplayer, `figure` valid through the swap.
func check_near(game: Node) -> void:
	await start_room(game, "battle", 1, null)
	var hand: Node3D = game.opponent_hand
	game.seat_figures_override = {"near": "robin"}
	var valid := true
	for i in 3:
		await process_frame
		valid = valid and is_instance_valid(hand.figure)
	expect(valid, "Near robin: figure valid on the frame of the swap and after")
	var figure: Node3D = hand.figure
	expect(figure.get_script() == StandeeFigure, "Near robin: the figure is a standee")
	check_place(game, figure, "Near robin: ")
	expect(not figure.visible, "Near robin: hidden in a singleplayer battle")
	# Three frames with the figure shown, one per camera view. The suite shows it; the game never does.
	figure.show()
	game.set_view(game.View.DESK)
	await frames(40)
	await capture("near-desk-1280")
	game.set_view(game.View.BOARD)
	await frames(40)
	await capture("near-board-1280")
	game.set_view(game.View.DESK)
	figure.hide()
	await frames(40)
	# Back to the Preparedness figure.
	game.seat_figures_override = null
	await frames()
	expect(hand.figure.get_script() == PrepFigure and not is_instance_valid(figure),
		"Near back to today's figure, the standee freed")


## 11. The near seat from the leader rows.
func check_leader_rows(game: Node) -> void:
	var director: Node = game.run_director
	var was: int = director.selected_character
	var found := false
	for i in director.CHARACTERS.size():
		var leader := str(director.CHARACTERS[i].get("leader", ""))
		if leader == "": continue
		found = true
		director.selected_character = i
		await start_room(game, "battle", 1, {})
		expect(SeatFigures.near_id(game) == leader, "Leader row %d: near id is %s" % [i, leader])
		var want: Variant = StandeeFigure if StandeeFigure.CUTS.has(leader) else PrepFigure
		expect(game.opponent_hand.figure.get_script() == want, "Leader row %d: the near figure fits" % i)
	if not found: print("No CHARACTERS row has a leader key: check 11 skipped")
	director.selected_character = was
	game.seat_figures_override = null
	await frames()


## 14. An unknown id at either seat shows today's body.
func check_unknown(game: Node) -> void:
	await start_room(game, "battle", 1, {"far": "nobody", "near": "nobody"})
	expect(body(game).visible and standee_count(game) == 0, "Unknown far id: the Janitor shows")
	expect(game.opponent_hand.figure.get_script() == PrepFigure, "Unknown near id: today's figure")


## 15. 120 frames per room with both seats forced; the log must show no SCRIPT ERROR.
func check_frames_all_rooms(game: Node) -> void:
	var both := {"far": "robin", "near": "robin"}
	for row: Array in [["battle", 1], ["elite", 1], ["boss", 1]]:
		await start_room(game, row[0], row[1], both)
		await frames(120)
		expect(is_instance_valid(game.opponent_hand.far_standee) and game.opponent_hand.figure.get_script()
			== StandeeFigure, "120 frames in %s with both seats forced" % row[0])


## 12. Versus: never on.
func check_versus(game: Node) -> void:
	game.seat_figures_override = {"far": "robin", "near": "robin"}
	await frames()
	var director: Node = game.run_director
	director.start_versus_match()
	director.screen = ""
	director.close_modal()
	game.disaster_is_human = true
	await frames()
	expect(not SeatFigures.on(game), "Versus: the hook is off")
	expect_today(game, "Versus: ")


## 13. The tutorial, through its real start, then 120 frames with both seats forced.
func check_tutorial() -> void:
	var game: Node = await make_game()
	var director: Node = game.run_director
	game.tutorial_override = true
	game.seat_figures_override = {"far": "robin", "near": "robin"}
	director.show_title()
	await frames()
	expect(Tutorial.start(director), "Tutorial: the drill starts")
	for i in 600:
		if game.phase == game.Phase.PLAYER_DRAW: break
		await process_frame
	expect(game.encounter_kind == "tutorial", "Tutorial: the room is the tutorial")
	var standee: Node3D = game.opponent_hand.far_standee
	expect(is_instance_valid(standee) and standee.visible and not body(game).visible,
		"Tutorial: the far standee shows")
	await frames(120)
	expect(is_instance_valid(game.opponent_hand.far_standee), "Tutorial: 120 frames with both seats forced")
	game.tutorial_override = null
	await free_game(game)


## Copied from standee_figure_smoke.gd: the figure's box in world space, all meshes.
func figure_box(figure: Node3D) -> AABB:
	var meshes := figure.find_children("*", "MeshInstance3D", true, false)
	var first := meshes[0] as MeshInstance3D
	var box := first.global_transform * first.get_aabb()
	for mesh: MeshInstance3D in meshes:
		box = box.merge(mesh.global_transform * mesh.get_aabb())
	return box


## Copied from preparedness_figure_smoke.gd: a card-sized box around a lane slot.
func slot_box(slot: Node3D) -> AABB:
	return AABB(slot.global_position - Vector3(0.6, 0.2, 0.8), Vector3(1.2, 0.4, 1.6))


## Copied from preparedness_figure_smoke.gd check_place (box of all meshes).
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


## Saves a frame when a --shot folder is given and the run is not headless.
func capture(shot_name: String, size := Vector2i(1280, 720)) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	root.size = size
	# The pass-the-laptop cover would hide the table.
	current_scene.run_director.privacy_screen.hide()
	await frames(8)
	var path := shot_folder.path_join(shot_name + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, shot_name + " frame saved")
