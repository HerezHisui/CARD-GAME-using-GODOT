# Covers: "The Drill" tutorial (scripts/tutorial.gd, data/tutorial_steps.json). Reached only through
# game.tutorial_override = true; the TUTORIAL_ENABLED const stays false. Driven with real mouse and key events.
# Every wait is a frame loop capped at 600 frames.
extends SceneTree

const Tutorial = preload("res://scripts/tutorial.gd")
const CAP := 600

var checks := 0
var failures := 0
var game: Node
var director: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

## Waits until the predicate is true, at most cap frames.
func wait_until(predicate: Callable, cap: int = CAP) -> bool:
	for i in cap:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

func move_to(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)

func button_event(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)

## A real click: move, press, release.
func click(point: Vector2) -> void:
	move_to(point)
	await process_frame
	button_event(point, true)
	await process_frame
	button_event(point, false)
	await frames(2)

func click_control(control: Control) -> void:
	await click(control.get_global_rect().get_center())

## Moves the mouse to a corner, so no card stays raised under it.
func mouse_away() -> void:
	move_to(Vector2(4, 4))
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func hand_point(card: Node) -> Vector2:
	# The resting place, so a card still sliding into the hand is hit where it will be.
	var polygon: PackedVector2Array = game.hand_card_polygon(card, true)
	return (polygon[0] + polygon[1]) * 0.5 + Vector2(0, 30)

func lane_point(lane: int) -> Vector2:
	return game.camera.unproject_position(game._response_slots()[lane].global_position)

## A real drag of a hand card to a Response lane: press, move over frames, release.
## Returns true when the real press picked the card up.
func drag_to_lane(card: Node, lane: int) -> bool:
	var start := hand_point(card)
	move_to(start)
	await process_frame
	button_event(start, true)
	await frames(2)
	var picked: bool = card.is_dragging
	var target := lane_point(lane)
	for i in 10:
		move_to(start.lerp(target, (i + 1) / 10.0))
		await process_frame
	await frames(10)
	button_event(target, false)
	await frames(2)
	# Headless has no real cursor, so the release cannot find the lane under it and the card goes back to
	# the hand. Finish the drop the way the release does over a lane (card_3d.gd _drop_card).
	var slot: Node3D = game._response_slots()[lane]
	if card.in_hand and game._get_card_in_slot(slot) == null and game.try_play_card(card):
		game.preparedness_actions.place_unit(card, slot)
	await frames(4)
	await mouse_away()
	return picked

func hand_card(id: String) -> Node:
	for card in game.get_hand_cards():
		if card.card_data.get("id", "") == id: return card
	return null

func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card): return str(card.card_data.get("id", "")))

func drill() -> Node:
	return director.get_node_or_null("Tutorial")

func step_index() -> int:
	return drill().index if drill() else -1

func empty_lane() -> int:
	for lane in 4:
		if game._get_card_in_slot(game._response_slots()[lane]) == null: return lane
	return -1

func my_turn() -> bool:
	return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]

func save_path() -> String:
	return director.persistence.save_path()

func settings_path() -> String:
	return game.visual_settings_path()

func find_button(parent: Node, text: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree(): return node
	return null

func new_scene(override: Variant) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames(2)
	paused = false
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	await frames()
	game.tutorial_override = override
	# The title is built in _ready, before the override is set. Build it again.
	director.show_title()
	await frames()

func reloaded() -> bool:
	return is_instance_valid(current_scene) and (not is_instance_valid(game) or current_scene != game)

## Waits for return_title's scene reload and picks up the new scene.
func wait_reload() -> bool:
	# The reload may already have freed the old scene, so read the members, not a captured local.
	var ok := await wait_until(reloaded)
	if ok:
		game = current_scene
		director = game.run_director
		await frames()
	return ok

func title_button(node_name: String) -> Button:
	return director.content.find_child(node_name, true, false)

## How to play, clicked for real. Returns true when the drill waits for the first draw.
func start_drill() -> bool:
	var how := title_button("HowToPlayButton")
	if how == null: return false
	await click_control(how)
	var saw_coin := false
	for i in CAP:
		if director.screen == "coin": saw_coin = true
		if game.phase == game.Phase.PLAYER_DRAW: break
		await process_frame
	expect(not saw_coin, "no coin screen in the drill")
	return drill() != null and game.phase == game.Phase.PLAYER_DRAW

func draw_by_click() -> void:
	await mouse_away()
	await click_control(game.get_node("HUD/Root/DeckDrawButton"))
	await wait_until(func(): return game.phase != game.Phase.PLAYER_DRAW)

func end_turn_by_click() -> void:
	await click_control(game.get_node("HUD/Root/EndTurnButton"))
	await wait_until(func(): return not my_turn())

## The next play phase: draws by a real click when the draw phase comes first.
func next_play_phase() -> bool:
	await wait_until(func(): return my_turn() or not director.battle_active)
	if game.phase == game.Phase.PLAYER_DRAW: await draw_by_click()
	return await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY)

func run() -> void:
	root.size = Vector2i(1440, 900)
	await new_scene(null)
	# A clean start: no mark, no run save from an older test run.
	DirAccess.remove_absolute(settings_path())
	director.persistence.discard()
	await check_flag_off()
	await check_first_run()
	await check_full_drill()
	await check_space_and_early_end()
	await check_loss()
	await check_skip_and_menu()
	await check_existing_save()
	await check_text_fits()
	DirAccess.remove_absolute(settings_path())
	finish()

## 1. Flag false, override null: nothing changes.
func check_flag_off() -> void:
	await new_scene(null)
	expect(title_button("HowToPlayButton") == null, "1: flag off: no How to play on the title")
	expect(not Tutorial.start(director), "1: flag off: tutorial start refuses")
	expect(drill() == null, "1: flag off: no drill node")
	await click_control(title_button("StartButton"))
	expect(await wait_until(func(): return director.screen == "characters"), "1: Start Game goes to characters")

## 14. First run: with no save and no mark, Start Game asks once; after Skip it does not ask again.
func check_first_run() -> void:
	await new_scene(true)
	await click_control(title_button("StartButton"))
	expect(director.screen == "confirm" and find_button(director.content, "Play the drill") != null,
		"14: first Start Game asks FIRST TIME?")
	expect(find_button(director.content, "Skip") != null, "14: the question has Skip")
	await click_control(find_button(director.content, "Skip"))
	expect(await wait_until(func(): return director.screen == "characters"), "14: Skip goes to characters")
	expect(Tutorial.is_done(game), "14: Skip stores the done mark")
	director.show_title()
	await frames()
	await click_control(title_button("StartButton"))
	expect(await wait_until(func(): return director.screen == "characters"), "14: second time no question")
	DirAccess.remove_absolute(settings_path())
	# "Play the drill" on the question starts the drill.
	await new_scene(true)
	await click_control(title_button("StartButton"))
	var play := find_button(director.content, "Play the drill")
	if play: await click_control(play)
	expect(await wait_until(func(): return drill() != null and game.phase == game.Phase.PLAYER_DRAW),
		"14: Play the drill starts the drill")
	if drill(): await click_control(drill().skip_button)
	expect(await wait_reload(), "14: Skip leaves the drill")
	expect(not Tutorial.is_done(game), "14: leaving by Skip does not store the mark")

## 2-5, 7-10, 13, 15: one drill from the title to the last step.
func check_full_drill() -> void:
	await new_scene(true)
	var how := title_button("HowToPlayButton")
	var start := title_button("StartButton")
	expect(how != null and start != null and how.get_index() == start.get_index() + 1,
		"2: How to play sits after Start Game")
	expect(await start_drill(), "2: a real click on How to play starts the drill")
	expect(hand_ids() == ["quick_dash", "fire_drill", "fire_truck"], "2: opening hand %s" % [hand_ids()])
	expect(game.get_hand_cards().map(func(c): return c.card_data.name) == ["Quick Dash", "Fire Drill", "Fire Hose"],
		"2: hand names")
	expect(game.enemy_hp == 8 and game.enemy_max_hp == 8, "2: Janitor HP is 8")
	expect(game.player_first, "2: you go first")
	expect(step_index() == 0 and drill().panel.visible, "2: step 1 is on screen")
	expect(drill().frame.visible, "2: the deck has a gold frame")
	var coins_before: int = director.coins
	# 15. The panel never takes a click: a click on its text reaches the game below.
	await check_click_through()
	# 3. A real press on a hand card before the draw: DRAW A CARD FIRST, the step stays.
	await mouse_away()
	var card: Node = game.get_hand_cards()[0]
	var point := hand_point(card)
	move_to(point)
	await process_frame
	button_event(point, true)
	await frames(2)
	expect(card._live_popups.any(func(p): return is_instance_valid(p) and p.text == "DRAW A CARD FIRST"),
		"3: a press before the draw shows DRAW A CARD FIRST")
	button_event(point, false)
	await frames(2)
	expect(step_index() == 0 and card.in_hand, "3: the step stays and the card stays in the hand")
	await draw_by_click()
	expect(await wait_until(func(): return step_index() == 1), "3: a real deck click moves to step 2")
	# 4. A real drag of a card to a lane.
	expect(await drag_to_lane(hand_card("quick_dash"), 1), "4: a real press picks the card up")
	expect(await wait_until(func(): return step_index() == 2), "4: a unit on the board moves to step 3")
	# 5. The End turn button.
	await end_turn_by_click()
	expect(await wait_until(func(): return step_index() == 3), "5: End turn moves to step 4")
	# Step 7 below needs no Fire Hose: take it out of the hand and the deck while the round plays.
	for definition in game.deck.duplicate():
		if definition.get("id", "") == "fire_truck": game.deck.erase(definition)
	var hose := hand_card("fire_truck")
	if hose:
		game.hand.erase(hose)
		hose.remove_from_group("cards")
		hose.queue_free()
		game.arrange_hand_centered()
	expect(await wait_until(func(): return step_index() == 4), "4: combat ends and step 5 shows")
	expect(await next_play_phase(), "the second turn comes")
	# 7. Step 5 gives a Fire Hose and names the real Fire unit.
	var fire: Node = drill().fire_unit()
	expect(fire != null, "7: a real Fire unit is on the Disaster side")
	if fire == null: return
	fire.card_data.name = "Blaze"
	await frames(2)
	expect(hand_card("fire_truck") != null, "7: a Fire Hose was put in the hand")
	expect(drill().text_label.text.contains("Blaze") and not drill().text_label.text.contains("Ember"),
		"7: step 5 names the Fire unit on the board: %s" % drill().text_label.text)
	# 8. A Douse unit across from the Fire unit, then its hit finishes step 6.
	var health_before := -1
	for round in 4:
		if step_index() > 5 or not director.battle_active: break
		fire = drill().fire_unit()
		var held := hand_card("fire_truck")
		if fire and held and step_index() == 4:
			var lane: int = game._threat_slots().find(fire.current_slot)
			if game._get_card_in_slot(game._response_slots()[lane]) == null:
				health_before = int(fire.card_data.health)
				await drag_to_lane(held, lane)
				expect(step_index() == 5, "8: the Fire Hose across from the Fire unit moves to step 6")
		await end_turn_by_click()
		await wait_until(func(): return my_turn() or step_index() > 5 or not director.battle_active)
		if step_index() <= 5: await next_play_phase()
	expect(step_index() >= 6, "8: a Douse hit on a Fire unit finishes step 6")
	expect(health_before > 0, "8: the hit came from a placed Fire Hose")
	# 9. Play on past round 5: no adaptation screen in the drill.
	var saw_buff := false
	for round in 6:
		if game.turn > 5 or not director.battle_active: break
		await next_play_phase()
		await end_turn_by_click()
		for i in CAP:
			if director.screen == "buff": saw_buff = true
			if my_turn() or not director.battle_active: break
			await process_frame
	expect(game.turn > 5 or not director.battle_active, "9: the drill reached round 6")
	expect(not saw_buff, "9: no adaptation screen in the drill")
	expect(step_index() == 7 or not director.battle_active, "7: the next draw moved on to step 8")
	expect(not FileAccess.file_exists(save_path()), "13: no run save is written during the drill")
	# 10. A win: step 9 with its one button. No supplies, no reward screen.
	await wait_until(func(): return my_turn())
	game.enemy_hp = 0
	game._check_game_over()
	await frames(4)
	expect(step_index() == drill().steps().size() - 1, "10: winning shows step 9")
	expect(drill().run_button.visible and not drill().skip_button.visible, "10: step 9 has Start a run")
	expect(director.coins == coins_before and director.screen != "reward" and not director.modal.visible,
		"10: no supplies and no reward screen")
	expect(game.visible, "10: the board stays in view behind step 9")
	await click_control(drill().run_button)
	expect(await wait_reload(), "10: Start a run returns to the title")
	expect(director.screen == "title", "10: the title is on screen")
	expect(Tutorial.is_done(game), "10: Start a run stores the done mark")
	expect(not FileAccess.file_exists(save_path()), "13: still no run save after the drill")
	DirAccess.remove_absolute(settings_path())

## 15. A probe that counts presses the GUI did not take, added last so it hears them first.
func check_click_through() -> void:
	var probe_script := GDScript.new()
	probe_script.source_code = "extends Node\nvar hits := 0\nfunc _unhandled_input(event):\n" \
		+ "\tif event is InputEventMouseButton and event.pressed: hits += 1\n"
	probe_script.reload()
	var probe: Node = probe_script.new()
	root.add_child(probe)
	var text_rect: Rect2 = drill().text_label.get_global_rect()
	await click(text_rect.get_center())
	expect(probe.hits == 1, "15: a click on the panel text passes through to the game")
	var tag_rect: Rect2 = drill().tag_label.get_global_rect()
	await click(tag_rect.get_center())
	expect(probe.hits == 2, "15: a click on the panel tag passes through to the game")
	probe.queue_free()
	expect(step_index() == 0, "15: the clicks changed nothing")

## 5 (second run) and 6: Space ends the turn; ending the turn at step 2 does not hang.
func check_space_and_early_end() -> void:
	await new_scene(true)
	expect(await start_drill(), "5b: the drill starts again")
	await draw_by_click()
	var text_before: String = drill().text_label.text
	# 6. End the turn at step 2 without playing.
	await end_turn_by_click()
	expect(step_index() == 1, "6: ending the turn early keeps step 2")
	expect(await next_play_phase(), "6: the next turn still comes")
	expect(step_index() == 1 and drill().text_label.text == text_before, "6: the step text stayed")
	expect(await drag_to_lane(game.get_hand_cards()[0], empty_lane()), "6: a real press picks a card up")
	expect(await wait_until(func(): return step_index() == 2), "6: the next turn still works")
	# 5b. Space moves step 3 on.
	await key(KEY_SPACE)
	expect(await wait_until(func(): return step_index() == 3), "5b: Space moves to step 4")
	await click_control(drill().skip_button)
	expect(await wait_reload(), "12: Skip at step 4 returns to the title")

## 11. Losing restarts the drill and writes nothing.
func check_loss() -> void:
	await new_scene(true)
	expect(await start_drill(), "11: the drill starts")
	await draw_by_click()
	game.player_hp = 0
	game._check_game_over()
	await frames(2)
	expect(drill() != null and drill().notice_label.visible
		and drill().notice_label.text == "That one got away. Try again.", "11: a loss shows one line")
	expect(director.screen != "result", "11: no defeat screen")
	expect(await wait_until(func(): return director.battle_active and game.phase == game.Phase.PLAYER_DRAW),
		"11: the drill starts again")
	expect(hand_ids() == ["quick_dash", "fire_drill", "fire_truck"] and game.enemy_hp == 8 and step_index() == 0,
		"11: the same battle from step 1")
	expect(game.player_hp > 0, "11: HP is back")
	expect(not FileAccess.file_exists(save_path()) and not Tutorial.is_done(game), "11: nothing was written")
	await draw_by_click()
	expect(step_index() == 1 and not drill().notice_label.visible, "11: the line goes after step 1")
	await click_control(drill().skip_button)
	expect(await wait_reload(), "12: Skip returns to the title")

## 12. Esc opens the menu with "Skip the drill"; it returns to the title.
func check_skip_and_menu() -> void:
	await new_scene(true)
	expect(await start_drill(), "12: the drill starts")
	# The map key still works in the drill (nothing is blocked); it opens and closes cleanly.
	await key(KEY_M)
	expect(director.screen == "map", "M opens the map in the drill")
	await key(KEY_M)
	expect(director.screen == "" and director.battle_active and not paused, "M closes it and the drill goes on")
	await key(KEY_ESCAPE)
	expect(director.screen == "menu", "12: Esc opens the menu")
	var skip := find_button(director.content, "Skip the drill")
	var back: Node = director.content.get_node_or_null("TitleButton")
	expect(skip != null and back != null and skip.get_index() == back.get_index() - 1,
		"12: Skip the drill sits above Return to starting screen")
	expect(director.content.get_node_or_null("DebugButton") == null, "12: Debug stays hidden")
	expect(not drill().panel.visible, "12: the panel hides while the menu is open")
	if skip: await click_control(skip)
	expect(await wait_reload(), "12: Skip the drill returns to the title")
	expect(director.screen == "title" and not FileAccess.file_exists(save_path()), "12: title, no save")

## 13. A run save that exists before the drill is the same after it.
func check_existing_save() -> void:
	await new_scene(null)
	director.new_run()
	await frames(10)
	director.persistence.checkpoint()
	var before := FileAccess.get_file_as_string(save_path())
	expect(not before.is_empty(), "13: a run save exists before the drill")
	await new_scene(true)
	var how := title_button("HowToPlayButton")
	var resume := title_button("ContinueButton")
	expect(how != null and resume != null and how.get_index() == resume.get_index() + 1,
		"13: How to play sits after Continue")
	expect(await start_drill(), "13: the drill starts with a save on disk")
	await draw_by_click()
	await frames(90)
	await click_control(drill().skip_button)
	expect(await wait_reload(), "13: Skip returns to the title")
	expect(FileAccess.get_file_as_string(save_path()) == before, "13: the run save is unchanged")
	director.persistence.discard()

## Text fits at 1280x720 and 1920x1080: inside the window, clear of the top bar and the type chart.
func check_text_fits() -> void:
	await new_scene(true)
	expect(await start_drill(), "fit: the drill starts")
	for window in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window
		await frames(4)
		for i in drill().steps().size():
			drill().index = i
			await frames(3)
			var rect: Rect2 = drill().panel.get_global_rect()
			var bar: Rect2 = game.get_node("HUD/TopBar").get_global_rect()
			var chart: Rect2 = game.get_node("HUD/Root/TypeChartPanel").get_global_rect()
			expect(root.get_visible_rect().encloses(rect), "fit %s step %d: panel inside the window" % [window, i + 1])
			expect(rect.position.y >= bar.end.y and not rect.intersects(chart),
				"fit %s step %d: clear of the top bar and chart" % [window, i + 1])
			expect(drill().text_label.get_line_count() <= 2, "fit %s step %d: at most two lines" % [window, i + 1])
	root.size = Vector2i(1440, 900)
	await click_control(drill().skip_button)
	await wait_reload()

func finish() -> void:
	if failures > 0:
		push_error("tutorial_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: tutorial_smoke (%d checks)" % checks)
	quit(0)
