extends SceneTree
## Four fixes from the flag-screen review: the tutorial Plans screen with a kit set, the boss name on the intent
## popup, the board pick prompt clear of the TYPES panel, and the hero shield and Janitor lock icons.
## Every flag stays false; features turn on only through the test overrides. Waits are frame loops capped at 600.
const BossRules = preload("res://scripts/boss_rules.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const LONG_PROMPT := "Click one ally. It and the adjacent ally on each side gain +1 attack this combat."
var game: Node
var director: Node
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func wait_frames(count: int) -> void:
	for i in mini(count, 600): await process_frame

func wait_until(predicate: Callable) -> bool:
	for i in 600:
		if predicate.call(): return true
		await process_frame
	return predicate.call()

# Real input, as tutorial_smoke sends it.
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

func click_control(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	move_to(point)
	await process_frame
	button_event(point, true)
	await process_frame
	button_event(point, false)
	await wait_frames(2)

func mouse_away() -> void:
	move_to(Vector2(4, 4))
	await wait_frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await wait_frames(2)

# A fresh game scene, as tutorial_smoke makes one. The old one is freed first.
func new_scene() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await wait_frames(2)
	paused = false
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	director = game.run_director
	await wait_frames(4)

# A real encounter, as boss_guardian_smoke starts one, waited to the player's turn.
func encounter(kind: String, floor_number: int, override: Variant) -> bool:
	director.start_character(0)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = floor_number
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.start_encounter(director.character_deck(0), kind, floor_number, 0)
	return await wait_until(func(): return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY])

# Same boss room fixture as boss_janitor_smoke and small_fixes_smoke.
func fresh(override: Variant) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = 1
	game.encounter_kind = "boss"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.turn = 1
	game.enemy_max_hp = 28
	game.enemy_hp = game.enemy_max_hp
	game._set_phase(game.Phase.PLAYER_PLAY)

# Real starter cards go into the hand through the game's own draw path, as small_fixes_smoke adds them.
func hand_of(count: int) -> Array:
	var starters: Array = director.character_deck(0)
	for i in count:
		var definition: Dictionary = starters[i].duplicate(true)
		definition.erase("locked_until")
		game.add_card_to_hand(definition)
	return game.get_hand_cards()

func intent_title() -> String:
	return director.boss_intent.get_parent().get_node("Title").text

func run() -> void:
	root.size = Vector2i(1440, 900)
	await new_scene()
	check(not director.persistence.enabled, "the test save path is the disposable one")
	await check_tutorial_plans()
	await new_scene()
	await check_intent_titles()
	await check_prompt_clear()
	await check_shield_and_lock()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("flag_screen_fixes_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: flag_screen_fixes_smoke (%d checks)" % checks)
	quit(0)

# 1. The tutorial with each kit set: P opens today's plans, brace and coordinate, and no kit id.
func check_tutorial_plans() -> void:
	game.tutorial_override = true
	game.leader_kit_override = "robin"
	game.plans.set_kit("robin")
	director.show_title()
	await wait_frames(4)
	check(Tutorial.start(director), "the tutorial starts")
	await wait_until(func(): return game.phase == game.Phase.PLAYER_DRAW)
	await mouse_away()
	await click_control(game.get_node("HUD/Root/DeckDrawButton"))
	check(await wait_until(func(): return game.phase == game.Phase.PLAYER_PLAY), "the tutorial reaches its play phase")
	for leader in ["robin", "sage", "kai", "sam"]:
		game.leader_kit_override = leader
		game.plans.set_kit(leader)
		check(game.plans.kit_id() == "" and game.plans.kit == leader, "%s: stored kit, today's plans" % leader)
		var kit_ids: Array = game.plans.unlocked.duplicate()
		check(kit_ids.all(func(id): return game.plans.definition(id).is_empty()),
			"%s: unlocked holds the kit's ids %s" % [leader, kit_ids])
		await mouse_away()
		await key(KEY_P)
		check(director.screen == "plans", "%s: P opens the plans screen (screen '%s')" % [leader, director.screen])
		var titles: Array = []
		if director.screen == "plans":
			for tile in director.content.get_node("Scroll/List").get_children():
				titles.append(tile.get_node("Box/PickButton").text)
		check(titles.size() == 2, "%s: two plans shown (got %s)" % [leader, titles])
		check(titles.any(func(text): return text.begins_with("Brace")), "%s: Brace is shown" % leader)
		check(titles.any(func(text): return text.begins_with("Coordinated Response")),
			"%s: Coordinated Response is shown" % leader)
		for id in kit_ids:
			check(not director.plan_ids().has(id), "%s: kit id %s is not shown" % [leader, id])
			check(not director.tactic_available(id), "%s: kit id %s is not available" % [leader, id])
		# plans.arm needs the id in unlocked, so a shown plan the rules cannot arm stays disabled.
		check(not director.tactic_available("brace"), "%s: brace is disabled while it is not unlocked" % leader)
		director.begin_tactic("brace")
		check(game.board_input.action.is_empty() and game.plans.armed.is_empty(),
			"%s: a disabled plan starts no pick" % leader)
		director.close_modal()
		await wait_frames(2)
	game.leader_kit_override = null
	game.plans.set_kit("")
	game.tutorial_override = null
	# A normal run with no kit lists unlocked as before.
	game.plans.reset_run()
	game.plans.unlocked.append("supply")
	check(director.plan_ids() == ["brace", "coordinate", "supply"], "no kit: the unlocked plans, in order")
	# Versus: only the chosen plans, no start plan added.
	game.encounter_kind = "versus"
	game.plans.unlocked.assign(["brace", "shelter"])
	check(director.plan_ids() == ["brace", "shelter"], "versus: only the chosen plans (got %s)" % [director.plan_ids()])

# 2. The intent popup title is the fight's boss name; the button reads "Close".
func check_intent_titles() -> void:
	var panel: Control = director.boss_intent.get_parent()
	check(panel.get_node("CloseButton").text == "Close", "the intent button reads Close")
	var fights := [["elite", 1, "guardian", "HALLWAY GUARDIAN"], ["boss", 1, "janitor", "JANITOR"],
		["boss", 3, null, "MIDNIGHT WARDEN"]]
	for fight in fights:
		check(await encounter(fight[0], fight[1], fight[2]), "%s: the fight reaches the player turn" % fight[3])
		await wait_frames(4)
		check(intent_title() == fight[3], "%s: the popup title is the boss name (got '%s')" % [fight[3], intent_title()])
		game.clear_battle()
		await wait_frames(2)

# 3. A board pick prompt ends left of the TYPES panel at 1280x800 and 1920x1080.
func check_prompt_clear() -> void:
	check(await encounter("elite", 1, "guardian"), "the prompt fight reaches the player turn")
	var chart: Control = game.get_node("HUD/Root/TypeChartPanel")
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		await wait_frames(12)
		game.board_input.pick(LONG_PROMPT, [], func(_card: Node): pass, Callable())
		await wait_frames(4)
		var prompt: Rect2 = director.board_prompt.get_global_rect()
		var types: Rect2 = chart.get_global_rect()
		check(director.board_prompt.visible, "%s: the pick shows the prompt" % size)
		check(prompt.end.x < types.position.x,
			"%s: prompt right edge %d is left of TYPES at %d" % [size, prompt.end.x, types.position.x])
		check(not prompt.intersects(types), "%s: prompt and TYPES do not overlap" % size)
		check(director.board_prompt_label.get_minimum_size().x <= prompt.size.x, "%s: the prompt text fits" % size)
		game.board_input.cancel()
		await wait_frames(2)
	root.size = Vector2i(1440, 900)
	await wait_frames(4)
	game.clear_battle()
	await wait_frames(2)

# 4. The hero shield beside the player HP, and the Janitor lock icon.
func check_shield_and_lock() -> void:
	await fresh("janitor")
	var health: Control = game.get_node("HUD/TopBar/PlayerHealth")
	game.plan_hero_barrier = 3
	var shield: Control = health.get_node_or_null("HeroShield")
	check(shield != null and shield.visible, "barrier 3: the shield shows")
	check(shield != null and shield.get_node("Count").text == "3", "barrier 3: the shield reads 3")
	game.plan_hero_barrier = 0
	check(shield != null and not shield.visible, "barrier 0: the shield is hidden")
	# Hero damage spends the shield: it follows the value.
	game.plan_hero_barrier = 2
	game._damage_side(true, 1)
	check(shield != null and shield.visible and shield.get_node("Count").text == "1", "a hit leaves the shield at 1")
	game.plans.finish_combat()
	check(shield != null and not shield.visible, "the end of combat hides the shield")
	# A Janitor lock: round 2 locks the newest hand card until round 4.
	var cards := hand_of(3)
	game.turn = 2
	BossRules.prepare_round(game)
	var locked: Array = cards.filter(func(card): return int(card.card_data.get("locked_until", 0)) == 4)
	check(locked.size() == 1, "round 2 locks one card")
	if locked.size() == 1:
		var card: Node = locked[0]
		check(card.card_data.get("lock_source", "") == "janitor", "the locked card has lock_source janitor")
		check(card._status_row.has_node("Delay") and not card._status_row.has_node("Sealed"),
			"a Janitor lock shows the delay icon, not the seal icon")
		var badge: Control = card._status_row.get_node_or_null("Delay")
		check(badge != null and badge.tooltip_text == "Locked by the Janitor. Playable from round 4.",
			"the delay icon says when it is playable (got '%s')" % [badge.tooltip_text if badge else ""])
	# A card sealed another way keeps the seal icon.
	var other: Node = cards[0]
	other.card_data.locked_until = 9
	other._refresh_face()
	check(other.card_data.get("lock_source", "") == "", "a sealed card has no lock_source")
	check(other._status_row.has_node("Sealed") and not other._status_row.has_node("Delay"),
		"a sealed card keeps the seal icon")
