# Covers: Kai's kit effect "rally" is shown as Huddle (leader_kits.gd), on the Drill screen and in the log.
# The "Rally the Team" card keeps its own name. The kit is reached only with game.plans.set_kit; flags stay false.
extends SceneTree
var game: Node
var director: Node
var failures := 0
var checks := 0

const LeaderKits = preload("res://scripts/leader_kits.gd")
const ALL_DRILL := ["fall_in", "double_time", "lane_swap", "rally", "duck"]

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int) -> void:
	for i in count: await process_frame

# Same battle fixture as leader_kai_smoke, with the whole Drill kit owned.
func fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "battle"
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.set_kit("kai")
	game.plans.auto_save = true
	game.plans.unlocked.assign(ALL_DRILL)
	game.plans.tokens = 0
	game.turn = 1
	game.player_hp = 20
	game.player_barrier = 0
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 3
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func card(name: String, lane: int, health: int) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup({"name":name, "type":"response", "element":"evac", "cost":1, "attack":2, "health":10})
	result.in_hand = false
	var slots: Array = game._response_slots()
	result.current_slot = slots[lane]
	result.global_position = slots[lane].global_position
	result.card_data.health = health
	return result

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(2)

func log_has(text: String) -> bool:
	return game.battle_log.any(func(line): return text in str(line))

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(not director.persistence.enabled, "the test save path is the disposable one")
	check_row()
	await check_tile()
	check_log()
	check_card_name()
	game.clear_battle()
	DirAccess.remove_absolute(director.persistence.save_path())
	if failures > 0:
		push_error("kai_huddle_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: kai_huddle_smoke (%d checks)" % checks)
	quit(0)

# 1. The kit row keeps its id "rally" and is named Huddle.
func check_row() -> void:
	var rows: Array = LeaderKits.kit("kai").effects.filter(func(row): return row.id == "rally")
	check(rows.size() == 1 and rows[0].name == "Huddle", "the kit row with id rally is named Huddle")

# 2. The Drill screen tile says Huddle, and no tile says Rally.
func check_tile() -> void:
	fixture()
	game.plans.tokens = 2
	await frames(3)
	await key(KEY_P)
	check(director.screen == "plans" and director.modal.visible, "P opens the Drill screen")
	var texts: Array = []
	for tile in director.content.get_node("Scroll/List").get_children():
		var button = tile.get_node_or_null("Box/PickButton")
		if button != null: texts.append(button.text)
	check("Huddle · 2 Tempo" in texts, "a tile reads Huddle · 2 Tempo")
	check(not texts.any(func(text): return "Rally" in text), "no tile says Rally")
	fixture()

# 3. Arming it and its combat both log Huddle, not Rally.
func check_log() -> void:
	fixture()
	game.plans.tokens = 2
	game.battle_log.clear()
	var left = card("Left", 0, 5)
	var center = card("Center", 1, 5)
	check(game.plans.use_kit_effect("rally", center), "Huddle can be armed on one unit")
	check(log_has("Armed Huddle for this combat."), "arming logs Huddle")
	game.plans.apply_combat()
	check(log_has("Huddle gives Center and its neighbours +1 attack"), "the combat line names Huddle")
	check(left.effective_attack() == 3, "Huddle still gives the neighbour +1")
	check(not log_has("Rally"), "no log line says Rally")
	game.plans.finish_combat()

# 4. The Rally the Team card (id rally) keeps its name.
func check_card_name() -> void:
	var cards = JSON.parse_string(FileAccess.get_file_as_string("res://data/response_expansion.json"))
	var rows: Array = cards.filter(func(row): return row.get("id", "") == "rally")
	check(rows.size() == 1 and rows[0].name == "Rally the Team", "the Rally the Team card keeps its name")
