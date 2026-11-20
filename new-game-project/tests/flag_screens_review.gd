extends SceneTree
## Windowed review: saves a PNG of every flag-gated screen at two window sizes, so each one can be judged by eye.
## Not a _smoke file: run-suites.sh never runs it. Every flag stays false; features turn on only through the
## test overrides (game.boss_rule_override, game.leader_kit_override and game.plans.set_kit).
## Run: godot --path . -s tests/flag_screens_review.gd -- out=<folder>   (default user://frames)
## Add only=<name>[,<name>...] (for example only=kai-hud,kai-drill) to capture just those screens.
const BossRules = preload("res://scripts/boss_rules.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const SIZES := [Vector2i(1280, 800), Vector2i(1920, 1080)]
const FILLER := {"name":"Filler", "type":"response", "element":"evac", "cost":1, "attack":1, "health":3}

var game: Node
var director: Node
var out_dir := "user://frames"
var width := 0
var saved := 0
var skipped: Array = []
# Screen names from only=; empty means every screen.
var only: Array = []

func _initialize() -> void: call_deferred("run")

# True when one of these screens should be captured. Without only=, every screen is.
func wanted(screens: Array) -> bool:
	return only.is_empty() or screens.any(func(screen): return screen in only)

# Waits in frames, capped at 600.
func frames(count: int) -> void:
	for i in mini(count, 600): await process_frame

func wait_until(predicate: Callable) -> bool:
	for i in 600:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

# desk: the desk view, so every HUD frame uses the same camera. A board pick keeps the board view.
func capture(screen: String, desk: bool = true) -> void:
	if not wanted([screen]): return
	if desk: game.set_view(game.View.DESK)
	await mouse_away()
	await frames(30)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s-%d.png" % [out_dir, screen, width]
	if image == null or image.save_png(path) != OK:
		skipped.append("%s-%d (save failed)" % [screen, width])
		return
	saved += 1
	print("SAVED %s (%dx%d)" % [path, image.get_width(), image.get_height()])

func skip(screen: String, reason: String) -> void:
	skipped.append("%s-%d (%s)" % [screen, width, reason])
	print("SKIPPED %s-%d: %s" % [screen, width, reason])

# Input helpers, as leader_sam_smoke sends them.
func mouse_move(point: Vector2) -> void:
	var window := InputEventMouseMotion.new()
	window.position = root.get_final_transform() * point
	window.global_position = window.position
	Input.parse_input_event(window)
	Input.flush_buffered_events()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await process_frame

func mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
	await process_frame

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	await mouse_move(point)
	await mouse_button(point, true)
	await mouse_button(point, false)
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)

# The real cursor moves too, as the boss smokes warp it, or it can hover a hand card in the window.
func mouse_away() -> void:
	Input.warp_mouse(Vector2(4, 4))
	await mouse_move(Vector2(4, 4))

# A unit on the board, as the leader smokes place one.
func card(name: String, lane: int, health: int, side: String = "response") -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	var type := "response" if side == "response" else "disaster"
	result.setup({"name":name, "type":type, "element":"evac", "cost":1, "attack":2, "health":10})
	result.in_hand = false
	var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
	result.current_slot = slots[lane]
	result.global_position = slots[lane].global_position
	result.card_data.health = health
	# Board size and face, as boss_guardian_smoke places a unit.
	result._set_overlay(false)
	return result

# A fresh game scene. The old one is freed first.
func new_game() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames(2)
	paused = false
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director

func close_popup() -> void:
	if not game.board_input.action.is_empty(): game.board_input.cancel()
	director.close_modal()
	paused = false
	await frames(2)

# A real encounter, as the boss smokes start one, waited to the player's play phase.
func encounter(kind: String, character: int, floor_number: int = 1) -> bool:
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = floor_number
	game.disaster_is_human = false
	game.start_encounter(director.character_deck(character), kind, floor_number, 0)
	await wait_until(func(): return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY])
	if game.phase == game.Phase.PLAYER_DRAW:
		await click(game.get_node("HUD/Root/DeckDrawButton"))
	var ok := await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY)
	if not ok: print("  %s: phase %s, screen '%s'" % [kind, game.phase, director.screen])
	game.board_input.clear()
	await mouse_away()
	# Let the turn banner fade before any frame is taken.
	await frames(180)
	return ok

# A run with one leader kit, through the override, as the leader smokes start one.
func kit_run(kit: String, character: int) -> bool:
	await new_game()
	game.leader_kit_override = kit
	director.selected_character = character
	director.new_run()
	if game.plans.kit != kit: return false
	return await encounter("battle", character)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This optional visual review requires a rendering display")
		quit(2)
		return
	# A window can draw far above 60 fps; at 60 the 600-frame cap is about 10 s, enough for an enemy turn.
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="): out_dir = arg.substr(4).rstrip("/")
		if arg.begins_with("only="): only.assign(arg.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for size in SIZES:
		width = size.x
		root.size = size
		await frames(5)
		# A group whose screens are not wanted is skipped before its setup runs.
		if wanted(["guardian-p1", "guardian-p2"]): await guardian_screens()
		if wanted(["janitor-warn", "janitor-lock", "janitor-locked-card", "janitor-none"]): await janitor_screens()
		if wanted(["robin-hud", "robin-aid"]): await robin_screens()
		if wanted(["sage-hud", "sage-lab", "sage-pick"]): await sage_screens()
		if wanted(["kai-hud", "kai-drill"]): await kai_screens()
		if wanted(["sam-hud", "sam-skip"]): await sam_screens()
		if wanted(["tutorial-plans"]): await tutorial_screens()
	if is_instance_valid(game): game.queue_free()
	await frames(2)
	print("SAVED %d frames, SKIPPED %s" % [saved, skipped if not skipped.is_empty() else "none"])
	quit(0)

# 1. Elite fight with the Guardian rule: phase 1, then phase 2 at half HP.
func guardian_screens() -> void:
	await new_game()
	director.start_character(0)
	game.boss_rule_override = "guardian"
	if not await encounter("elite", 0):
		skip("guardian-p1", "no player turn")
		return
	await capture("guardian-p1")
	game.enemy_hp = ceili(game.enemy_max_hp / 2.0)
	game._refresh_bars()
	await capture("guardian-p2")

# 2. Floor 1 boss fight with the Janitor rule.
func janitor_screens() -> void:
	await new_game()
	director.start_character(0)
	game.boss_rule_override = "janitor"
	if not await encounter("boss", 0):
		skip("janitor-warn", "no player turn")
		return
	await capture("janitor-warn")
	# Round 2: the newest hand card is locked.
	game.turn = 2
	BossRules.prepare_round(game)
	var locked: Array = game.get_hand_cards().filter(
		func(item): return int(item.card_data.get("locked_until", 0)) == 4)
	if locked.is_empty():
		skip("janitor-lock", "no hand card was locked")
	else:
		await capture("janitor-lock")
		director.inspect_board_card(locked[0], true)
		await capture("janitor-locked-card")
		await close_popup()
	# Round 4 with every hand card sealed: nothing to lock.
	for item in game.get_hand_cards(): item.card_data.locked_until = 9
	game.turn = 4
	BossRules.prepare_round(game)
	if BossRules.intent(game).contains("nothing to lock"):
		await capture("janitor-none")
	else:
		skip("janitor-none", "intent was '%s'" % BossRules.intent(game))

# 3. Robin's Aid kit: the HUD, then the Aid screen opened with P.
func robin_screens() -> void:
	if not await kit_run("robin", 3):
		skip("robin-hud", "the Robin run did not start")
		return
	game.plans.tokens = 1
	card("Hurt", 0, 5)
	await capture("robin-hud")
	await key(KEY_P)
	if director.screen == "plans": await capture("robin-aid")
	else: skip("robin-aid", "P did not open the Aid screen")
	await close_popup()

# 4. Sage's Lab kit: the Lab screen, the Nick pick prompt, the HUD with Samples.
func sage_screens() -> void:
	if not await kit_run("sage", 2):
		skip("sage-lab", "the Sage run did not start")
		return
	game.plans.tokens = 1
	card("Foe", 1, 9, "disaster")
	await capture("sage-hud")
	await key(KEY_P)
	if director.screen != "plans":
		skip("sage-lab", "P did not open the Lab screen")
		return
	await capture("sage-lab")
	var nick: Button = director.content.get_node("Scroll/List").get_child(0).get_node("Box/PickButton")
	await click(nick)
	if game.board_input.action.is_empty(): skip("sage-pick", "Nick did not ask for a unit")
	else: await capture("sage-pick", false)
	await close_popup()

# 5. Kai's Drill kit: the HUD after one lane change fills Tempo to 3/3, then the Drill screen opened with P.
func kai_screens() -> void:
	if not await kit_run("kai", 1):
		skip("kai-hud", "the Kai run did not start")
		skip("kai-drill", "the Kai run did not start")
		return
	game.plans.tokens = 2
	var ally := card("Runner", 0, 5)
	game.apply_relocation(ally, game._response_slots()[2], null)
	await frames(2)
	if director.plans_button.get_node("CountLabel").text == "3/3": await capture("kai-hud")
	else: skip("kai-hud", "count read '%s'" % director.plans_button.get_node("CountLabel").text)
	# The Drill screen with Huddle owned, as kai_huddle_smoke owns it, so its tile is in the frame.
	game.plans.unlocked.append("rally")
	await key(KEY_P)
	if director.screen == "plans": await capture("kai-drill")
	else: skip("kai-drill", "P did not open the Drill screen")
	await close_popup()

# 6. Sam's Last Bell kit: the HUD with the gauge and pips, then a skipped turn (draw 1, block 3).
func sam_screens() -> void:
	if not await kit_run("sam", 0):
		skip("sam-hud", "the Sam run did not start")
		return
	# Energy above the cap, as check_frames_above_cap in leader_sam_smoke sets it: the gauge reads 6 / 4.
	game.energy_cap = 4
	game.preparedness = 6
	game.plans.tokens = 2
	await capture("sam-hud")
	# An empty Bell, as the skip check in leader_sam_smoke starts.
	game.plans.tokens = 0
	game.preparedness = game.energy_cap
	if game.deck.is_empty(): game.deck.assign([FILLER.duplicate()])
	game.plans.bank_unused_energy()
	if game.plan_hero_barrier == 3: await capture("sam-skip")
	else: skip("sam-skip", "the turn was not a skip")

# 7. The tutorial with a kit set: P shows today's plans.
func tutorial_screens() -> void:
	await new_game()
	game.tutorial_override = true
	game.leader_kit_override = "robin"
	game.plans.set_kit("robin")
	director.show_title()
	await frames(4)
	if not Tutorial.start(director):
		skip("tutorial-plans", "the tutorial did not start")
		return
	await wait_until(func(): return game.phase == game.Phase.PLAYER_DRAW)
	await mouse_away()
	await click(game.get_node("HUD/Root/DeckDrawButton"))
	await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY)
	# The kit's ids stay in unlocked; show_plans lists today's plans instead of them.
	await key(KEY_P)
	if director.screen == "plans": await capture("tutorial-plans")
	else: skip("tutorial-plans", "P did not open the plans screen")
	await close_popup()
	game.leader_kit_override = null
	game.plans.set_kit("")
