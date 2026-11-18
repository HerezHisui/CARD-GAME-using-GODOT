extends SceneTree
## Two small fixes: no leader kit in the tutorial, and the Janitor's intent when nothing can be locked.
const BossRules = preload("res://scripts/boss_rules.gd")
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

# Real starter cards go into the hand through the game's own draw path. The last one is the newest.
func hand_of(count: int) -> Array:
	var starters: Array = director.character_deck(0)
	for i in count:
		var definition: Dictionary = starters[i].duplicate(true)
		definition.erase("locked_until")
		game.add_card_to_hand(definition)
	return game.get_hand_cards()

func locked(cards: Array, until: int) -> Array:
	return cards.filter(func(card): return int(card.card_data.get("locked_until", 0)) == until)

# Same boss room fixture as boss_janitor_smoke.
func fresh(override: Variant, floor_number: int = 1) -> void:
	game.clear_battle()
	await wait_frames(2)
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	director.floor_number = floor_number
	game.encounter_kind = "boss"
	game.boss_rule_override = override
	game.disaster_is_human = false
	game.player_first = true
	game.turn = 1
	game.enemy_max_hp = 28 if floor_number == 1 else 31
	game.enemy_hp = game.enemy_max_hp
	game._set_phase(game.Phase.PLAYER_PLAY)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	check_flag_off()
	check_tutorial_kits()
	director.start_character(0)
	Input.warp_mouse(Vector2(4, 4))
	await check_nothing_to_lock()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("small_fixes_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: small_fixes_smoke (%d checks)" % checks)
	quit(0)

# 2. Flag false and override null: no kit in any room.
func check_flag_off() -> void:
	check(game.leader_kit_override == null, "the override starts as null")
	director.new_run()
	for kind in ["battle", "elite", "boss", "tutorial", "versus"]:
		game.encounter_kind = kind
		check(game.plans.kit_id() == "", "flag off: no kit in a %s room" % kind)
	check(game.plans.kit == "", "flag off: no stored kit")

# 1. Every leader kit: off in the tutorial, back in the next battle.
func check_tutorial_kits() -> void:
	for leader in ["robin", "sage", "kai", "sam"]:
		game.leader_kit_override = leader
		game.plans.set_kit(leader)
		game.encounter_kind = "tutorial"
		check(game.plans.kit_id() == "", "%s: no kit in the tutorial" % leader)
		check(game.plans.kit == leader, "%s: the stored kit stays in the tutorial" % leader)
		game.encounter_kind = "battle"
		check(game.plans.kit_id() == leader, "%s: the kit is back in a battle" % leader)
	game.plans.set_kit("")
	game.leader_kit_override = null

# 3 to 5. A floor 1 lock round: the intent says a card is locked only when one is.
func check_nothing_to_lock() -> void:
	# 3. Empty hand.
	await fresh("janitor")
	game.turn = 2
	BossRules.prepare_round(game)
	check(game.get_hand_cards().is_empty(), "empty hand: the hand is empty")
	var text := BossRules.intent(game)
	check(text == "CLOSING TIME: nothing to lock. Next lock in 2 rounds.",
		"empty hand: nothing to lock (got '%s')" % text)
	game.enemy_hp = 14
	text = BossRules.intent(game)
	check(text.begins_with("NIGHT SHIFT. CLOSING TIME: nothing to lock."),
		"night shift keeps the prefix (got '%s')" % text)

	# 4. One sealed card only.
	await fresh("janitor")
	var cards := hand_of(1)
	cards[0].card_data.locked_until = 9
	game.turn = 2
	BossRules.prepare_round(game)
	check(int(cards[0].card_data.locked_until) == 9, "sealed hand: the seal is not changed")
	check(locked(cards, 4).is_empty(), "sealed hand: no card is locked")
	text = BossRules.intent(game)
	check(text == "CLOSING TIME: nothing to lock. Next lock in 2 rounds.",
		"sealed hand: nothing to lock (got '%s')" % text)

	# 5. A normal hand card: it is locked and the old text stays.
	await fresh("janitor")
	cards = hand_of(1)
	game.turn = 2
	BossRules.prepare_round(game)
	check(locked(cards, 4).size() == 1, "normal hand: the card is locked until round 4")
	text = BossRules.intent(game)
	check(text == "CLOSING TIME: one card is locked. Next lock in 2 rounds.", "normal hand: old text (got '%s')" % text)
	# The panel shows the same line.
	game.board_input.clear()
	await wait_frames(2)
	check(director.boss_intent.text == text, "the intent panel shows it (got '%s')" % director.boss_intent.text)
