extends Node
## "The Drill": a short first-run tutorial. One scripted battle, steps kept in data/tutorial_steps.json.
## It only watches the game and shows one line of text. It never blocks or swallows an input.
## Every way out (Skip, a win, the menu) ends in director.return_title(), which reloads the scene.

const UI = preload("res://scripts/ui_theme.gd")
## Off until the drill has been played by hand. Tests turn it on with game.tutorial_override.
const TUTORIAL_ENABLED := false
const STEPS_PATH := "res://data/tutorial_steps.json"
## Frames to wait after a loss before the same battle starts again.
const RESTART_FRAMES := 60
const PANEL_WIDTH := 600.0
## Just under the 52 px top bar.
const PANEL_TOP := 60.0
const FRAME_GAP := 4.0

var director: Node
var game: Node
var data: Dictionary = {}
## Frames left until a lost drill restarts. -1 means no restart is waiting.
var restart_wait := -1
## One short line shown after a loss, until the first step is done.
var notice := ""
## Which step is on screen, and what the game looked like when it began.
var index := 0
var step_deck := 0
var step_turn := 0
## Turn in which the step's card was last given, so a card is given at most once per turn.
var given_turn := -1
var seen_combat := false
## Fire units facing a Douse unit, with their health, saved while no combat runs.
var facing: Array = []
var won := false
var pressed := false
var chart_opened := false
var panel: PanelContainer
var tag_label: Label
var notice_label: Label
var text_label: Label
var skip_button: Button
var run_button: Button
var frame: Panel

## True when the drill may run: the test override if set, else the flag.
static func enabled(game_node) -> bool:
	if game_node.tutorial_override is bool: return game_node.tutorial_override
	return TUTORIAL_ENABLED

## Starts the drill from the title. Returns false when it may not start.
static func start(director_node) -> bool:
	var game_node: Node = director_node.game
	if not enabled(game_node): return false
	# The title, or the first-run question on it.
	if director_node.battle_active or director_node.run_active: return false
	if director_node.screen not in ["title", "confirm"]: return false
	if game_node.encounter_kind == "versus": return false
	var drill: Node = load("res://scripts/tutorial.gd").new()
	drill.name = "Tutorial"
	director_node.add_child(drill)
	drill.setup(director_node)
	return true

func setup(director_node: Node) -> void:
	director = director_node
	game = director.game
	# Keeps running while the menu pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = load_steps()
	build_panel()
	begin_battle()

## The step rows and the battle block from data/tutorial_steps.json.
static func load_steps() -> Dictionary:
	var file := FileAccess.open(STEPS_PATH, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## Sets the director up for a battle and starts the fixed drill battle.
func begin_battle() -> void:
	get_tree().paused = false
	director.encounter = "tutorial"
	director.battle_active = true
	director.modal.hide()
	director.screen = ""
	director.run_active = false
	var battle: Dictionary = data.get("battle", {})
	var opening := prep_cards(battle.get("prep_opening", []))
	var deck := prep_cards(battle.get("prep_deck", []))
	var disaster := disaster_cards(battle.get("disaster_deck", []))
	game.start_tutorial(opening, deck, disaster, int(battle.get("janitor_hp", 8)))
	go_to(0)

## Response cards from the run catalog, by id, in the given order.
func prep_cards(ids: Array) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for id in ids:
		var card: Dictionary = director.catalog_card(str(id))
		if not card.is_empty(): cards.append(card)
	return cards

## Disaster base cards from data/disaster_deck.json, by id, in the given order.
func disaster_cards(ids: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	game.load_deck_from_json("res://data/disaster_deck.json", rows)
	var cards: Array[Dictionary] = []
	for id in ids:
		for row in rows:
			if row.get("id", "") == id:
				cards.append(row.duplicate(true))
				break
	return cards

## Called by run_director.battle_finished. No supplies, rewards, save or defeat screen.
func battle_finished(battle_won: bool) -> void:
	if battle_won:
		won = true
		go_to(steps().size() - 1)
		return
	# Lost: the same battle starts again after a short wait. No run is lost.
	notice = "That one got away. Try again."
	restart_wait = RESTART_FRAMES

func _process(_delta: float) -> void:
	if game.encounter_kind != "tutorial": return
	if restart_wait >= 0:
		restart_wait -= 1
		# Wait in frames so the old combat has fully stopped before the new battle starts.
		if restart_wait < 0: begin_battle()
		refresh_panel()
		return
	var step := current()
	if not step.is_empty() and director.battle_active:
		give_card(step)
		if str(step.get("done", "")) == "super_hit_seen" and not super_hit_possible():
			# The Douse unit fell before it could hit: offer the Fire Hose step again.
			go_to(index - 1)
		elif check(str(step.get("done", ""))):
			go_to(index + 1)
	refresh_panel()

## Skip, a win or the menu: back to the title. The scene reload clears every bit of drill state.
func leave() -> void:
	director.return_title()

func steps() -> Array:
	return data.get("steps", [])

func current() -> Dictionary:
	if index < 0 or index >= steps().size(): return {}
	return steps()[index]

## Shows step i and saves the game state its check compares against.
func go_to(i: int) -> void:
	if i > 0: notice = ""
	index = clampi(i, 0, maxi(0, steps().size() - 1))
	step_deck = game.deck.size()
	step_turn = game.turn
	given_turn = -1
	seen_combat = false
	facing.clear()
	chart_opened = false

## The named checks. Each reads game state only, never which input caused it.
func check(done: String) -> bool:
	match done:
		"drew": return game.deck.size() < step_deck
		"unit_deployed": return not response_units().is_empty()
		"turn_ended": return game.phase in [game.Phase.ENEMY, game.Phase.COMBAT]
		"combat_ended":
			if game.phase == game.Phase.COMBAT: seen_combat = true
			return seen_combat and game.phase != game.Phase.COMBAT
		"douse_faces_fire": return not douse_fire_pairs().is_empty()
		"super_hit_seen": return super_hit()
		"next_draw": return game.turn > step_turn and game.phase == game.Phase.PLAYER_PLAY
		"battle_won": return won
		"button_pressed": return pressed
	return false

func response_units() -> Array:
	var units: Array = []
	for slot in game._response_slots():
		var card: Node = game._get_card_in_slot(slot)
		if card != null and card.is_alive(): units.append(card)
	return units

## The first live Fire unit on the Disaster side, or null.
func fire_unit() -> Node:
	for slot in game._threat_slots():
		var card: Node = game._get_card_in_slot(slot)
		if card != null and card.is_alive() and card.card_data.get("element", "") == "fire": return card
	return null

## Each lane where a live Douse unit faces a live Fire unit: [douse card, fire card].
func douse_fire_pairs() -> Array:
	var pairs: Array = []
	for lane in 4:
		var mine: Node = game._get_card_in_slot(game._response_slots()[lane])
		var theirs: Node = game._get_card_in_slot(game._threat_slots()[lane])
		if mine == null or theirs == null or not mine.is_alive() or not theirs.is_alive(): continue
		if mine.card_data.get("element", "") == "douse" and theirs.card_data.get("element", "") == "fire":
			pairs.append([mine, theirs])
	return pairs

## Read from the board before and after: outside combat, save each Fire unit that faces a Douse unit.
## In combat, a saved Fire unit that lost health was hit by that Douse unit, the only card across from it.
func super_hit() -> bool:
	if game.phase != game.Phase.COMBAT:
		facing = douse_fire_pairs().map(func(pair): return [pair[1], int(pair[1].card_data.health)])
		return false
	for saved in facing:
		var fire: Variant = saved[0]
		if not is_instance_valid(fire) or not fire.is_alive() or int(fire.card_data.health) < int(saved[1]):
			return true
	return false

## False on your play turn when no Douse unit faces a Fire unit any more.
func super_hit_possible() -> bool:
	return game.phase != game.Phase.PLAYER_PLAY or not douse_fire_pairs().is_empty()

## Puts the step's card in the hand on your play turn, once per turn, when you do not hold one.
func give_card(step: Dictionary) -> void:
	var id := str(step.get("give", ""))
	if id.is_empty() or game.phase != game.Phase.PLAYER_PLAY or given_turn == game.turn: return
	# The Fire Hose step waits for a real Fire unit. It never makes one.
	if str(step.get("done", "")) == "douse_faces_fire" and fire_unit() == null: return
	if game.get_hand_cards().size() >= game.HAND_SIZE_MAX: return
	given_turn = game.turn
	for card in game.get_hand_cards():
		if card.card_data.get("id", "") == id: return
	var definition: Dictionary = director.catalog_card(id)
	if not definition.is_empty(): game.add_card_to_hand(definition)

## The step sentence. The Fire Hose step names the real Fire unit on the board.
func step_text(step: Dictionary) -> String:
	var text := str(step.get("text", ""))
	var fire := fire_unit()
	if str(step.get("done", "")) == "douse_faces_fire" and fire != null:
		text = text.replace("Ember", str(fire.card_data.get("name", "Ember")))
	return text

# ------------------------------------------------------------------- panel
## One panel at the top centre, under the top bar: tag, sentence and Skip. Only the buttons take clicks.
func build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "TutorialPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.sharp_panel())
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.offset_top = PANEL_TOP
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	director.root.add_child(panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	tag_label = director.label("", 14, UI.GOLD)
	notice_label = director.label("", 16, UI.AMBER, true)
	text_label = director.label("", 18, UI.TEXT, true)
	for line in [tag_label, notice_label, text_label]:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(line)
	skip_button = director.button("Skip", leave, row)
	skip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# No keyboard focus, so Space always ends the turn and never presses Skip.
	skip_button.focus_mode = Control.FOCUS_NONE
	run_button = director.button("Start a run", start_run, row)
	run_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A plain gold frame around the control the step talks about.
	frame = Panel.new()
	frame.name = "TutorialFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = UI.GOLD
	box.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", box)
	director.root.add_child(frame)

## Fills the panel for the current step. It hides while a menu or popup is open.
func refresh_panel() -> void:
	var step := current()
	var last: bool = str(step.get("done", "")) == "button_pressed"
	panel.visible = not director.modal.visible and not step.is_empty()
	tag_label.text = str(step.get("tag", ""))
	if notice_label.text != notice: notice_label.text = notice
	notice_label.visible = not notice.is_empty()
	var text := step_text(step)
	if text_label.text != text: text_label.text = text
	skip_button.visible = not last
	run_button.visible = last
	var target := point_target(str(step.get("point", "none")))
	frame.visible = panel.visible and target != null and target.is_visible_in_tree()
	if frame.visible:
		var rect := target.get_global_rect().grow(FRAME_GAP)
		frame.global_position = rect.position
		frame.size = rect.size

## The control a step points at, or null for hand and none.
func point_target(point: String) -> Control:
	match point:
		"deck": return game.get_node("HUD/Root/DeckDrawButton")
		"end_turn": return game.get_node("HUD/Root/EndTurnButton")
		"chart":
			var chart: Control = game.get_node("HUD/Root/TypeChartPanel")
			# Open the chart once, so the step can point at its rows.
			if not chart_opened:
				chart_opened = true
				chart.set_collapsed(false)
			return chart
	return null

## The last step's button: the drill counts as done, then back to the title.
func start_run() -> void:
	pressed = true
	mark_done(game)
	leave()

## True once the drill was finished, or skipped at the first-run question.
static func is_done(game_node) -> bool:
	var settings := ConfigFile.new()
	settings.load(game_node.visual_settings_path())
	return bool(settings.get_value("tutorial", "done", false))

## Stores the "done" mark with the visual settings, never in the run save.
static func mark_done(game_node) -> void:
	var settings := ConfigFile.new()
	settings.load(game_node.visual_settings_path())
	settings.set_value("tutorial", "done", true)
	settings.save(game_node.visual_settings_path())
