extends CanvasLayer
## Owns the persistent run. Battle copies never mutate the collection.
const RouteCanvas = preload("res://scripts/route_canvas.gd")
const CardFace = preload("res://scripts/card_3d.gd")
const Rules = preload("res://scripts/battle_rules.gd")
const TITLE_ART_PATH := "res://assets/title_screen.png"
static var start_after_reload := false
static var last_character := 0
const DECISIONS := ["coin", "reward", "shop", "event", "upgrade", "upgrade_preview", "result", "choice", "buff", "floor_buff", "intel", "title", "title_help", "characters", "character_preview", "victory", "inspect", "plans", "remove", "remove_confirm", "contingency_reward"]
const MAP_ROWS := 11
const MAX_UPGRADES := 2
const CHARACTERS := [
	{"name":"Steve · Student", "available":true, "description":"Balanced training. Units start with +1 health.", "buff":"cadet", "deck":[]},
	{"name":"Evacuation Club · Leader", "available":false, "description":"Evac formations, movement and draw. Matching neighbors gain +1 extra damage.", "buff":"marshal", "deck":["quick_dash", "quick_dash", "fire_drill", "fire_drill", "lane_marshal", "lane_marshal", "runner", "runner", "evacuation", "tutor", "shelter_brace", "rally"]},
	{"name":"Science Club · Leader", "available":false, "description":"Burn and Poison combinations. Apply +2 Burn and +1 Poison; units lose 1 health.", "buff":"chemist", "deck":["fire_truck", "fire_truck", "steam_team", "steam_team", "hazmat_team", "hazmat_team", "debris_clearance", "debris_clearance", "heat_seeker", "toxin_hunter", "cleanse", "tutor"]},
	{"name":"Safety Club · Leader", "available":false, "description":"Brace formations and Strength. Surviving blockers retaliate for 1 fixed damage.", "buff":"warden", "deck":["shelter_brace", "shelter_brace", "shard_barrier", "shard_barrier", "captain", "captain", "drill_leader", "momentum_team", "fire_truck", "field_medic", "rally", "cleanse"]}
]
var selected_character := 0
const SORT_KEYS := ["name", "element", "cost", "attack", "health", "modifier", "acquired"]
const GOLD := Color("c9aa70")
const TEAL := Color("75d6c6")
const BG := Color("0c141f")
var game: Node
var collection: Array[Dictionary] = []
var acquisition_serial := 0
var reward_stock: Array[Dictionary] = []
var run_active := false
var persistence: Node
var catalog: Array[Dictionary] = []
var rooms: Array = []
var cleared: Array = []
var current := -1
var coins := 35
var floor_number := 1
var run_seed := 0
var rng := RandomNumberGenerator.new()
var battle_active := false
var encounter := "battle"
var root: Control
var modal: PanelContainer
var content: VBoxContainer
var summary: Label
var prep: ProgressBar
var threat: ProgressBar
var screen := ""
var inspected_face: TextureRect
var saved_content: VBoxContainer
var saved_screen := ""
var map_button: Button
var menu_button: Button
var action_cancel: Callable
var buff_choices: Array = []
var intel_revealed := false
var idle_hint: Label
var boss_intent: Label
var plans_button: Button
var remove_origin := ""
var remove_index := -1
var board_prompt: PanelContainer
var board_prompt_label: Label
var extraction_card: Node
var unlock_after := "cards"
var event_key := ""
var event_type := "locked"
var event_cards: Array[Dictionary] = []
var event_resolved := false
const EVENT_TYPES := ["locked", "radio", "rooftop", "science", "infirmary", "lost_found"]
var deck_sort := 0
var upgrade_sort := 0
var deck_descending := false
var upgrade_descending := false
var viewed_cards: Array[Dictionary] = []
var shop_key := ""
var shop_stock: Array[Dictionary] = []
var shop_purchased: Array = []

func _ready() -> void:
	game = get_parent()
	selected_character = last_character
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	persistence = preload("res://scripts/run_save.gd").new()
	add_child(persistence)
	persistence.setup(self)
	get_tree().auto_accept_quit = false
	game.load_deck_from_json("res://data/starter_deck.json", catalog)
	game.load_deck_from_json("res://data/response_expansion.json", catalog)
	# Utility cards belong to the reward pool, preserving the original starter deck.
	catalog.append({"id":"supply_cache", "name":"Supply Cache", "type":"response", "element":"clearance", "cost":2, "attack":0, "health":1, "effect":"draw", "utility":true})
	catalog.append({"id":"emergency_exit", "name":"Emergency Exit", "type":"response", "element":"evac", "cost":1, "attack":0, "health":1, "effect":"move", "utility":true})
	if start_after_reload:
		start_after_reload = false
		new_run()
	else:
		game.clear_battle()
		show_title()

func show_title() -> void:
	game.presentation.clear_banner()
	get_tree().paused = false
	battle_active = false
	reset_panel("MIDNIGHT DRRILLS", "THE SCHOOL AFTER DARK", "title")
	content.get_child(0).add_theme_font_size_override("font_size", 54)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 50)
	content.add_child(body)
	var menu := VBoxContainer.new()
	menu.custom_minimum_size.x = 340
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 12)
	body.add_child(menu)
	var has_save: bool = persistence.has_run()
	if has_save:
		var saved: Dictionary = persistence.read_save()
		menu.add_child(label("UNFINISHED RUN · FLOOR %d" % int(saved.director.floor_number), 17, TEAL))
		button("Continue run", continue_saved_run, menu).grab_focus()
		button("Abandon run…", confirm_abandon, menu)
	else: button("Singleplayer · Start game", show_characters, menu).grab_focus()
	var multiplayer := button("Multiplayer · Coming soon", Callable(), menu)
	multiplayer.disabled = true
	button("How to play", show_title_help, menu)
	button("Quit", quit_game, menu)
	var scenery := preload("res://scripts/title_backdrop.gd").new()
	scenery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scenery)
	if ResourceLoader.exists(TITLE_ART_PATH):
		var art := TextureRect.new()
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = load(TITLE_ART_PATH)
		scenery.add_child(art)
	content.add_child(label("BUILD YOUR RESPONSE. CONTAIN THE DISASTER. SURVIVE THE NIGHT.", 16, TEAL))

func continue_saved_run() -> void:
	if not persistence.resume(): show_title()

func confirm_abandon() -> void:
	reset_panel("ABANDON THIS RUN?", "Your saved deck, school route and battle progress will be cleared. Start again from character selection.", "title_help")
	button("Abandon run", abandon_run, content)
	button("Keep my run", show_title, content)

func abandon_run() -> void:
	run_active = false
	persistence.discard()
	game.clear_battle()
	collection.clear()
	show_title()

func show_characters() -> void:
	reset_panel("CHOOSE YOUR CHARACTER", "Each character has a 12-card starter deck and a permanent starting perk.", "characters")
	for i in CHARACTERS.size():
		var character: Dictionary = CHARACTERS[i]
		button(character.name + "\n" + (character.description if character.available else "AVAILABLE SOON · " + character.description), show_character_preview.bind(i), content).disabled = not character.available
	button("Back", show_title, content)

func character_deck(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if index == 0:
		game.load_deck_from_json("res://data/starter_deck.json", result)
	else:
		for id in CHARACTERS[index].deck:
			for card in catalog:
				if card.id == id:
					result.append(card.duplicate(true))
					break
	return result

func show_character_preview(index: int) -> void:
	reset_panel(CHARACTERS[index].name, CHARACTERS[index].description, "character_preview")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for card in character_deck(index): _card_tile(card, grid)
	button("Begin run" if CHARACTERS[index].available else "Available soon", start_character.bind(index), content).disabled = not CHARACTERS[index].available
	button("Back to characters", show_characters, content)

func start_character(index: int) -> void:
	if index < 0 or index >= CHARACTERS.size() or not CHARACTERS[index].available: return
	selected_character = index
	last_character = index
	new_run()

func help_section(parent: Node, title: String, explanation: String) -> void:
	parent.add_child(label(title, 21, GOLD))
	var text := label(explanation, 17)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(text)

func show_title_help(page_index: int = 0) -> void:
	reset_panel("HOW TO PLAY", "Steve's guide to surviving the school after dark.", "title_help")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	content.add_child(tabs)
	var titles := ["Start a run", "Battle and Plans", "Cards and effects", "Controls"]
	for i in titles.size(): button(titles[i], show_title_help.bind(i), tabs).disabled = i == page_index
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 14)
	scroll.add_child(sections)
	match page_index:
		0:
			help_section(sections, "1  Pick Steve and follow the map", "Start Singleplayer and preview Steve's 12-card deck. Choose a glowing room, then climb upward through connected rooms toward the boss.")
			help_section(sections, "2  Build your deck between battles", "Wins offer a card reward and supplies. Shops allow multiple purchases. Workshops preview upgrades; each card copy can upgrade twice. Rests offer healing, training or free card removal.")
			help_section(sections, "3  Prepare for the Midnight Warden", "Clear the first two floor bosses, then face a three-phase final boss on floor three. Read its announced attacks and prepare healing, barriers and ways around guardian Taunt.")
			help_section(sections, "Continue when you are ready", "Return to the starting screen or quit to keep the last stable checkpoint. Continue resumes it. Abandon clears it only after confirmation.")
		1:
			help_section(sections, "Draw, deploy, end your turn", "Draw first when prompted. Drag a Response card onto an empty lower lane. Its energy cost is paid only after a successful play. End Turn resolves the remaining enemy actions and combat.")
			help_section(sections, "Your resources", "Preparedness starts at 3 energy, refills each round and grows toward a base cap of 7. Disasters spend tension and sacrifice deployed cards to evolve. The first side alternates each round and attacks first.")
			help_section(sections, "Save now, respond later", "End a turn with at least 2 unused energy to bank 1 Plan. Hold up to 2 and arm one tactic per round with P. Most cost 1 Plan; Precision Team costs 2. Target allies directly on the board.")
			help_section(sections, "Grow your options", "Elite and boss victories unlock more tactics for this run. Every 5 rounds you choose a battle-only adaptation. Floor rewards last the run. Strong buffs can have drawbacks.")
		2:
			help_section(sections, "Match the right response", "Evac counters Earthquake. Douse counters Fire. Clearance counters Flood. Brace counters Typhoon. Strong matchups deal double damage; weak ones deal half. Inspect a card for its exact matchups.")
			help_section(sections, "Blocking and attack effects", "A blocker stops all ordinary hero damage, even if destroyed. Piercing also hits the opposing health pool. Sluggish attacks once every two rounds. Strength adds attack. Neighboring matching types gain a formation bonus.")
			help_section(sections, "Damage over time", "Burn deals its stacks, then halves them. Poison deals its stacks, then loses 1. Both trigger at round start. Bleed deals its stacks after an attack, then loses 1. These hits bypass armor and Barrier.")
			help_section(sections, "Protect and disrupt", "Armored reduces attack damage; Fragile increases it. Barrier absorbs attack damage, up to 3 stored protection. Regenerating restores health. Seal and cost disruption affect held cards only. Scouting reveals the enemy hand.")
		3:
			help_section(sections, "W / S  Camera views", "Press W to move from Room to Table to Overhead. Press S to move back. Table is the normal playing view; Room pulls back to show the Janitor and classroom. Camera controls pause while dragging or choosing a board target.")
			help_section(sections, "Mouse  Cards and targets", "Drag hand cards to open friendly lanes. Click deployed cards to inspect them. Relocation uses direct dragging. Other allied targets use board clicks. Right-click cancels a drag; Esc cancels a target selection.")
			help_section(sections, "D / P / L  Your tools", "D opens your collection and battle piles. Graveyards are available only during battle. P opens Plans. L opens the combat log. Card lists support sorting, including Recently added.")
			help_section(sections, "M / Esc / Space  Navigation", "M opens and closes the map during battle. Between encounters, the full map remains your home screen. Esc opens the menu or closes an overlay. Space or End Turn finishes your turn. Overlays pause an active battle.")
	button("Back to starting screen", show_title, content)

func style(color: Color = BG, border: Color = Color("344550")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func label(text: String, font_size: int = 20, color: Color = Color("e4e7e9")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func button(text: String, action: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 42)
	if action.is_valid(): b.pressed.connect(action)
	parent.add_child(b)
	game.presentation.button_feedback(b)
	return b

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	theme.default_font = font
	theme.default_font_size = 18
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "Button", style(Color("233a47") if state == "hover" else BG, TEAL if state == "focus" else Color("52606a")))
	root.theme = theme
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 78
	header.add_theme_stylebox_override("panel", style(Color(0.04, 0.07, 0.11, 0.96)))
	root.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	header.add_child(row)
	var brand := VBoxContainer.new()
	row.add_child(brand)
	brand.add_child(label("MIDNIGHT DRRILLS", 22, GOLD))
	brand.add_child(label("THE SCHOOL AFTER DARK", 11, Color("8a9cab")))
	summary = label("", 16)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(summary)
	button("Deck  [D]", show_deck, row)
	button("Log  [L]", show_battle_log, row)
	map_button = button("School map  [M]", toggle_map, row)
	menu_button = button("Menu  [Esc]", show_menu, row)
	prep = _gauge("PREPAREDNESS", true, TEAL)
	threat = _gauge("TENSION", false, Color("da857c"))
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 45
	modal.offset_right = -45
	modal.offset_top = 94
	modal.offset_bottom = -28
	modal.add_theme_stylebox_override("panel", style(Color(0.04, 0.07, 0.11, 0.99), GOLD))
	root.add_child(modal)
	modal.gui_input.connect(_modal_input)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	modal.add_child(content)
	idle_hint = label("Choose your next room with School map  [M]", 20, TEAL)
	idle_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(idle_hint)
	idle_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	idle_hint.offset_top = -60
	idle_hint.offset_bottom = -20
	var intent_panel := PanelContainer.new()
	intent_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	intent_panel.offset_left = 245
	intent_panel.offset_right = -245
	intent_panel.offset_top = 182
	intent_panel.offset_bottom = 254
	intent_panel.add_theme_stylebox_override("panel", style(Color(0.04, 0.07, 0.11, 0.95), GOLD))
	intent_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(intent_panel)
	boss_intent = label("", 16, GOLD)
	boss_intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_panel.add_child(boss_intent)
	intent_panel.hide()
	plans_button = button("Plans 0/2  [P]", show_plans, root)
	plans_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	plans_button.offset_left = -210
	plans_button.offset_right = -24
	plans_button.offset_top = -225
	plans_button.offset_bottom = -183
	plans_button.tooltip_text = "Save 2 unused energy at End Turn for one Plan. Arm a contingency on a later turn."
	board_prompt = PanelContainer.new()
	board_prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	board_prompt.offset_left = 240
	board_prompt.offset_right = -240
	board_prompt.offset_top = 178
	board_prompt.offset_bottom = 257
	board_prompt.add_theme_stylebox_override("panel", style(BG, TEAL))
	root.add_child(board_prompt)
	var action_row := HBoxContainer.new()
	board_prompt.add_child(action_row)
	board_prompt_label = label("", 17, TEAL)
	board_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board_prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(board_prompt_label)
	button("Cancel [Esc]", func(): game.board_input.cancel(), action_row)
	board_prompt.hide()
	_style_battle_hud(theme)

func _gauge(title: String, right: bool, color: Color) -> ProgressBar:
	var box := VBoxContainer.new()
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT if right else Control.PRESET_CENTER_LEFT)
	box.offset_left = -222 if right else 22
	box.offset_right = -22 if right else 222
	box.offset_top = -50
	box.offset_bottom = 35
	box.add_child(label(title, 14, color))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(195, 25)
	bar.add_theme_stylebox_override("background", style(BG))
	bar.add_theme_stylebox_override("fill", style(color, color))
	box.add_child(bar)
	box.add_child(label("", 13, Color("9cacb9")))
	return bar

func _style_battle_hud(theme: Theme) -> void:
	var hud: Control = game.get_node("HUD/Root")
	hud.theme = theme
	for name in ["OrbGauge_2", "OrbGauge_3", "EnemyDeckPlaque", "DeckShadow"]:
		hud.get_node(name).hide()
	for i in 2:
		var hint: Label = hud.get_node("HintW" if i == 0 else "HintS")
		hint.position = Vector2(24, 160 + i * 26)
		hint.add_theme_font_override("font", theme.default_font)
		hint.add_theme_font_size_override("font_size", 17)
	hud.get_node("PlayerHealth/Caption").text = "STUDENT / RESPONSE"
	hud.get_node("EnemyHealth/Caption").text = "THE JANITOR / DISASTER"
	var player: Control = hud.get_node("PlayerHealth")
	player.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	player.position = Vector2(24, 92)
	player.size = Vector2(260, 56)
	var enemy: Control = hud.get_node("EnemyHealth")
	enemy.position.y = 92
	var turn: Control = hud.get_node("TurnPlaque")
	turn.position.y = 90
	hud.get_node("PhaseLabel").position.y = 145
	var end: Button = hud.get_node("EndTurnButton")
	end.add_theme_stylebox_override("normal", style(Color("233a47"), TEAL))
	end.text = "End turn  [Space]"
	end.offset_left = -210
	end.offset_right = -24
	end.offset_top = -92
	end.offset_bottom = -36
	var draw: Button = hud.get_node("DeckDrawButton")
	draw.offset_left = -210
	draw.offset_right = -24
	draw.offset_top = -165
	draw.offset_bottom = -106
	draw.tooltip_text = "Draw your card for this turn. D opens the full deck."
	hud.get_node("DrawCaption").hide()
	draw.add_theme_stylebox_override("normal", style(BG, GOLD))
	for health in [player, enemy]:
		for child in health.get_children():
			if child is Label:
				child.add_theme_font_override("font", theme.default_font)
				child.add_theme_font_size_override("font_size", 17)
	for path in ["TurnPlaque/TurnLabel", "PhaseLabel", "DeckDrawButton/DeckCountLabel", "EndTurnButton"]:
		var widget: Control = hud.get_node(path)
		widget.add_theme_font_override("font", theme.default_font)
		widget.add_theme_font_size_override("font_size", 20)
		widget.add_theme_constant_override("outline_size", 0)
		widget.add_theme_constant_override("shadow_offset_y", 0)
	for health in [player, enemy]:
		var bar: ProgressBar = health.get_node("Bar")
		bar.add_theme_stylebox_override("background", style(Color("14212c")))
		bar.add_theme_stylebox_override("fill", style(TEAL if health == player else Color("da857c")))

func _process(_delta: float) -> void:
	game.visible = battle_active or screen == "reward"
	board_prompt.visible = battle_active and not modal.visible and not game.board_input.action.is_empty()
	if board_prompt.visible: board_prompt_label.text = str(game.board_input.action.get("title", "Choose a board target"))
	game.opponent_hand.visible = battle_active and not modal.visible
	game.get_node("HUD/Root/EndTurnButton").disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or not game.board_input.action.is_empty() or _dragging()
	plans_button.visible = battle_active and not modal.visible
	plans_button.disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or _dragging() or not game.board_input.action.is_empty()
	plans_button.text = "Plans %d/2  [P]" % game.plans.tokens
	boss_intent.visible = is_instance_valid(game.final_boss) and battle_active and not modal.visible and game.board_input.action.is_empty()
	boss_intent.get_parent().visible = boss_intent.visible
	if boss_intent.visible: boss_intent.text = game.final_boss.intent()
	summary.text = "Floor %d  /  HP %d  /  %d supplies  /  %d cards" % [floor_number, game.player_hp, coins, collection.size()]
	prep.max_value = game.energy_cap
	prep.value = game.preparedness
	threat.max_value = game.tension_cap
	threat.value = game.tension
	prep.get_parent().get_child(0).text = "PREPAREDNESS  %d / %d" % [game.preparedness, game.energy_cap]
	threat.get_parent().get_child(0).text = "TENSION  %d / %d" % [game.tension, game.tension_cap]
	threat.get_parent().get_child(2).text = "Deck %d / Hand %d / Evo %d" % [game.enemy_deck.size(), game.enemy_hand.size(), game.enemy_evolution_deck.size()]
	prep.get_parent().get_child(2).text = "Deck %d  /  Hand %d" % [game.deck.size(), game.get_hand_cards().size()]
	game.get_node("HUD/Root").visible = battle_active and not modal.visible
	game.get_node("HUD/Root/DeckDrawButton/DeckCountLabel").text = "Draw · %d left" % game.deck.size()
	root.get_child(0).visible = screen not in ["title", "title_help", "characters", "character_preview"]
	map_button.disabled = saved_content != null or screen in DECISIONS or not game.board_input.action.is_empty()
	menu_button.disabled = map_button.disabled
	idle_hint.visible = false
	prep.get_parent().visible = battle_active and not modal.visible
	threat.get_parent().visible = battle_active and not modal.visible

func _input(event: InputEvent) -> void:
	if game.presentation.blocking: return
	if screen == "reward": return
	if screen == "inspect" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_modal_input(event)
		if screen != "inspect":
			get_viewport().set_input_as_handled()
			return
	if not modal.visible and not game.board_input.action.is_empty() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		game.board_input.cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if screen in ["title", "title_help", "characters", "character_preview"]: return
		match event.keycode:
			KEY_D: show_deck()
			KEY_L: show_battle_log()
			KEY_P: show_plans()
			KEY_M: toggle_map()
			KEY_ESCAPE:
				if screen == "choice" and action_cancel.is_valid():
					action_cancel.call()
				elif screen in ["intel", "inspect", "plans", "log"]: close_modal()
				elif screen in ["deck", "menu"] or (modal.visible and screen == "map" and battle_active):
					close_modal()
				else:
					show_menu()
			_: return
		get_viewport().set_input_as_handled()

func _panel_layout(kind: String) -> void:
	var title_screen := kind in ["title", "title_help", "characters", "character_preview"]
	var full_screen := title_screen or not battle_active or kind in ["map", "reward", "inspect"]
	game.visible = battle_active or kind == "reward"
	modal.offset_left = 0 if full_screen else 45
	modal.offset_right = 0 if full_screen else -45
	modal.offset_top = (0 if title_screen or kind in ["reward", "inspect"] else 78) if full_screen else 94
	modal.offset_bottom = 0 if full_screen else -28
	var panel_style := style(Color(0, 0, 0, 0.80) if kind in ["reward", "inspect"] else (BG if full_screen else Color(0.04, 0.07, 0.11, 0.99)), GOLD)
	if full_screen:
		panel_style.set_border_width_all(0)
		panel_style.set_corner_radius_all(0)
		panel_style.content_margin_left = 55
		panel_style.content_margin_right = 55
		panel_style.content_margin_top = 45 if title_screen else 20
		panel_style.content_margin_bottom = 35 if title_screen else 20
	modal.add_theme_stylebox_override("panel", panel_style)

func reset_panel(title: String, subtitle: String, kind: String) -> void:
	game.presentation.clear_banner()
	_panel_layout(kind)
	game.clear_hand_hover()
	if battle_active: get_tree().paused = true
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	screen = kind
	modal.show()
	content.add_child(label(title, 30, GOLD))
	content.add_child(label(subtitle, 16, Color("9cacb9")))
	game.presentation.reveal(content)

func close_modal() -> void:
	if saved_content:
		modal.remove_child(content)
		content.queue_free()
		content = saved_content
		modal.add_child(content)
		saved_content = null
		screen = saved_screen
		_panel_layout(screen)
		return
	if screen == "map":
		toggle_map()
		return
	if battle_active:
		get_tree().paused = false
		modal.hide()
		screen = ""
	else:
		show_map()

func new_run() -> void:
	if selected_character < 0 or selected_character >= CHARACTERS.size() or not CHARACTERS[selected_character].available: selected_character = 0
	last_character = selected_character
	get_tree().paused = false
	if saved_content:
		saved_content.queue_free()
		saved_content = null
	screen = ""
	saved_screen = ""
	action_cancel = Callable()
	intel_revealed = false
	game.plans.reset_run()
	event_key = ""
	event_cards.clear()
	game.player_buffs.clear()
	game.enemy_buffs.clear()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	shop_key = ""
	shop_stock.clear()
	shop_purchased.clear()
	rng.randomize()
	run_seed = rng.randi()
	rng.seed = run_seed
	collection.clear()
	acquisition_serial = 0
	for card in character_deck(selected_character): add_collection_card(card)
	reward_stock.clear()
	run_active = true
	persistence.discard()
	game.get_node("HUD/Root/PlayerHealth/Caption").text = CHARACTERS[selected_character].name
	coins = 35
	floor_number = 1
	game.player_hp = game.PLAYER_MAX_HP
	game.energy_cap = game.ENERGY_START
	game.preparedness = game.ENERGY_START
	game.tension_cap = game.TENSION_START
	game.tension = game.TENSION_START
	battle_active = false
	game.clear_battle()
	game.player_run_buffs[CHARACTERS[selected_character].buff] = 1
	generate_map()
	show_map()
	persistence.checkpoint()

func generate_map() -> void:
	rooms.clear()
	cleared.clear()
	current = -1
	for row in range(MAP_ROWS):
		for lane in range(3 if row < MAP_ROWS - 1 else 1):
			var kind := "battle"
			if row == MAP_ROWS - 1:
				kind = "boss"
			elif row == 7:
				kind = ["elite", "rest", "upgrade"][lane]
			elif row in [0, 3, 6, 9]:
				kind = "elite" if row == 9 and lane == 1 else "battle"
			elif row > 0:
				kind = ["battle", "battle", "event", "shop", "upgrade", "rest"][rng.randi_range(0, 5)]
			rooms.append({"id":rooms.size(), "row":row, "lane":lane if row < MAP_ROWS - 1 else 1, "kind":kind, "links":[], "event":EVENT_TYPES[rng.randi_range(0, EVENT_TYPES.size() - 1)] if kind == "event" else ""})
	for room in rooms:
		var candidates: Array = []
		for next in rooms:
			if next.row == room.row + 1 and (abs(next.lane - room.lane) <= 1 or next.kind == "boss"):
				candidates.append(next.id)
		if not candidates.is_empty():
			room.links.append(candidates[rng.randi_range(0, candidates.size() - 1)])
			for id in candidates:
				if id not in room.links and rng.randf() < 0.38: room.links.append(id)
	# Guarantee incoming paths too: every generated room can be reached.
	for next in rooms:
		if next.row == 0: continue
		if rooms.any(func(room): return next.id in room.links): continue
		var predecessors := rooms.filter(func(room): return room.row == next.row - 1 and (abs(room.lane - next.lane) <= 1 or next.kind == "boss"))
		predecessors[rng.randi_range(0, predecessors.size() - 1)].links.append(next.id)

func reachable(id: int) -> bool:
	if battle_active or (current >= 0 and current not in cleared): return false
	return rooms[id].row == 0 if current < 0 else id in rooms[current].links

func show_map() -> void:
	if _dragging(): return
	if saved_content: return
	if screen in DECISIONS: return
	reset_panel("THE SCHOOL MAP", "Choose a glowing room and climb toward the boss. Every route includes combat. Scroll to explore.  •  Seed %d" % run_seed, "map")
	var canvas := RouteCanvas.new()
	canvas.rooms = rooms
	canvas.current = current
	canvas.cleared = cleared
	canvas.custom_minimum_size = Vector2(680, 1660)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(map_scroll)
	map_scroll.add_child(canvas)
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	animate_map.call_deferred(weakref(map_scroll), maxi(0, 1660 - 100 - (int(rooms[current].row) if current >= 0 else 0) * 145 - 280))
	canvas.resized.connect(func():
		for b in canvas.get_children():
			b.position = canvas.point(rooms[int(b.get_meta("room"))]) - b.size / 2
	)
	for room in rooms:
		var id: int = room.id
		var b := button(("✓ " if id in cleared else "") + str(room.kind).capitalize(), visit.bind(id), canvas)
		b.set_meta("room", id)
		b.custom_minimum_size = Vector2(92, 62)
		b.size = Vector2(92, 62)
		b.disabled = not reachable(id)
		if not b.disabled: b.add_theme_stylebox_override("normal", style(Color("233a47"), TEAL))
		if id in cleared: b.add_theme_stylebox_override("disabled", style(Color("28312e"), GOLD))
		b.tooltip_text = "Room %d · %s" % [room.row + 1, room.kind]
		if room.kind == "boss" and floor_number == 3:
			b.text = "FINAL BOSS"
			b.tooltip_text = "Final boss: three telegraphed phases. Prepare healing, barriers and AoE."
		b.position = canvas.point(room) - b.size / 2
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	content.add_child(footer)
	footer.add_child(label("Battle  /  Elite  /  Rest  /  Workshop  /  Event  /  Shop  ↑  JANITOR", 16, TEAL))
	if battle_active: button("Return to battle", close_modal, footer)
	else: button("Menu  [Esc]", show_menu, footer)

func animate_map(reference: WeakRef, destination: int) -> void:
	var scroll = reference.get_ref()
	if not is_instance_valid(scroll): return
	await get_tree().process_frame
	if not is_instance_valid(scroll): return
	scroll.scroll_vertical = destination + 110
	var tween: Tween = scroll.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(scroll, "scroll_vertical", destination, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func toggle_map() -> void:
	if _dragging() or saved_content or screen in DECISIONS: return
	if screen == "map":
		if not battle_active: return
		get_tree().paused = false
		modal.hide()
		screen = ""
	else:
		show_map()

func visit(id: int) -> void:
	if not reachable(id): return
	current = id
	encounter = rooms[id].kind
	game.presentation.banner("ENTERING " + str(encounter).to_upper(), "Floor %d" % floor_number)
	match encounter:
		"battle", "elite", "boss":
			intel_revealed = false
			battle_active = true
			modal.hide()
			screen = ""
			game.start_encounter(collection, encounter, floor_number, rng.randi_range(0, 3))
		"rest": show_rest()
		"upgrade": show_upgrade()
		"shop": show_shop()
		"event": show_event()

func finish_room() -> void:
	reward_stock.clear()
	if current not in cleared: cleared.append(current)
	screen = ""
	game._refresh_bars()
	show_map()

func show_rest() -> void:
	reset_panel("THE INFIRMARY", "Choose one: recover 7 health, train a card, or remove one card from your deck.", "event")
	button("Rest · +%d HP · free" % healing_gain(7), rest, content).disabled = healing_gain(7) == 0
	button("Train · upgrade 1 card · free", show_upgrade, content)
	button("Destroy 1 card · free", show_remove_cards.bind("rest"), content).disabled = collection.size() <= 5
	button("Leave infirmary", finish_room, content)

func healing_gain(amount: int) -> int:
	return maxi(0, mini(amount, game.PLAYER_MAX_HP - game.player_hp))

func rest() -> void:
	game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 7)
	finish_room()

func battle_finished(won: bool) -> void:
	if not battle_active: return
	get_tree().paused = false
	battle_active = false
	intel_revealed = false
	game.player_buffs.clear()
	game.enemy_buffs.clear()
	if not won:
		run_active = false
		persistence.discard()
		reset_panel("TRAPPED AFTER MIDNIGHT", "Your run has ended. Begin again with a new school layout.", "result")
		button("Return to starting screen", return_title, content)
		return
	coins += 35 if encounter == "elite" else (60 if encounter == "boss" else 20)
	if encounter == "boss":
		game.clear_battle(true)
		show_contingency_reward("victory" if floor_number == 3 else "floor")
	elif encounter == "elite": show_contingency_reward("cards")
	else:
		show_rewards()
	game.presentation.banner("BATTLE VICTORY", "+%d supplies" % (35 if encounter == "elite" else (60 if encounter == "boss" else 20)))

func show_contingency_reward(next_screen: String, restore_offers: bool = false) -> void:
	unlock_after = next_screen
	if not restore_offers: buff_choices.clear()
	var locked: Array = game.plans.TACTICS.filter(func(tactic): return tactic.id not in game.plans.unlocked)
	if locked.is_empty():
		finish_unlock_reward()
		return
	if not restore_offers:
		for i in range(mini(3, locked.size())): buff_choices.append(locked.pop_at(rng.randi_range(0, locked.size() - 1)))
	reset_panel("NEW CONTINGENCY", "Elite and boss victories teach a new tactic. Choose one to unlock for the rest of this run.", "contingency_reward")
	for tactic in buff_choices: button(tactic.name + " · %d Plan%s\n" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""] + tactic.description, select_contingency_reward.bind(tactic.id), content)

func select_contingency_reward(id: String) -> void:
	if screen != "contingency_reward" or not buff_choices.any(func(tactic): return tactic.id == id): return
	game.plans.unlock(id)
	finish_unlock_reward()

func finish_unlock_reward() -> void:
	match unlock_after:
		"floor": show_floor_buffs()
		"victory": show_run_victory()
		_: show_rewards()

func show_run_victory() -> void:
	run_active = false
	persistence.discard()
	reset_panel("DAWN AT LAST", "Steve has survived all three floors and contained the Midnight Warden. The school is safe.", "victory")
	content.add_child(label("RUN COMPLETE · %d cards · %d supplies · %d health remaining" % [collection.size(), coins, game.player_hp], 20, TEAL))
	button("Return to starting screen", return_title, content)
	button("Keep exploring · endless floors", show_floor_buffs, content)

func next_floor() -> void:
	run_active = true
	floor_number += 1
	game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 5)
	game.clear_battle()
	generate_map()
	screen = ""
	show_map()
	game.presentation.banner("FLOOR %d" % floor_number, "A new route through the school")

func add_collection_card(card: Dictionary) -> void:
	acquisition_serial += 1
	var copy := card.duplicate(true)
	copy.acquired = acquisition_serial
	collection.append(copy)

func offers(count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var ids: Array = []
	for card in catalog:
		if card.id not in ids:
			ids.append(card.id)
			pool.append(card.duplicate(true))
	var result: Array[Dictionary] = []
	for i in range(count):
		var pick := rng.randi_range(0, pool.size() - 1)
		result.append(pool[pick])
		pool.remove_at(pick)
	return result

func show_rewards() -> void:
	reset_panel("DISASTER CONTAINED", "Take one Response card for your deck. Supplies earned; your surviving health carries forward.", "reward")
	var box := centered_content()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	if reward_stock.is_empty(): reward_stock = offers(3)
	for card in reward_stock:
		var column := VBoxContainer.new()
		row.add_child(column)
		var preview = game.Card3DScene.instantiate()
		preview.preview_only = true
		preview.input_ray_pickable = false
		preview.collision_layer = 0
		preview.collision_mask = 0
		column.add_child(preview)
		preview.setup(card)
		preview.set_process(false)
		preview.hide()
		var face := card_image(preview._vp.get_texture(), column, 245)
		face.tooltip_text = card_rules(card)
		game.presentation.card_feedback(face)
		var take := func():
			if screen != "reward": return
			add_collection_card(card.duplicate(true))
			finish_room()
		face.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: take.call()
		)
		button("Take card", take, column)
		game.presentation.reveal(column)
	button("Skip card reward", finish_room, box)

func centered_content() -> VBoxContainer:
	var headings := content.get_children().duplicate()
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	for heading in headings:
		heading.reparent(box)
		if heading is Label: heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return box

func card_image(texture: Texture2D, parent: Node, width: float) -> TextureRect:
	var frame := AspectRatioContainer.new()
	frame.ratio = float(CardFace.FACE_W) / CardFace.FACE_H
	frame.custom_minimum_size = Vector2(width, width / frame.ratio)
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	parent.add_child(frame)
	var face := TextureRect.new()
	face.texture = texture
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(face)
	return face

func _modal_input(event: InputEvent) -> void:
	if screen != "inspect" or not is_instance_valid(inspected_face): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not inspected_face.get_global_rect().has_point(event.global_position):
			close_modal()
			get_viewport().set_input_as_handled()

func _card_tile(card: Dictionary, parent: Node, action: Callable = Callable(), action_text: String = "") -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(225, 300)
	panel.tooltip_text = card_rules(card)
	panel.add_theme_stylebox_override("panel", style(Color("152431"), CardFace.ELEMENT_COLORS.get(card.element, GOLD)))
	# Previews use lightweight controls and leave illustration windows blank.
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(label(card.name, 19, GOLD))
	var cost_text := "%d energy" % int(card.cost)
	if card.get("type", "response") == "disaster":
		cost_text = "%d sacrifices" % int(card.cost) if int(card.cost) > 0 else "%d tension" % int(card.get("tension_cost", 1))
	box.add_child(label("%s  •  %s" % [str(card.element).to_upper(), cost_text], 14, TEAL))
	var blank := Panel.new()
	blank.custom_minimum_size = Vector2(180, 115)
	blank.add_theme_stylebox_override("panel", style(Color("0e1922")))
	box.add_child(blank)
	box.add_child(label("ATK %d   /   HP %d" % [card.attack, card.health], 17))
	var traits: Array = card.get("modifiers", []).duplicate()
	if card.get("modifier", "") != "": traits.push_front(card.modifier)
	box.add_child(label(" / ".join(traits).capitalize() if not traits.is_empty() else "No modifier", 14, Color("9cacb9")))
	box.add_child(label("Upgrades %d / 2" % upgrade_level(card), 12, GOLD))
	if card.has("graveyard_reason"): box.add_child(label("%s · round %d" % [card.graveyard_reason, int(card.graveyard_round)], 13, GOLD))
	if int(card.get("locked_until", 0)) > game.turn: box.add_child(label("SEALED until round %d" % int(card.locked_until), 13, Color("da857c")))
	if card.has("on_hit"):
		var hits: PackedStringArray = []
		for status in card.on_hit: hits.append("%s %d" % [str(status).capitalize(), int(card.on_hit[status])])
		box.add_child(label("On hit: " + " / ".join(hits), 12, TEAL))
	if int(card.get("strength", 0)) > 0: box.add_child(label("Strength +%d" % int(card.strength), 13, TEAL))
	if card.has("statuses"):
		var tokens: PackedStringArray = []
		for status in card.statuses:
			if status != "strength" and int(card.statuses[status]) > 0: tokens.append("%s %d" % [str(status).capitalize(), int(card.statuses[status])])
		if not tokens.is_empty(): box.add_child(label(" / ".join(tokens), 13, Color("da857c")))
	if not card.get("utility", false) and card.get("effect", "") == "draw": box.add_child(label("On play: draw %d" % int(card.get("draw_count", 1)), 13, TEAL))
	if card.get("effect", "") == "move_ally": box.add_child(label("On play: relocate an ally", 13, TEAL))
	if card.get("effect", "") == "heal_all": box.add_child(label("On play: heal other allies 2", 13, TEAL))
	if card.get("effect", "") == "rally_all": box.add_child(label("On play: other allies +1 Strength", 13, TEAL))
	if int(card.get("leech", 0)) > 0: box.add_child(label("Heal %d after each attack" % int(card.leech), 13, TEAL))
	if card.get("utility", false): box.add_child(label("UTILITY · " + str(Rules.EFFECT_LABELS.get(card.effect, card.effect)).to_upper(), 13, TEAL))
	else:
		var counters: Dictionary = game.TYPE_CHART.get(card.element, {})
		for element in counters:
			if float(counters[element]) > 1: box.add_child(label("2× vs " + str(element).capitalize(), 13, TEAL))
	var special := Rules.special_text(card)
	if special != "":
		var text := label(special, 12, TEAL)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 180
		box.add_child(text)
	if action.is_valid(): button(action_text, action, box)

func show_deck() -> void:
	if _dragging(): return
	if screen in ["title", "title_help", "characters", "character_preview"]: return
	if screen == "deck":
		close_modal()
		return
	if screen in DECISIONS:
		saved_content = content
		saved_screen = screen
		modal.remove_child(content)
		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		modal.add_child(content)
	reset_panel("YOUR RESPONSE DECK", "%d collected cards. Blank art windows are ready for your artwork. Draw-pile order stays hidden." % collection.size(), "deck")
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	button("Collection (%d)" % collection.size(), deck_cards.bind(collection), tabs)
	button("Draw pile (%d)" % game.deck.size(), deck_cards.bind(game.deck), tabs).disabled = not battle_active
	button("Hand (%d)" % game.get_hand_cards().size(), deck_hand, tabs).disabled = not battle_active
	button("On board", deck_board, tabs).disabled = not battle_active
	if battle_active: button("Graveyards (%d / %d)" % [game.player_graveyard.size(), game.enemy_graveyard.size()], show_graveyard, tabs)
	if battle_active and intel_revealed: button("Janitor hand", func(): deck_cards(game.enemy_hand), tabs)
	button("Close", close_modal, tabs)
	add_sort_controls(false)
	var scroll := ScrollContainer.new()
	scroll.name = "Cards"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	deck_cards(collection)

func preserve_pending_decision() -> void:
	if screen in DECISIONS and saved_content == null:
		saved_content = content
		saved_screen = screen
		modal.remove_child(content)
		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		modal.add_child(content)

func inspect_board_card(card: Node) -> void:
	if not battle_active or modal.visible or _dragging() or not is_instance_valid(card) or card.in_hand: return
	reset_panel("CARD INSPECTION", "Current battle stats, effects and statuses. Combat is paused while you inspect.", "inspect")
	var box := centered_content()
	var row := CenterContainer.new()
	box.add_child(row)
	card._refresh_face()
	inspected_face = card_image(card._vp.get_texture(), row, 330)
	var details := RichTextLabel.new()
	details.custom_minimum_size = Vector2(650, 85)
	details.text = "Attack %d · Health %d/%d\n" % [card.effective_attack(), card.card_data.health, card.max_health]
	if not card.modifiers.is_empty(): details.text += "Modifiers: " + ", ".join(card.modifiers) + "\n"
	for status in card.statuses:
		if int(card.statuses[status]) > 0: details.text += "%s %d · " % [str(status).capitalize(), int(card.statuses[status])]
	details.text += "\n" + card_rules(live_definition(card)) + "\n\nClick outside the card to return."
	details.add_theme_font_size_override("normal_font_size", 19)
	box.add_child(details)
	button("Return to battle", close_modal, box)

func show_battle_log() -> void:
	if _dragging() or screen in ["title", "title_help", "characters", "character_preview"]: return
	if screen == "log":
		close_modal()
		return
	preserve_pending_decision()
	reset_panel("BATTLE LOG", "Latest 300 events, in order. This encounter's actions, damage, healing and statuses.", "log")
	var log_view := RichTextLabel.new()
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 18)
	log_view.text = "\n".join(game.battle_log) if not game.battle_log.is_empty() else "No battle events yet."
	content.add_child(log_view)
	button("Close  [L / Esc]", close_modal, content)

func show_plans() -> void:
	if not battle_active or _dragging() or not game.board_input.action.is_empty(): return
	if screen == "plans":
		close_modal()
		return
	if screen in DECISIONS or saved_content != null: return
	reset_panel("PREPAREDNESS · CONTINGENCIES", "Save 2 unused energy at End Turn for 1 Plan. Unlock more tactics from elite and boss wins.", "plans")
	content.add_child(label("PLANS %d / 2 · %d TACTICS UNLOCKED" % [game.plans.tokens, game.plans.unlocked.size()], 23, TEAL))
	var save := CheckButton.new()
	save.text = "Automatically save 2 unused energy when ending my turn"
	save.button_pressed = game.plans.auto_save
	save.toggled.connect(func(enabled): game.plans.auto_save = enabled)
	content.add_child(save)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for id in game.plans.unlocked:
		var tactic: Dictionary = game.plans.definition(id)
		button(tactic.name + " · %d Plan%s\n" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""] + tactic.description, begin_tactic.bind(id), list).disabled = not tactic_available(id)
	if not game.plans.armed.is_empty(): content.add_child(label("ARMED: " + str(game.plans.definition(game.plans.armed.kind).name), 18, GOLD))
	content.add_child(label("One armed tactic per round. Targeted tactics use board clicks. Esc cancels target selection without spending.", 16))
	button("Return to battle  [P / Esc]", close_modal, content)

func tactic_available(id: String) -> bool:
	var tactic: Dictionary = game.plans.definition(id)
	if game.phase != game.Phase.PLAYER_PLAY or game.plans.tokens < int(tactic.cost) or game.plans.committed_round == game.turn: return false
	var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
	if id == "coordinate": return not matching_plan_pairs().is_empty()
	if id == "supply": return not game.deck.is_empty() and game.get_hand_cards().size() < game.HAND_SIZE_MAX
	if id == "shelter": return true
	if id == "extract": return not allies.is_empty() and game._response_slots().any(func(slot): return game._get_card_in_slot(slot) == null)
	return not allies.is_empty()

func begin_tactic(id: String) -> void:
	if not tactic_available(id): return
	close_modal()
	if id == "coordinate":
		game.board_input.pair("Click the first friendly ally for Coordinated Response. Esc cancels.", arm_coordination)
	elif id == "extract":
		var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
		game.board_input.pick("Click the ally to protect with Emergency Extraction. Esc cancels.", allies, select_extraction_ally, Callable())
	elif id in ["supply", "shelter"]: game.plans.arm(id, [])
	else:
		var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
		game.board_input.pick("Click a deployed ally for " + str(game.plans.definition(id).name) + ". Esc cancels.", allies, arm_target_tactic.bind(id), Callable())

func arm_target_tactic(card: Node, id: String) -> void: game.plans.arm(id, [card])
func select_brace() -> void: begin_tactic("brace")
func arm_brace(card: Node) -> void:
	game.board_input.clear()
	game.plans.arm("brace", [card])
func select_coordination() -> void: begin_tactic("coordinate")
func arm_coordination(cards: Array) -> void:
	game.board_input.clear()
	game.plans.arm("coordinate", cards)

func select_extraction_ally(card: Node) -> void:
	extraction_card = card
	game.board_input.destination(card, arm_extraction)

func arm_extraction(slot: Node3D) -> void:
	game.plans.arm("extract", [extraction_card], slot)
	extraction_card = null

func matching_plan_pairs() -> Array:
	var pairs: Array = []
	var slots: Array = game._response_slots()
	for i in range(slots.size() - 1):
		for j in range(i + 1, slots.size()):
			var first = game._get_card_in_slot(slots[i])
			var second = game._get_card_in_slot(slots[j])
			if first and second and game.plans.matching_pair([first, second]): pairs.append([first, second])
	return pairs

func show_graveyard() -> void:
	if not battle_active or _dragging(): return
	reset_panel("BATTLE GRAVEYARDS", "Destroyed units, sacrifices and cast spells stay here until the next encounter. Cards do not return to the draw pile.", "deck")
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	button("Response (%d)" % game.player_graveyard.size(), deck_cards.bind(game.player_graveyard), tabs)
	button("Janitor (%d)" % game.enemy_graveyard.size(), deck_cards.bind(game.enemy_graveyard), tabs)
	button("Back to deck", func(): screen = ""; show_deck(), tabs)
	button("Close", close_modal, tabs)
	add_sort_controls(false)
	var scroll := ScrollContainer.new()
	scroll.name = "Cards"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	deck_cards(game.player_graveyard)

func deck_hand() -> void:
	var cards: Array[Dictionary] = []
	for card in game.get_hand_cards(): cards.append(live_definition(card))
	deck_cards(cards)

func deck_board() -> void:
	var cards: Array[Dictionary] = []
	for slot in game._response_slots():
		var card = game._get_card_in_slot(slot)
		if card:
			cards.append(live_definition(card))
	deck_cards(cards)

func live_definition(card: Node) -> Dictionary:
	var definition: Dictionary = card.card_data.duplicate(true)
	definition.attack = card.effective_attack()
	definition.modifier = ", ".join(card.modifiers)
	definition.erase("modifiers")
	definition.strength = int(card.statuses.get("strength", 0))
	definition.statuses = card.statuses.duplicate()
	return definition

func card_rules(card: Dictionary) -> String:
	var effect: String = str(card.get("effect", ""))
	if card.get("utility", false): return str(Rules.EFFECTS.get(effect, effect)) + "\n" + Rules.special_text(card) + "\nChoose an empty Response slot to cast. Cancel before choosing a target to keep the card and energy."
	var rules := "Adjacent matching types: +1 attack.\n" + Rules.special_text(card) + "\n"
	if effect == "draw": rules += "On play: draw %d.\n" % int(card.get("draw_count", 1))
	if effect == "move_ally": rules += "On play: optionally choose another ally, then an empty lane, and move it there. Skipping movement does not undo the summon.\n"
	if effect == "heal_all": rules += "On play: heal other deployed allies by 2.\n"
	if effect == "rally_all": rules += "On play: other deployed allies gain 1 Strength.\n"
	if int(card.get("leech", 0)) > 0: rules += "Heal %d after attacking.\n" % int(card.leech)
	if card.get("modifier", "") == "piercing": rules += "Piercing: also hits opposing health for attack damage, even when blocked.\n"
	if card.get("modifier", "") == "sluggish": rules += "Sluggish: attacks immediately, then rests every other round.\n"
	if card.has("on_hit"):
		for status in card.on_hit: rules += "On hit: %s %d to a surviving blocker.\n" % [str(status).capitalize(), int(card.on_hit[status])]
	for element in game.TYPE_CHART.get(card.element, {}):
		rules += "%s: %s× damage\n" % [str(element).capitalize(), game.TYPE_CHART[card.element][element]]
	return rules + "All other matchups: normal damage."

func deck_cards(cards: Array[Dictionary]) -> void:
	viewed_cards = cards.duplicate()
	var scroll := content.get_node("Cards")
	for child in scroll.get_children():
		scroll.remove_child(child)
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for index in sorted_indices(cards, deck_sort, deck_descending): _card_tile(cards[index], grid)
	if cards.is_empty(): grid.add_child(label("No cards here yet.", 20, TEAL))

func sorted_indices(cards: Array, key_index: int, descending: bool) -> Array:
	var indices: Array = range(cards.size())
	var key: String = SORT_KEYS[key_index]
	indices.sort_custom(func(a, b):
		var left: Variant = cards[a].get(key, "")
		var right: Variant = cards[b].get(key, "")
		var comparison := 0
		if key == "acquired":
			left = int(cards[a].get(key, a))
			right = int(cards[b].get(key, b))
			comparison = -1 if int(left) > int(right) else (1 if int(left) < int(right) else 0)
		elif key in ["cost", "attack", "health"]:
			comparison = -1 if int(left) < int(right) else (1 if int(left) > int(right) else 0)
		else: comparison = str(left).naturalnocasecmp_to(str(right))
		if comparison == 0: return a < b
		return comparison > 0 if descending else comparison < 0
	)
	return indices

func add_sort_controls(workshop: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	row.add_child(label("Sort by", 16))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(190, 40)
	for title in ["Name", "Type", "Cost", "Attack", "Health", "Modifier", "Recently added"]: picker.add_item(title)
	picker.select(upgrade_sort if workshop else deck_sort)
	picker.item_selected.connect(change_sort.bind(workshop))
	row.add_child(picker)
	var descending := upgrade_descending if workshop else deck_descending
	button("Descending ↓" if descending else "Ascending ↑", reverse_sort.bind(workshop), row)

func change_sort(index: int, workshop: bool) -> void:
	if workshop:
		upgrade_sort = index
		show_upgrade()
	else:
		deck_sort = index
		deck_cards(viewed_cards)

func reverse_sort(workshop: bool) -> void:
	if workshop:
		upgrade_descending = not upgrade_descending
		show_upgrade()
	else:
		deck_descending = not deck_descending
		deck_cards(viewed_cards)
		# Rebuild the small sort row without changing tabs or the viewed pile.
		var row := content.get_child(3)
		content.remove_child(row)
		row.queue_free()
		add_sort_controls(false)
		content.move_child(content.get_child(content.get_child_count() - 1), 3)

func show_upgrade() -> void:
	reset_panel("THE WORKSHOP", "Each card can upgrade twice. Preview type-specific abilities and improvements before confirming.", "upgrade")
	add_sort_controls(true)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	for i in sorted_indices(collection, upgrade_sort, upgrade_descending):
		var card := collection[i]
		_card_tile(card, grid, show_upgrade_preview.bind(i) if can_upgrade(card) else Callable(), "Preview upgrade")
		if not can_upgrade(card):
			grid.get_child(grid.get_child_count() - 1).tooltip_text = "This card has reached its two-upgrade limit."
			grid.get_child(grid.get_child_count() - 1).get_child(0).add_child(label("Fully upgraded", 14, GOLD))
	button("Leave", finish_room, content)

func upgrade(index: int) -> void:
	if index < 0 or index >= collection.size() or not can_upgrade(collection[index]): return
	collection[index] = upgraded_definition(collection[index])
	finish_room()

func upgrade_level(card: Dictionary) -> int:
	return int(card.get("upgrades", str(card.get("name", "")).count("+")))

func can_upgrade(card: Dictionary) -> bool:
	return upgrade_level(card) < MAX_UPGRADES

func upgraded_definition(card: Dictionary) -> Dictionary:
	var result: Dictionary = card.duplicate(true)
	if not can_upgrade(card): return result
	var tier := upgrade_level(card) + 1
	result.upgrades = tier
	if result.get("utility", false):
		if tier == 1 and int(result.cost) > 0: result.cost = int(result.cost) - 1
		elif result.get("effect", "") in ["move", "tutor", "scout"]: result.refund_energy = int(result.get("refund_energy", 0)) + 1
		else: result.utility_power = int(result.get("utility_power", 0)) + 1
	else:
		match str(result.get("element", "")):
			"evac":
				if tier == 1:
					result.attack = int(result.attack) + 1
					result.on_play_draw = int(result.get("on_play_draw", 0)) + 1
				else:
					result.health = int(result.health) + 1
					result.cost = maxi(0, int(result.cost) - 1)
			"douse":
				if tier == 1:
					result.attack = int(result.attack) + 1
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.burn = int(hits.get("burn", 0)) + 1
					result.on_hit = hits
				else:
					result.health = int(result.health) + 1
					result.leech = int(result.get("leech", 0)) + 1
			"clearance":
				if tier == 1:
					result.attack = int(result.attack) + 1
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.poison = int(hits.get("poison", 0)) + 1
					result.on_hit = hits
				else:
					result.health = int(result.health) + 1
					result.status_bonus = int(result.get("status_bonus", 0)) + 2
			"brace":
				if tier == 1:
					result.health = int(result.health) + 2
					result.armor_value = int(result.get("armor_value", 1 if game.definition_has_modifier(result, "armored") else 0)) + 1
					var traits: Array = result.get("modifiers", []).duplicate()
					if result.get("modifier", "") != "armored" and "armored" not in traits: traits.append("armored")
					result.modifiers = traits
				else:
					result.health = int(result.health) + 1
					result.thorns = int(result.get("thorns", 0)) + 1
			_:
				result.attack = int(result.attack) + 1
				result.health = int(result.health) + 1
	result.name = str(result.name) + "+"
	return result

func show_upgrade_preview(index: int) -> void:
	if not can_upgrade(collection[index]): return
	reset_panel("UPGRADE PREVIEW", "Left: current card. Right: upgraded card. Only Confirm applies the upgrade.", "upgrade_preview")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	content.add_child(row)
	_card_tile(collection[index], row)
	row.add_child(label("→", 40, GOLD))
	_card_tile(upgraded_definition(collection[index]), row)
	button("Confirm upgrade", upgrade.bind(index), content)
	button("Back to workshop", show_upgrade, content)

func show_shop() -> void:
	var key := "%d:%d" % [floor_number, current]
	if shop_key != key:
		shop_key = key
		shop_stock = offers(4)
		if floor_number >= 2:
			var remainder := shop_stock.filter(func(card): return card.id not in ["barrier", "alarm_sweep"])
			shop_stock.clear()
			for id in ["barrier", "alarm_sweep"]:
				for card in catalog:
					if card.id == id:
						shop_stock.append(card.duplicate(true))
						break
			shop_stock.append(remainder[0])
			shop_stock.append(remainder[1])
		shop_purchased.clear()
	reset_panel("THE SUPPLY ROOM", "Buy as many stocked items as you can afford. Card prices scale with power. First aid restores up to 5 HP for 15 supplies. Stock stays fixed.", "shop")
	var row := HBoxContainer.new()
	content.add_child(row)
	for card in shop_stock:
		var sold: bool = card.id in shop_purchased
		var price := shop_price(card)
		_card_tile(card, row, buy.bind(card) if not sold and coins >= price else Callable(), "Buy card · -%d supplies" % price)
		if sold: row.get_child(row.get_child_count() - 1).get_child(0).add_child(label("SOLD OUT", 16, GOLD))
		elif coins < price: row.get_child(row.get_child_count() - 1).get_child(0).add_child(label("Need %d supplies" % price, 14, Color("9cacb9")))
	button("First aid · +%d HP · -15 supplies" % healing_gain(5), buy_heal, content).disabled = coins < 15 or game.player_hp >= game.PLAYER_MAX_HP
	button("Destroy 1 card · -30 supplies", show_remove_cards.bind("shop"), content).disabled = coins < 30 or collection.size() <= 5
	button("Leave shop", finish_room, content)

func shop_price(card: Dictionary) -> int:
	var power := int(card.get("cost", 0)) + int(card.get("attack", 0)) + int(card.get("health", 1))
	power += int(card.get("strength", 0)) + int(card.get("leech", 0))
	if card.has("condition"): power += 3
	for amount in card.get("on_hit", {}).values(): power += int(amount)
	if card.get("modifier", "") == "sluggish": power -= 3
	elif card.get("modifier", "") != "": power += 2
	if card.get("effect", "") in ["draw", "rally_all", "heal_all"]: power += 2
	return 20 if power <= 5 else (30 if power <= 9 else (40 if power <= 13 else 50))

func buy(card: Dictionary) -> void:
	var stocked := shop_stock.filter(func(item): return item.id == card.id)
	if stocked.is_empty() or card.id in shop_purchased: return
	var definition: Dictionary = stocked[0]
	var price := shop_price(definition)
	if coins < price: return
	coins -= price
	add_collection_card(definition.duplicate(true))
	shop_purchased.append(definition.id)
	show_shop()

func buy_heal() -> void:
	if coins < 15 or game.player_hp >= game.PLAYER_MAX_HP: return
	coins -= 15
	game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 5)
	show_shop()

func show_remove_cards(origin: String) -> void:
	if battle_active or origin not in ["shop", "rest", "event"]: return
	remove_origin = origin
	reset_panel("REMOVE A CARD", "Choose the exact copy to retire. Keep at least 5 cards. " + ("Removal costs 30 supplies; the shop stays open." if origin == "shop" else ("This replaces healing or training at this rest node." if origin == "rest" else "Trade one card for 25 supplies.")), "remove")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	for i in sorted_indices(collection, deck_sort, deck_descending): _card_tile(collection[i], grid, preview_remove.bind(i), "Choose this copy")
	button("Cancel", cancel_remove, content)

func preview_remove(index: int) -> void:
	if index < 0 or index >= collection.size(): return
	remove_index = index
	reset_panel("DESTROY THIS COPY?", "This removes the card from your run deck. Your other copies are kept.", "remove_confirm")
	_card_tile(collection[index], content)
	button("Destroy card · " + ("-30 supplies" if remove_origin == "shop" else ("+25 supplies" if remove_origin == "event" else "free")), confirm_remove, content).disabled = collection.size() <= 5 or (remove_origin == "shop" and coins < 30)
	button("Back", show_remove_cards.bind(remove_origin), content)

func confirm_remove() -> void:
	if screen != "remove_confirm" or collection.size() <= 5 or remove_index < 0 or remove_index >= collection.size(): return
	if remove_origin == "shop" and coins < 30: return
	if remove_origin == "shop": coins -= 30
	collection.remove_at(remove_index)
	remove_index = -1
	if remove_origin == "shop": show_shop()
	else:
		if remove_origin == "event":
			coins += 25
			event_resolved = true
		finish_room()

func cancel_remove() -> void:
	if remove_origin == "shop": show_shop()
	elif remove_origin == "event": show_event()
	else: show_rest()

func catalog_card(id: String) -> Dictionary:
	for card in catalog:
		if card.id == id: return card.duplicate(true)
	return {}

func show_event() -> void:
	var key := "%d:%d" % [floor_number, current]
	if event_key != key:
		event_key = key
		event_type = str(rooms[current].get("event", "locked")) if current >= 0 and current < rooms.size() else "locked"
		if event_type == "": event_type = "locked"
		event_resolved = false
		event_cards.clear()
		if event_type == "locked": event_cards = offers(1)
		elif event_type == "science":
			var burn := catalog_card("steam_team")
			burn.name = "Experimental Steam Team"
			burn.on_hit.burn = int(burn.on_hit.burn) + 2
			var poison := catalog_card("hazmat_team")
			poison.name = "Experimental Hazmat Team"
			poison.on_hit.poison = int(poison.on_hit.poison) + 1
			event_cards.assign([burn, poison])
	match event_type:
		"radio":
			reset_panel("THE EMERGENCY RADIO", "The utility kit contains Hazard Forecast and Search and Rescue.", "event")
			button("Utility kit · +2 cards · -20 supplies", resolve_event.bind("radio_buy"), content).disabled = coins < 20
			button("Report the safe route · +10 supplies", resolve_event.bind("safe"), content)
		"rooftop":
			reset_panel("ROOFTOP DRILLS", "Training gives a starting Plan but reduces energy capacity in every battle for the rest of this run.", "event")
			button("Train · +1 starting Plan · -1 energy capacity", resolve_event.bind("training"), content)
			button("Collect equipment · +10 supplies", resolve_event.bind("safe"), content)
		"science":
			reset_panel("THE SCIENCE LAB", "Unstable experiments offer stronger status cards. Each experiment costs 3 health.", "event")
			var row := HBoxContainer.new()
			content.add_child(row)
			for i in range(event_cards.size()): _card_tile(event_cards[i], row, resolve_event.bind("science_%d" % i) if game.player_hp > 3 else Callable(), "Take card · -3 HP")
			button("Leave experiments · +10 supplies", resolve_event.bind("safe"), content)
		"infirmary":
			reset_panel("A VOLUNTEER'S OFFER", "Full treatment adds Paperwork to your deck: spend 1 energy to discard it. A short break has no downside.", "event")
			button("Full treatment · +%d HP · add Paperwork" % healing_gain(8), resolve_event.bind("treatment"), content).disabled = game.player_hp >= game.PLAYER_MAX_HP
			button("Short break · +%d HP · free" % healing_gain(3), resolve_event.bind("rest"), content)
		"lost_found":
			reset_panel("LOST AND FOUND", "The supply monitor will trade for one card you no longer need.", "event")
			button("Trade 1 card · +25 supplies", show_remove_cards.bind("event"), content).disabled = collection.size() <= 5
			button("Keep your deck · +10 supplies", resolve_event.bind("safe"), content)
		_:
			reset_panel("A LOCKED CLASSROOM", "Emergency supplies wait behind broken glass. Take the risk, or search safely.", "event")
			button("Break glass · +1 card · +30 supplies · -3 HP", event_risk, content).disabled = game.player_hp <= 3
			button("Search the hallway · +10 supplies", resolve_event.bind("safe"), content)

func resolve_event(choice: String) -> void:
	if screen != "event" or event_resolved: return
	if choice in ["risk", "science_0", "science_1"] and game.player_hp <= 3: return
	if choice == "radio_buy" and coins < 20: return
	event_resolved = true
	match choice:
		"risk":
			game.player_hp -= 3
			coins += 30
			add_collection_card(event_cards[0].duplicate(true))
		"radio_buy":
			coins -= 20
			add_collection_card(catalog_card("scout"))
			add_collection_card(catalog_card("tutor"))
		"training": game.add_global_buff(true, "drill_tactics", true)
		"science_0", "science_1":
			game.player_hp -= 3
			add_collection_card(event_cards[int(choice.right(1))].duplicate(true))
		"treatment":
			game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 8)
			add_collection_card({"id":"paperwork", "name":"Paperwork", "type":"response", "element":"clearance", "cost":1, "attack":0, "health":1, "utility":true, "effect":"delay"})
		"rest": game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 3)
		_: coins += 10
	finish_room()

func event_risk() -> void: resolve_event("risk")

func show_menu() -> void:
	if _dragging(): return
	if saved_content: return
	if screen in DECISIONS: return
	reset_panel("MIDNIGHT DRRILLS", "Drag cards onto open Response slots. W / S changes the camera. Adjacent matching types grant +1 attack.", "menu")
	content.add_child(label("Counters: Evac → Earthquake  /  Douse → Fire  /  Clearance → Flood  /  Brace → Typhoon", 17, TEAL))
	content.add_child(label("Armored reduces damage. Fragile increases it. Regenerating heals. Rampaging boosts the second strike. Fierce boosts direct hits.", 16))
	content.add_child(label("Piercing also hits health through blockers. Sluggish attacks every other round. Strength adds attack. Periodic statuses bypass armor.", 16))
	content.add_child(label("BATTLE: " + buff_summary(game.player_buffs) + "\nRUN: " + buff_summary(game.player_run_buffs) + "\nJANITOR BATTLE: " + buff_summary(game.enemy_buffs) + "\nJANITOR RUN: " + buff_summary(game.enemy_run_buffs), 16, TEAL))
	button("Resume", close_modal, content)
	button("Combat log  [L]", show_battle_log, content)
	button("Return to starting screen…", confirm_title, content)
	button("Quit game", quit_game, content)

func quit_game() -> void:
	persistence.checkpoint()
	get_tree().paused = false
	get_tree().quit()

func confirm_title() -> void:
	reset_panel("RETURN TO STARTING SCREEN?", "Your unfinished run is saved. Continue it from the starting screen, or abandon it there.", "menu")
	button("Return to starting screen", return_title, content)
	button("Keep playing", close_modal, content)

func return_title() -> void:
	persistence.checkpoint()
	run_active = false
	get_tree().paused = false
	start_after_reload = false
	get_tree().call_deferred("reload_current_scene")

func confirm_restart() -> void: confirm_title()

func _dragging() -> bool:
	return is_instance_valid(game.dragged_hand_card) and game.dragged_hand_card.is_dragging

func restart_scene() -> void: return_title()

func choose_card(title: String, cards: Array, callback: Callable, cancel: Callable, subtitle: String = "Choose one card. Cancel keeps your spell and energy.") -> void:
	reset_panel(title, subtitle, "choice")
	action_cancel = cancel
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b):
		var first: Dictionary = a.card_data if a is Node else a
		var second: Dictionary = b.card_data if b is Node else b
		return str(first.name) < str(second.name)
	)
	for entry in sorted:
		var definition: Dictionary = live_definition(entry) if entry is Node else entry
		_card_tile(definition, grid, callback.bind(entry), "Choose")
	button("Cancel  [Esc]", cancel, content)

func choose_enemy_hand(cards: Array, callback: Callable, cancel: Callable) -> void:
	if intel_revealed:
		choose_card("CHOOSE AN ENEMY HAND CARD", cards, callback, cancel)
		return
	reset_panel("CHOOSE AN ENEMY HAND CARD", "Only cards currently held by the Janitor can be targeted. Cast Hazard Forecast to reveal their faces first.", "choice")
	action_cancel = cancel
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	for i in range(cards.size()):
		var box := VBoxContainer.new()
		grid.add_child(box)
		var back := TextureRect.new()
		back.texture = CardFace._card_back()
		back.custom_minimum_size = Vector2(180, 235)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(back)
		button("Hand card %d" % (i + 1), callback.bind(cards[i]), box)
	button("Cancel", cancel, content)

func choose_slot(slots: Array, callback: Callable, cancel: Callable) -> void:
	reset_panel("CHOOSE AN EMPTY LANE", "Your selected ally moves to this slot. The newly played card stays on board.", "choice")
	action_cancel = cancel
	for slot in slots: button("Lane %d" % (game._response_slots().find(slot) + 1), callback.bind(slot), content)
	button("Skip movement", cancel, content)

func show_intel() -> void:
	intel_revealed = true
	reset_panel("HAZARD FORECAST", "The Janitor's current hand. This reveal lasts until the encounter ends.", "intel")
	var row := HBoxContainer.new()
	content.add_child(row)
	# Use a scrollable row for a full hand.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.remove_child(row)
	content.add_child(scroll)
	scroll.add_child(row)
	for card in game.enemy_hand: _card_tile(card, row)
	if game.enemy_hand.is_empty(): row.add_child(label("The Janitor's hand is empty."))
	button("Return to battle", close_modal, content)

func show_buff_choices(restore_offers: bool = false) -> void:
	if not restore_offers: buff_choices.clear()
	var pool: Array = Rules.BUFFS.duplicate(true)
	if not restore_offers:
		for i in range(3):
			var index := rng.randi_range(0, pool.size() - 1)
			buff_choices.append(pool.pop_at(index))
	var enemy_choice: Dictionary = game.choose_ai_buff(buff_choices)
	if not restore_offers and not is_instance_valid(game.final_boss): game.add_global_buff(false, enemy_choice.id)
	reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn, "These buffs expire after this battle. The Janitor adaptation is already applied: %s." % enemy_choice.name, "buff")
	if is_instance_valid(game.final_boss): content.get_child(1).text = "Battle-only adaptations. The final boss keeps its fixed attack pattern."
	for buff in buff_choices:
		button(buff.name + "\n" + buff.description, select_buff.bind(buff.id), content)
	content.add_child(label("YOUR BUFFS: " + buff_summary(game.player_buffs) + "\nJANITOR BUFFS: " + buff_summary(game.enemy_buffs), 16, TEAL))

func select_buff(id: String) -> void:
	if screen != "buff" or not buff_choices.any(func(buff): return buff.id == id): return
	game.add_global_buff(true, id)
	close_modal()
	game.continue_round()

func show_floor_buffs(restore_offers: bool = false) -> void:
	if not restore_offers: buff_choices.clear()
	var pool: Array = Rules.RUN_BUFFS.duplicate(true)
	if not restore_offers:
		for i in range(3): buff_choices.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % floor_number, "Choose one buff for the entire run, then climb to the next floor. The Janitor also adapts permanently.", "floor_buff")
	for buff in buff_choices: button(buff.name + "\n" + buff.description, select_floor_buff.bind(buff.id), content)
	button("Return to starting screen", return_title, content)

func select_floor_buff(id: String) -> void:
	if screen != "floor_buff" or not buff_choices.any(func(buff): return buff.id == id): return
	var enemy_choice: Dictionary = game.choose_ai_buff(buff_choices)
	game.add_global_buff(true, id, true)
	game.add_global_buff(false, enemy_choice.id, true)
	next_floor()

func buff_summary(buffs: Dictionary) -> String:
	var names: PackedStringArray = []
	for id in buffs:
		var title: String = str(id).capitalize()
		for option in Rules.BUFFS + Rules.RUN_BUFFS + Rules.CHARACTER_BUFFS:
			if option.id == id:
				title = option.name
				break
		names.append("%s ×%d" % [title, int(buffs[id])])
	return "None" if names.is_empty() else " / ".join(names)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence != null: quit_game()
