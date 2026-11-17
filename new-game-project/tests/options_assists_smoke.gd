# Covers: the title Options button, the Auto camera and Auto draw settings (game_3d_manager.gd, run_director.gd,
# board_actions.gd). ASSISTS_DEFAULT_ON is true but off under tests/; tests reach "on" through
# game.assists_default_override, set before the game enters the tree. Buttons and keys go through real input.
# Every wait is capped at 600 frames.
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
func click_control(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	move_to(point)
	await process_frame
	button_event(point, true)
	await process_frame
	button_event(point, false)
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func find_button(text: String) -> Button:
	for node in director.content.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree(): return node
	return null

func settings_path() -> String:
	return game.visual_settings_path()

## A fresh game. The override must be set before _ready reads the settings file.
func new_scene(override: Variant, tutorial: Variant = null) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames(2)
	paused = false
	game = load("res://scenes/game_3d.tscn").instantiate()
	game.assists_default_override = override
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	game.disaster_is_human = false
	await frames()
	if tutorial != null:
		game.tutorial_override = tutorial
		director.show_title()
		await frames()

func my_turn() -> bool:
	return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]

## A singleplayer battle up to the first turn of the player.
func start_battle() -> bool:
	director.new_run()
	director.visit(0)
	return await wait_until(my_turn)

## Draws by the real deck button when the turn waits for it, then waits for the play phase.
func reach_play() -> bool:
	if not await wait_until(my_turn): return false
	if game.phase == game.Phase.PLAYER_DRAW and not game.auto_draw_on():
		await click_control(game.get_node("HUD/Root/DeckDrawButton"))
	return await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY)

## Space ends the turn; returns when combat is over and the round moved on.
func end_turn_through_combat() -> bool:
	await key(KEY_SPACE)
	if not await wait_until(func(): return game.phase == game.Phase.COMBAT): return false
	return await wait_until(func(): return game.phase != game.Phase.COMBAT)

## A real click on the HUD view button: 1 = W (forward), -1 = S (back).
func view_button(direction: int) -> void:
	var path := "HUD/Root/ViewForwardButton" if direction > 0 else "HUD/Root/ViewBackButton"
	await click_control(game.get_node(path))
	await frames(2)

## Lets the camera tween finish.
func settle() -> void:
	await frames(45)

func run() -> void:
	root.size = Vector2i(1440, 900)
	await new_scene(null)
	DirAccess.remove_absolute(settings_path())
	director.persistence.discard()
	await check_settings()
	await check_options_button()
	await check_camera_after_combat()
	await check_camera_after_board_action()
	await check_auto_draw()
	await check_versus_and_drill()
	DirAccess.remove_absolute(settings_path())
	director.persistence.discard()
	print("%s: %d checks, %d failures" % ["options_assists_smoke", checks, failures])
	if failures == 0: print("PASS: options_assists_smoke (%d checks)" % checks)
	game.queue_free()
	await frames(2)
	quit(1 if failures else 0)

## 1. The flag ships true but tests start with both off. A saved choice persists in the test config.
## Override true gives both on.
func check_settings() -> void:
	await new_scene(null)
	expect(game.ASSISTS_DEFAULT_ON == true, "1: the flag ships on")
	expect(game.running_under_tests() and not game.assists_default(), "1: tests/ command line, override null: off")
	expect(not game.auto_camera and not game.auto_draw, "1: no override under tests/: both assists start off")
	expect(settings_path().contains("test_visual_settings"), "1: the test uses its own settings file")
	game.set_visual_setting("auto_camera", true)
	game.set_visual_setting("auto_draw", true)
	await new_scene(null)
	expect(game.auto_camera and game.auto_draw, "1: saved choices load on the next start")
	game.set_visual_setting("auto_camera", false)
	game.set_visual_setting("auto_draw", false)
	await new_scene(true)
	expect(not game.auto_camera and not game.auto_draw, "1: a saved off wins over the default")
	DirAccess.remove_absolute(settings_path())
	await new_scene(true)
	expect(game.auto_camera and game.auto_draw, "1: override true and no saved choice: both on")
	DirAccess.remove_absolute(settings_path())
	# No override, no saved choice, tests/ command line: a normal game node starts with both off.
	await new_scene(null)
	expect(game.assists_default_override == null, "1: normal game node has no override")
	expect(not game.auto_camera and not game.auto_draw, "1: no override under tests/: auto camera and draw false")
	game.assists_default_override = true
	expect(game.assists_default(), "1: override true turns the default on")
	DirAccess.remove_absolute(settings_path())
	await new_scene(true)
	expect(game.auto_camera and game.auto_draw, "1: override true: auto camera and draw true")
	DirAccess.remove_absolute(settings_path())

## 2. Title Options opens GAME SETTINGS; Return and Esc go back to the title. The battle menu returns to the menu.
func check_options_button() -> void:
	await new_scene(null)
	var options: Button = director.content.find_child("OptionsButton", true, false)
	expect(options != null and not options.disabled, "2: the title Options button is enabled")
	if options == null: return
	await click_control(options)
	expect(director.screen == "settings", "2: a real click on Options opens GAME SETTINGS")
	for key_name in ["effects_enabled", "boss_fog_enabled", "auto_camera", "auto_draw"]:
		expect(director.content.find_child(key_name, true, false) is CheckButton, "2: toggle %s shown" % key_name)
	for key_name in ["auto_camera", "auto_draw"]:
		var hint: Label = director.content.find_child(key_name + "_hint", true, false)
		expect(hint != null and hint.text.length() <= 60, "2: %s has one short hint line" % key_name)
	var toggle: CheckButton = director.content.find_child("auto_draw", true, false)
	await click_control(toggle)
	expect(game.auto_draw, "2: a real click on Auto draw turns it on at once")
	await click_control(toggle)
	expect(not game.auto_draw, "2: a second click turns it off")
	var back := find_button("Return to title")
	expect(back != null, "2: from the title the button says Return to title")
	if back: await click_control(back)
	expect(director.screen == "title", "2: Return goes back to the title")
	options = director.content.find_child("OptionsButton", true, false)
	await click_control(options)
	await key(KEY_ESCAPE)
	expect(director.screen == "title", "2: Esc on title settings goes back to the title")
	# Battle menu: Game Settings, then Return to the game menu.
	expect(await start_battle(), "2: a battle starts")
	await key(KEY_ESCAPE)
	expect(director.screen == "menu", "2: Esc opens the battle menu")
	var settings := find_button("Game Settings")
	if settings: await click_control(settings)
	expect(director.screen == "settings", "2: Game Settings opens the same panel")
	back = find_button("Return to game menu")
	expect(back != null, "2: from the battle the button says Return to game menu")
	if back: await click_control(back)
	expect(director.screen == "menu", "2: Return goes back to the game menu")
	director.close_modal()
	await frames()
	DirAccess.remove_absolute(settings_path())

## 3. Camera after combat: auto goes to the desk, manual keeps today's view, W/S in combat is left alone.
func check_camera_after_combat() -> void:
	await new_scene(true)
	game.set_visual_setting("auto_draw", false)
	expect(await start_battle() and await reach_play(), "3: auto: the player can act")
	# A spell moves the camera to the board the same way.
	game.set_board_view(true)
	await settle()
	expect(await end_turn_through_combat(), "3: auto: combat ran")
	await settle()
	expect(game.view_mode == game.View.DESK, "3: auto: camera back at the desk after combat")
	# W/S during combat: auto camera leaves the view where the player put it.
	expect(await reach_play(), "3: auto: next turn")
	game.set_board_view(true)
	await settle()
	await key(KEY_SPACE)
	expect(await wait_until(func(): return game.phase == game.Phase.COMBAT), "3: hand: combat began")
	# The W/S keys are off in combat; the HUD view buttons still work.
	# S then W: the player picks the board by hand (there is no wide view now).
	await view_button(-1)
	expect(game.view_mode == game.View.DESK, "3: hand: the S button in combat gives the desk")
	await view_button(1)
	expect(game.view_mode == game.View.BOARD, "3: hand: the W button in combat gives the board")
	await wait_until(func(): return game.phase != game.Phase.COMBAT)
	await settle()
	expect(game.view_mode == game.View.BOARD, "3: hand: auto camera does not undo the player's view")
	# Manual camera: today's behaviour, the view from before combat comes back.
	DirAccess.remove_absolute(settings_path())
	await new_scene(null)
	expect(await start_battle() and await reach_play(), "3: manual: the player can act")
	game.set_board_view(true)
	await settle()
	expect(await end_turn_through_combat(), "3: manual: combat ran")
	await settle()
	expect(game.view_mode == game.View.BOARD, "3: manual: camera stays on the board as today")

## 4. Camera after a board pick: auto back to the desk, manual stays, a W/S change is left alone.
func check_camera_after_board_action() -> void:
	DirAccess.remove_absolute(settings_path())
	await new_scene(true)
	game.set_visual_setting("auto_draw", false)
	expect(await start_battle() and await reach_play(), "4: auto: the player can act")
	game.board_input.pick("Test pick", [], func(_card): pass, Callable())
	await settle()
	expect(game.view_mode == game.View.BOARD, "4: a board pick moves to the board")
	await key(KEY_ESCAPE)
	await settle()
	expect(game.board_input.action.is_empty(), "4: Esc ends the pick")
	expect(game.view_mode == game.View.DESK, "4: auto: camera back at the desk after the pick")
	game.board_input.pick("Test pick", [], func(_card): pass, Callable())
	await settle()
	# The W/S keys are off during a pick; the HUD view buttons still work.
	await view_button(-1)
	await view_button(1)
	expect(game.view_changed_by_hand, "4: hand: the view buttons count as a change by hand")
	await key(KEY_ESCAPE)
	await settle()
	expect(game.view_mode == game.View.BOARD, "4: hand: a W/S change is left alone")
	DirAccess.remove_absolute(settings_path())
	await new_scene(null)
	expect(await start_battle() and await reach_play(), "4: manual: the player can act")
	game.board_input.pick("Test pick", [], func(_card): pass, Callable())
	await settle()
	await key(KEY_ESCAPE)
	await settle()
	expect(game.view_mode == game.View.BOARD, "4: manual: camera stays on the board as today")

## Waits for the next draw phase of the player, with the hand size when it began. -1 when none came.
func next_draw_phase() -> int:
	if not await wait_until(func(): return game.phase == game.Phase.PLAYER_DRAW): return -1
	return game.get_hand_cards().size()

## 5. Auto draw: one card per turn after a short pause, never twice. Manual waits for the button.
func check_auto_draw() -> void:
	DirAccess.remove_absolute(settings_path())
	await new_scene(true)
	game.set_visual_setting("auto_camera", false)
	director.new_run()
	director.visit(0)
	for round_index in 2:
		var before := await next_draw_phase()
		expect(before >= 0, "5: round %d: a draw phase came" % round_index)
		if before < 0: return
		await frames(10)
		expect(game.phase == game.Phase.PLAYER_DRAW, "5: round %d: a short pause before the draw" % round_index)
		expect(await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY),
			"5: round %d: auto draw moves on to the play phase" % round_index)
		expect(game.get_hand_cards().size() == before + 1, "5: round %d: exactly one card drawn" % round_index)
		await frames(60)
		expect(game.get_hand_cards().size() == before + 1, "5: round %d: never a second card" % round_index)
		if round_index == 0: expect(await end_turn_through_combat(), "5: combat ran")
	DirAccess.remove_absolute(settings_path())
	await new_scene(null)
	director.new_run()
	director.visit(0)
	var hand := await next_draw_phase()
	await frames(120)
	expect(hand >= 0 and game.phase == game.Phase.PLAYER_DRAW, "5: manual: the turn waits for the button")
	expect(game.get_hand_cards().size() == hand, "5: manual: nothing drawn by itself")

## 6. Versus never auto draws. The drill waits for the manual draw but has auto camera on.
func check_versus_and_drill() -> void:
	DirAccess.remove_absolute(settings_path())
	await new_scene(true)
	director.start_versus_match()
	# The pre-match coin and side screens wait for players. Close them, then start the turn the real way.
	await frames(90)
	game.presentation.cancel_coin()
	game.presentation.blocking = false
	director.screen = ""
	game.reveal_versus_hand()
	game._begin_player_turn()
	var hand := await next_draw_phase()
	await frames(120)
	expect(hand >= 0 and game.phase == game.Phase.PLAYER_DRAW, "6: versus: the turn waits for the button")
	expect(game.get_hand_cards().size() == hand, "6: versus: nothing drawn by itself")
	expect(not game.auto_camera_on(), "6: versus: auto camera off")
	game.clear_battle()
	await new_scene(true, true)
	expect(Tutorial.start(director), "6: the drill starts")
	hand = await next_draw_phase()
	await frames(120)
	expect(hand >= 0 and game.phase == game.Phase.PLAYER_DRAW, "6: drill: waits for the manual draw")
	expect(game.auto_camera_on(), "6: drill: auto camera on")
	game.set_visual_setting("auto_camera", false)
	expect(game.auto_camera_on(), "6: drill: auto camera stays on while the assists default is on")
	game.clear_battle()
	DirAccess.remove_absolute(settings_path())
	await new_scene(null, true)
	expect(not game.auto_camera_on() or game.encounter_kind != "tutorial", "6: flag off: drill camera as today")
