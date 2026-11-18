extends SceneTree
## One list of usable plans (contingency_rules.plan_ids) and the Janitor lock text.
## 1. Tutorial with each kit set: the start plans, and they arm. 2. No kit: unlocked. 3. Kit battle: the kit list.
## 4. A Janitor lock keeps its own icon and text until something else changes locked_until.
## Every flag stays false; features turn on only through the test overrides. Waits are frame loops capped at 600.
const BossRules = preload("res://scripts/boss_rules.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const LeaderKits = preload("res://scripts/leader_kits.gd")
const CardScript = preload("res://scripts/card_3d.gd")
const LEADERS := ["robin", "sage", "kai", "sam"]
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

# Real input, as flag_screen_fixes_smoke sends it.
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

# A fresh game scene, as flag_screen_fixes_smoke makes one. The old one is freed first.
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

# Same boss room fixture as flag_screen_fixes_smoke, boss_janitor_smoke and small_fixes_smoke.
func fresh(kind: String, override: Variant) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = 1
	game.encounter_kind = kind
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.turn = 1
	game.enemy_max_hp = 28
	game.enemy_hp = game.enemy_max_hp
	game._set_phase(game.Phase.PLAYER_PLAY)

# A deployed ally in a lane, as contingency_plans_smoke makes one.
func ally(lane: int) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup({"name":"Helper", "type":"response", "element":"evac", "cost":1, "attack":2, "health":10})
	result.in_hand = false
	result.current_slot = game._response_slots()[lane]
	return result

# Real starter cards go into the hand through the game's own draw path, as small_fixes_smoke adds them.
func hand_of(count: int) -> Array:
	var starters: Array = director.character_deck(0)
	for i in count:
		var definition: Dictionary = starters[i].duplicate(true)
		definition.erase("locked_until")
		game.add_card_to_hand(definition)
	return game.get_hand_cards()

# A new round for the plans: nothing armed, nothing committed.
func clear_plans() -> void:
	game.plans.finish_combat()
	game.plans.committed_round = -1

func run() -> void:
	root.size = Vector2i(1440, 900)
	await new_scene()
	check(not director.persistence.enabled, "the test save path is the disposable one")
	await check_tutorial()
	await new_scene()
	await check_no_kit()
	await check_kit_battle()
	await check_janitor_lock()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("plan_ids_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: plan_ids_smoke (%d checks)" % checks)
	quit(0)

# 1. The tutorial with each kit set: today's start plans, and both arm with tokens. Kit ids are refused.
func check_tutorial() -> void:
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
	var helper := ally(0)
	for leader in LEADERS:
		game.leader_kit_override = leader
		game.plans.set_kit(leader)
		check(game.plans.kit_id() == "" and game.plans.kit == leader, "%s: stored kit, today's plans" % leader)
		check(game.plans.plan_ids() == game.plans.START_PLANS,
			"%s: plan_ids is the start list (got %s)" % [leader, game.plans.plan_ids()])
		clear_plans()
		game.plans.tokens = 2
		check(director.tactic_available("brace"), "%s: brace is available with tokens" % leader)
		check(game.plans.arm("brace", [helper]), "%s: brace arms" % leader)
		check(game.plans.armed.get("kind", "") == "brace" and game.plans.tokens == 1, "%s: brace spent 1" % leader)
		clear_plans()
		var result: Dictionary = game.preparedness_actions.use_tactic("coordinate", 0)
		check(result.ok, "%s: use_tactic accepts coordinate (got %s)" % [leader, result])
		check(game.plans.armed.get("kind", "") == "coordinate", "%s: coordinate is armed" % leader)
		clear_plans()
		for id in LeaderKits.kit(leader).start:
			check(not game.plans.plan_ids().has(id), "%s: kit id %s is not a plan" % [leader, id])
			check(not game.plans.arm(id, [helper]), "%s: kit id %s does not arm" % [leader, id])
			var refused: Dictionary = game.preparedness_actions.use_tactic(id, 0)
			check(refused.reason == "bad_tactic", "%s: use_tactic refuses %s (got %s)" % [leader, id, refused])
		check(game.plans.armed.is_empty(), "%s: nothing armed after the refusals" % leader)
	game.leader_kit_override = null
	game.plans.set_kit("")
	game.tutorial_override = null

# 2. No kit, battle: plan_ids is unlocked, with a plan unlocked later.
func check_no_kit() -> void:
	await fresh("battle", null)
	game.plans.reset_run()
	check(game.plans.plan_ids() == ["brace", "coordinate"], "no kit: the start plans")
	check(game.plans.unlock("supply"), "supply unlocks")
	check(game.plans.plan_ids() == ["brace", "coordinate", "supply"], "no kit: a later unlock is listed")
	check(game.plans.plan_ids() == Array(game.plans.unlocked), "no kit: plan_ids is unlocked")

# 3. Kit set, battle: plan_ids is the kit list, and today's plans stay out of the kit path.
func check_kit_battle() -> void:
	for leader in LEADERS:
		await fresh("battle", null)
		game.plans.reset_run()
		game.plans.set_kit(leader)
		check(game.plans.kit_id() == leader, "%s: the kit is in play" % leader)
		check(game.plans.plan_ids() == LeaderKits.kit(leader).start,
			"%s: plan_ids is the kit list (got %s)" % [leader, game.plans.plan_ids()])
		var helper := ally(0)
		game.plans.tokens = 2
		check(not game.plans.arm("brace", [helper]), "%s: brace does not arm with a kit" % leader)
		check(game.preparedness_actions.use_tactic("brace", 0).reason == "bad_tactic", "%s: brace is refused" % leader)
		check(not director.tactic_available("brace"), "%s: brace is not available" % leader)
	game.plans.set_kit("")

# 4. A Janitor lock: the delay icon and the Janitor text, then a later seal gives the seal look again.
func check_janitor_lock() -> void:
	await fresh("boss", "janitor")
	var cards := hand_of(3)
	game.turn = 2
	BossRules.prepare_round(game)
	var locked: Array = cards.filter(func(card): return int(card.card_data.get("locked_until", 0)) == 4)
	check(locked.size() == 1, "round 2 locks one card")
	if locked.size() != 1: return
	var card: Node = locked[0]
	check(int(card.card_data.get("janitor_until", 0)) == 4, "closing_time writes janitor_until")
	check(CardScript.is_janitor_lock(card.card_data), "the card counts as a Janitor lock")
	check(card._status_row.has_node("Delay") and not card._status_row.has_node("Sealed"),
		"a Janitor lock shows the delay icon")
	var badge: Control = card._status_row.get_node_or_null("Delay")
	var text := "Locked by the Janitor. Playable from round 4."
	check(badge != null and badge.tooltip_text == text,
		"the delay icon has the Janitor text (got '%s')" % [badge.tooltip_text if badge else ""])
	check(CardScript.seal_hint(card.card_data, 2) == text, "seal_hint has the Janitor text")
	# A later seal by anything else changes locked_until: the seal look and text come back.
	card.card_data.locked_until = 6
	card._refresh_face()
	check(not CardScript.is_janitor_lock(card.card_data), "a changed lock is no longer the Janitor's")
	check(card._status_row.has_node("Sealed") and not card._status_row.has_node("Delay"),
		"a resealed card shows the seal icon")
	check(CardScript.seal_hint(card.card_data, 2) == "Sealed by a Disaster effect. Cannot play this card until round 6.",
		"a resealed card has the seal text (got '%s')" % CardScript.seal_hint(card.card_data, 2))
