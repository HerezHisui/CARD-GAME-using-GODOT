extends CanvasLayer
## Owns the persistent run. Battle copies never mutate the collection.
const UI = preload("res://scripts/ui_theme.gd")
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
const GOLD := UI.GOLD
const TEAL := UI.RESPONSE
const BG := UI.BACKGROUND
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
const INSPECT_HOLD_SECONDS := 0.28
var inspect_hold_serial := 0
var inspect_hold_pending := false
var inspect_hold_origin := Vector2.ZERO
var suppress_inspect_release := false
var inspection_dossier: Control
var modal_scroll: ScrollContainer
var compact_layout := false
var debug_from_menu := false
var confirmation_cancel := Callable()
var modal_dimmer: ColorRect
var reward_selection := -1
var reward_faces: Array[TextureRect] = []
var graveyard_button: Button
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
var plans_meter: ProgressBar
var dashboard: PanelContainer
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
	var menu_panel := PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", style(UI.PANEL, GOLD))
	body.add_child(menu_panel)
	menu_panel.add_child(menu)
	menu.add_child(label("01 / OPERATIONS", 24, GOLD))
	var has_save: bool = persistence.has_run()
	if has_save:
		var saved: Dictionary = persistence.read_save()
		menu.add_child(label("UNFINISHED RUN · FLOOR %d" % int(saved.director.floor_number), 17, TEAL))
		button("Continue run", continue_saved_run, menu).grab_focus()
		button("Abandon run…", confirm_abandon, menu)
	else: button("Singleplayer · Start game", show_characters, menu).grab_focus()
	var multiplayer_button := button("Multiplayer · Coming soon", Callable(), menu)
	multiplayer_button.disabled = true
	button("Quit", quit_game, menu)
	for item in menu.get_children():
		if item is Button:
			item.theme_type_variation = "TerminalButton"
			item.custom_minimum_size.y = 44 if item is OptionButton else 64
			UI.decorate(item, item.disabled)
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
	reset_panel("ABANDON THIS RUN?", "Your saved deck, school route and battle progress will be cleared. Start again from character selection.", "confirm")
	confirmation_cancel = show_title
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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	content.add_child(grid)
	for i in CHARACTERS.size():
		var character: Dictionary = CHARACTERS[i]
		var pick := choice_tile(character.name, "IDENTITY %02d / %s\n\n%s" % [i + 1, "ACTIVE" if character.available else "AVAILABLE SOON", character.description], show_character_preview.bind(i), grid)
		pick.disabled = not character.available
		UI.decorate(pick.get_parent().get_parent(), not character.available)
	button("Back", show_title, content)
	var box := centered_content()
	box.custom_minimum_size.x = 940

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
	fit_card_grid(grid, scroll)
	for card in character_deck(index): _card_tile(card, grid)
	button("Begin run" if CHARACTERS[index].available else "Available soon", start_character.bind(index), content).disabled = not CHARACTERS[index].available
	button("Back to characters", show_characters, content)

func start_character(index: int) -> void:
	if index < 0 or index >= CHARACTERS.size() or not CHARACTERS[index].available: return
	selected_character = index
	last_character = index
	new_run()

func style(color: Color = UI.PANEL, border: Color = UI.BRONZE) -> StyleBoxFlat:
	return UI.panel(color, border)

func label(text: String, font_size: int = 20, color: Color = UI.TEXT, wrap_text: bool = false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if font_size >= 22 else text
	if wrap_text or compact_layout: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", UI.font(font_size >= 22))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func button(text: String, action: Callable, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	if compact_layout:
		b.clip_text = true
		b.tooltip_text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(130, 42)
	if action.is_valid(): b.pressed.connect(action)
	parent.add_child(b)
	if text.begins_with("Confirm") or text.begins_with("Abandon") or text.begins_with("Destroy"):
		b.theme_type_variation = "PrimaryButton"
	game.presentation.button_feedback(b)
	return b

func choice_tile(title: String, description: String, action: Callable, parent: Node) -> Button:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 190)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var pick := button(title, action, box)
	pick.custom_minimum_size.y = 54
	var details := label(description, 18, UI.MUTED)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(details)
	return pick

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	UI.apply_hud(game.get_node("HUD/Root"))
	root.theme = UI.get_theme()
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 78
	header.add_theme_stylebox_override("panel", style(UI.PANEL))
	root.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	header.add_child(row)
	UI.decorate(header)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 225
	row.add_child(brand)
	brand.add_child(label("MIDNIGHT DRRILLS", 22, GOLD))
	brand.add_child(label("THE SCHOOL AFTER DARK", 11, UI.MUTED))
	summary = label("", 16)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(summary)
	button("Deck  [D]", show_deck, row)
	map_button = button("School map  [M]", toggle_map, row)
	menu_button = button("Menu  [Esc]", show_menu, row)
	dashboard = PanelContainer.new()
	dashboard.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dashboard.offset_top = -90
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_theme_stylebox_override("panel", style(UI.INSET, UI.BRONZE))
	var scene_hud := game.get_node("HUD/Root")
	scene_hud.add_child(dashboard)
	scene_hud.move_child(dashboard, 0)
	UI.decorate(dashboard)
	prep = _gauge("PREPAREDNESS ENERGY", true, TEAL)
	threat = _gauge("TENSION", false, UI.DANGER)
	modal_dimmer = ColorRect.new()
	modal_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_dimmer.offset_top = 78
	modal_dimmer.color = Color(UI.BACKGROUND, 0.86)
	modal_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(modal_dimmer)
	modal_dimmer.hide()
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 45
	modal.offset_right = -45
	modal.offset_top = 94
	modal.offset_bottom = -28
	modal.add_theme_stylebox_override("panel", style(UI.PANEL, GOLD))
	root.add_child(modal)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.decorate(modal)
	modal.gui_input.connect(_modal_input)
	modal_scroll = ScrollContainer.new()
	modal_scroll.follow_focus = true
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	modal.add_child(modal_scroll)
	modal_scroll.hide()
	get_viewport().size_changed.connect(func():
		if modal.visible: _panel_layout(screen)
	)
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
	intent_panel.add_theme_stylebox_override("panel", style(UI.PANEL, GOLD))
	intent_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(intent_panel)
	boss_intent = label("", 16, GOLD)
	boss_intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_panel.add_child(boss_intent)
	intent_panel.hide()
	var plans_box := VBoxContainer.new()
	plans_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	plans_box.offset_left = 260
	plans_box.offset_right = 450
	plans_box.offset_top = -78
	plans_box.offset_bottom = -15
	root.add_child(plans_box)
	plans_meter = ProgressBar.new()
	plans_meter.custom_minimum_size = Vector2(180, 12)
	plans_meter.max_value = 2
	plans_meter.show_percentage = false
	plans_box.add_child(plans_meter)
	plans_button = button("Contingency 0/2  [P]", show_plans, plans_box)
	plans_button.tooltip_text = "Bank 2 unused energy for one Plan. Arm a contingency before combat."
	graveyard_button = button("Graveyard [G]", show_graveyard, root)
	graveyard_button.name = "GraveyardButton"
	graveyard_button.tooltip_text = "Response graveyard. Inspect lost units and eligible recovery targets."
	place_dashboard_button(graveyard_button, -560, -394)
	var log_button := button("Combat log [L]", show_battle_log, root)
	log_button.name = "CombatLogButton"
	place_dashboard_button(log_button, 470, 650, false)
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

func place_dashboard_button(control: Control, left: float, right: float, align_right: bool = true) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT if align_right else Control.PRESET_BOTTOM_LEFT)
	control.offset_left = left
	control.offset_right = right
	control.offset_top = -73
	control.offset_bottom = -17

func _gauge(title: String, right: bool, color: Color) -> ProgressBar:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if right else Control.PRESET_TOP_RIGHT)
	box.offset_left = 24 if right else -240
	box.offset_right = 240 if right else -24
	box.offset_top = -78 if right else 158
	box.offset_bottom = -12 if right else 215
	box.add_child(label(title, 14, color))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(195, 20)
	bar.add_theme_stylebox_override("background", UI.panel(UI.INSET, UI.BRONZE, 0))
	bar.add_theme_stylebox_override("fill", UI.bar(color))
	box.add_child(bar)
	if right: box.add_child(label("", 13, UI.MUTED))
	return bar

func _process(_delta: float) -> void:
	if inspect_hold_pending and not game.board_input.action.is_empty(): cancel_inspect_hold()
	modal_dimmer.visible = modal.visible and battle_active and screen not in ["map", "inspect", "reward"]
	game.visible = battle_active or screen == "reward"
	board_prompt.visible = battle_active and not modal.visible and not game.board_input.action.is_empty()
	if board_prompt.visible: board_prompt_label.text = str(game.board_input.action.get("title", "Choose a board target"))
	game.opponent_hand.visible = battle_active and not modal.visible
	game.get_node("HUD/Root/EndTurnButton").disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or not game.board_input.action.is_empty() or _dragging()
	plans_button.visible = battle_active and not modal.visible
	plans_button.disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or _dragging() or not game.board_input.action.is_empty()
	plans_button.text = "Contingency %d/2 [P]" % game.plans.tokens
	plans_meter.value = game.plans.tokens
	plans_meter.get_parent().visible = battle_active and not modal.visible
	dashboard.visible = battle_active and not modal.visible
	root.get_node("CombatLogButton").visible = battle_active and not modal.visible
	graveyard_button.visible = battle_active and not modal.visible and not game.presentation.blocking
	graveyard_button.disabled = _dragging() or not game.board_input.action.is_empty()
	boss_intent.visible = is_instance_valid(game.final_boss) and battle_active and not modal.visible and game.board_input.action.is_empty()
	boss_intent.get_parent().visible = boss_intent.visible
	if boss_intent.visible: boss_intent.text = game.final_boss.intent()
	summary.text = "Floor %d  /  HP %d  /  %d supplies  /  %d cards" % [floor_number, game.player_hp, coins, collection.size()]
	prep.max_value = game.energy_cap
	prep.value = game.preparedness
	threat.max_value = game.tension_cap
	threat.value = game.tension
	prep.get_parent().get_child(0).text = "ENERGY  %d / %d" % [game.preparedness, game.energy_cap]
	threat.get_parent().get_child(0).text = "TENSION  %d / %d" % [game.tension, game.tension_cap]
	prep.get_parent().get_child(2).text = "Deck %d" % game.deck.size()
	game.get_node("HUD/Root").visible = battle_active and not modal.visible
	game.get_node("HUD/Root/DeckDrawButton/DeckCountLabel").text = "Draw · %d left" % game.deck.size()
	root.get_child(0).visible = screen not in ["title", "title_help", "characters", "character_preview"]
	map_button.disabled = saved_content != null or screen in DECISIONS or not game.board_input.action.is_empty()
	menu_button.disabled = map_button.disabled
	idle_hint.visible = false
	prep.get_parent().visible = battle_active and not modal.visible
	threat.get_parent().visible = battle_active and not modal.visible

func _input(event: InputEvent) -> void:
	if inspect_hold_pending and event is InputEventMouseMotion and event.position.distance_to(inspect_hold_origin) > 12:
		cancel_inspect_hold()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_inspect_hold()
		if suppress_inspect_release or screen == "inspect" or root.has_node("CatalogInspection"):
			suppress_inspect_release = false
			get_viewport().set_input_as_handled()
			return
	if screen == "debug_password":
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			cancel_debug_password()
			get_viewport().set_input_as_handled()
		return
	if screen == "inspect" or root.has_node("CatalogInspection"):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			dismiss_inspection()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var on_card := is_instance_valid(inspected_face) and inspected_face.get_global_rect().has_point(event.position)
			var on_dossier := is_instance_valid(inspection_dossier) and inspection_dossier.get_global_rect().has_point(event.position)
			if on_card or not on_dossier:
				dismiss_inspection()
				get_viewport().set_input_as_handled()
		return
	if game.presentation.blocking: return
	if screen == "reward":
		if reward_selection >= 0:
			_modal_input(event)
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				show_rewards()
				get_viewport().set_input_as_handled()
		return
	if screen == "graveyard" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not modal.get_global_rect().has_point(event.position):
		close_modal()
		get_viewport().set_input_as_handled()
		return
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
			KEY_F3: show_debug()
			KEY_D: show_deck()
			KEY_L: show_battle_log()
			KEY_P: show_plans()
			KEY_G:
				if screen == "graveyard": close_modal()
				else: show_graveyard()
			KEY_M: toggle_map()
			KEY_ESCAPE:
				if screen == "confirm" and confirmation_cancel.is_valid():
					confirmation_cancel.call()
				elif screen == "choice" and action_cancel.is_valid():
					action_cancel.call()
				elif screen in ["intel", "inspect", "plans", "log", "graveyard", "debug"]: close_modal()
				elif screen in ["deck", "menu", "confirm"] or (modal.visible and screen == "map" and battle_active):
					close_modal()
				else:
					show_menu()
			_: return
		get_viewport().set_input_as_handled()

func _panel_layout(kind: String) -> void:
	compact_layout = kind in ["menu", "confirm", "debug_password", "debug", "log", "plans", "choice", "remove_confirm"]
	modal.custom_minimum_size = Vector2.ZERO
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if compact_layout:
		if content.get_parent() != modal_scroll: content.reparent(modal_scroll)
		modal_scroll.show()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var viewport_size := get_viewport().get_visible_rect().size
		var height := 360.0 if kind == "debug_password" else (420.0 if kind == "confirm" else 680.0)
		var panel_size := Vector2(minf(420, viewport_size.x - 32), minf(height, viewport_size.y - 48))
		modal.offset_left = (viewport_size.x - panel_size.x) / 2
		modal.offset_right = -modal.offset_left
		modal.offset_top = (viewport_size.y - panel_size.y) / 2
		modal.offset_bottom = -modal.offset_top
		modal.add_theme_stylebox_override("panel", style(UI.PANEL, GOLD))
		game.visible = battle_active
		return
	if content.get_parent() != modal: content.reparent(modal)
	modal_scroll.hide()
	var title_screen := kind in ["title", "title_help", "characters", "character_preview"]
	var full_screen := title_screen or not battle_active or kind in ["map", "reward", "inspect"]
	game.visible = battle_active or kind == "reward"
	modal.offset_left = 0 if full_screen else 45
	modal.offset_right = 0 if full_screen else -45
	modal.offset_top = (0 if title_screen or not battle_active or kind in ["reward", "inspect"] else 78) if full_screen else 94
	modal.offset_bottom = 0 if full_screen else -28
	var panel_style := style(Color(UI.BACKGROUND, 0.90) if kind in ["reward", "inspect"] else (BG if full_screen else UI.PANEL), GOLD)
	if full_screen:
		panel_style.set_border_width_all(0)
		panel_style.set_corner_radius_all(0)
		panel_style.content_margin_left = 55
		panel_style.content_margin_right = 55
		panel_style.content_margin_top = 45 if title_screen else 20
		panel_style.content_margin_bottom = 35 if title_screen else 20
	modal.add_theme_stylebox_override("panel", panel_style)
	if kind == "graveyard":
		var viewport_size := get_viewport().get_visible_rect().size
		var panel_size := Vector2(minf(700, viewport_size.x - 48), minf(500, viewport_size.y - 150))
		modal.offset_left = (viewport_size.x - panel_size.x) / 2
		modal.offset_right = -modal.offset_left
		modal.offset_top = (viewport_size.y - panel_size.y) / 2
		modal.offset_bottom = -modal.offset_top

func reset_panel(title: String, subtitle: String, kind: String) -> void:
	var catalog_inspection := root.get_node_or_null("CatalogInspection")
	if catalog_inspection: catalog_inspection.queue_free()
	game.presentation.clear_banner()
	cancel_inspect_hold()
	_panel_layout(kind)
	game.clear_hand_hover()
	if battle_active: get_tree().paused = true
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	screen = kind
	modal.show()
	content.add_child(label(title, 24 if compact_layout else 30, GOLD, compact_layout))
	content.add_child(label(subtitle, 16, UI.MUTED, true))
	game.presentation.reveal(content)
	if compact_layout: _fit_compact_content.call_deferred()

func _fit_compact_content() -> void:
	if not compact_layout: return
	for child in content.get_children():
		if child is ScrollContainer:
			child.custom_minimum_size.y = 180
			child.follow_focus = true

func close_modal() -> void:
	if saved_content:
		content.get_parent().remove_child(content)
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
	game.player_hp = game.hero_max_hp()
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
	reset_panel("THE SCHOOL MAP", "Choose an illuminated room. Follow the connected route upward to the Janitor.", "map")
	var canvas := RouteCanvas.new()
	canvas.rooms = rooms
	canvas.current = current
	canvas.cleared = cleared
	canvas.custom_minimum_size = Vector2(580, 1660)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var route_row := HBoxContainer.new()
	route_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(route_row)
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_row.add_child(map_scroll)
	map_scroll.add_child(canvas)
	var dossier := PanelContainer.new()
	dossier.custom_minimum_size.x = 255
	route_row.add_child(dossier)
	var dossier_text := VBoxContainer.new()
	dossier.add_child(dossier_text)
	dossier_text.add_child(label("FLOOR / %02d" % floor_number, 28, GOLD))
	dossier_text.add_child(label("SCHOOL OPERATIONS", 14, UI.MUTED))
	dossier_text.add_child(HSeparator.new())
	dossier_text.add_child(label("%d / %d rooms cleared" % [cleared.size(), rooms.size()], 17))
	var route_help := label("Choose a connected room.\n\nBATTLE / Build your deck\nELITE / Unlock a tactic\nREST / Heal or train\nSHOP / Spend supplies\nEVENT / Risk and reward\nUPGRADE / Improve a card\n\nDESTINATION\nThe Janitor", 17, UI.MUTED)
	route_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dossier_text.add_child(route_help)
	dossier_text.add_child(label("▲  ASCEND TO SURVIVE", 14, GOLD))
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	animate_map.call_deferred(weakref(map_scroll), maxi(0, 1660 - 100 - (int(rooms[current].row) if current >= 0 else 0) * 145 - 280))
	canvas.resized.connect(func():
		for b in canvas.get_children():
			b.position = canvas.point(rooms[int(b.get_meta("room"))]) - b.size / 2
	)
	for room in rooms:
		var id: int = room.id
		var b := button(("✓ " if id in cleared else "") + str(room.kind).to_upper(), visit.bind(id), canvas)
		b.set_meta("room", id)
		b.custom_minimum_size = Vector2(140, 68)
		b.size = Vector2(140, 68)
		b.disabled = not reachable(id)
		if not b.disabled: b.add_theme_stylebox_override("normal", style(UI.RAISED, GOLD))
		if id in cleared:
			b.add_theme_stylebox_override("disabled", style(UI.PANEL, UI.RESPONSE))
			b.add_theme_color_override("font_disabled_color", UI.RESPONSE)
		b.tooltip_text = "Room %d · %s" % [room.row + 1, room.kind]
		if room.kind == "boss" and floor_number == 3:
			b.text = "FINAL BOSS"
			b.tooltip_text = "Final boss: three telegraphed phases. Prepare healing, barriers and AoE."
		b.position = canvas.point(room) - b.size / 2
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	content.add_child(footer)
	var legend := label("Battle  /  Elite  /  Rest  /  Workshop  /  Event  /  Shop  ↑  JANITOR", 16, TEAL, true)
	legend.custom_minimum_size.x = 320
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(legend)
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
	return maxi(0, mini(amount, game.hero_max_hp() - game.player_hp))

func rest() -> void:
	game.player_hp = mini(game.hero_max_hp(), game.player_hp + 7)
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
	var triage := healing_gain(3) if encounter == "battle" else 0
	game.player_hp += triage
	game._refresh_bars()
	coins += 35 if encounter == "elite" else (60 if encounter == "boss" else 20)
	if encounter == "boss":
		game.clear_battle(true)
		show_contingency_reward("victory" if floor_number == 3 else "floor")
	elif encounter == "elite": show_contingency_reward("cards")
	else:
		show_rewards()
	var recovery := " · +%d HP triage" % triage if encounter == "battle" else ""
	game.presentation.banner("BATTLE VICTORY", "+%d supplies" % (35 if encounter == "elite" else (60 if encounter == "boss" else 20)) + recovery)

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
	var row := HBoxContainer.new()
	content.add_child(row)
	for tactic in buff_choices:
		choice_tile(tactic.name + " · %d Plan%s" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""], tactic.description, select_contingency_reward.bind(tactic.id), row)
	centered_content().custom_minimum_size.x = 1060

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
	game.player_hp = mini(game.hero_max_hp(), game.player_hp + 5)
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

func show_rewards(selected: int = -1) -> void:
	reward_selection = selected
	reward_faces.clear()
	reset_panel("DISASTER CONTAINED", "Click a card to inspect it. Click the enlarged card again to keep it.", "reward")
	var box := centered_content()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	if reward_stock.is_empty(): reward_stock = offers(3)
	if selected >= 0 and selected < reward_stock.size():
		inspected_face = reward_face(selected, row, 330)
		add_dossier(row, reward_stock[selected], "Press this card again to claim it. Press outside to compare rewards.")
	else:
		reward_selection = -1
		for i in reward_stock.size():
			var column := VBoxContainer.new()
			row.add_child(column)
			var face := reward_face(i, column, 245)
			game.presentation.card_feedback(face)
			game.presentation.reveal(column)
		button("Skip card reward", finish_room, box)

func reward_face(index: int, parent: Node, width: float) -> TextureRect:
	var card: Dictionary = reward_stock[index]
	var preview = game.Card3DScene.instantiate()
	preview.preview_only = true
	preview.input_ray_pickable = false
	preview.collision_layer = 0
	preview.collision_mask = 0
	parent.add_child(preview)
	preview.setup(card)
	if card.has("statuses"):
		preview.statuses = card.statuses.duplicate()
		preview._refresh_face()
	preview.set_process(false)
	preview.hide()
	var face := card_image(preview._vp.get_texture(), parent, width)
	face.tooltip_text = "Press to inspect. Press the enlarged card again to claim."
	reward_faces.append(face)
	face.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_reward(index)
			get_viewport().set_input_as_handled()
	)
	return face

func select_reward(index: int) -> void:
	if screen != "reward" or index < 0 or index >= reward_stock.size(): return
	if reward_selection != index:
		show_rewards(index)
		return
	add_collection_card(reward_stock[index].duplicate(true))
	finish_room()

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
	if screen == "reward" and reward_selection >= 0 and is_instance_valid(inspected_face):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not inspected_face.get_global_rect().has_point(event.global_position):
			show_rewards()
			get_viewport().set_input_as_handled()
		return

func _card_tile(card: Dictionary, parent: Node, action: Callable = Callable(), action_text: String = "") -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style(UI.PANEL, UI.BRONZE))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var center := CenterContainer.new()
	box.add_child(center)
	var preview = game.Card3DScene.instantiate()
	preview.preview_only = true
	preview.input_ray_pickable = false
	preview.collision_layer = 0
	preview.collision_mask = 0
	panel.add_child(preview)
	preview.setup(card)
	if card.has("statuses"):
		preview.statuses = card.statuses.duplicate()
		preview._refresh_face()
	preview.set_process(false)
	preview.hide()
	var face := card_image(preview._vp.get_texture(), center, 180)
	face.tooltip_text = "Hold to inspect " + str(card.name)
	face.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	face.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			begin_catalog_hold(card, face)
	)
	var caption := label("UPGRADE  %d / 2" % upgrade_level(card), 13, UI.MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	if action.is_valid(): button(action_text, action, box)

func begin_catalog_hold(card: Dictionary, face: Control) -> void:
	cancel_inspect_hold()
	inspect_hold_pending = true
	inspect_hold_origin = get_viewport().get_mouse_position()
	var serial := inspect_hold_serial
	await get_tree().create_timer(INSPECT_HOLD_SECONDS).timeout
	if serial != inspect_hold_serial or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	if not is_instance_valid(face) or not face.get_global_rect().has_point(get_viewport().get_mouse_position()): return
	inspect_hold_pending = false
	show_catalog_inspection(card, face.texture)

func show_catalog_inspection(card: Dictionary, texture: Texture2D) -> void:
	if root.has_node("CatalogInspection"): return
	var overlay := ColorRect.new()
	overlay.name = "CatalogInspection"
	overlay.color = Color(UI.BACKGROUND, 0.96)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	center.add_child(row)
	inspected_face = card_image(texture, row, 310)
	add_dossier(row, card, "Click the card or outside this panel, or press Esc, to close.")

func add_dossier(parent: Node, card: Dictionary, hint: String, live_card: Node = null) -> RichTextLabel:
	var panel := PanelContainer.new()
	inspection_dossier = panel
	panel.custom_minimum_size = Vector2(440, 420)
	parent.add_child(panel)
	UI.decorate(panel)
	var details := RichTextLabel.new()
	details.name = "DossierText"
	details.bbcode_enabled = true
	details.text = "[color=#%s][b]%s[/b][/color]\n" % [UI.GOLD.to_html(false), str(card.name).to_upper()]
	details.text += "ATK %d  /  HP %d\n\n" % [int(card.get("preview_attack", card.get("attack", 0))), int(card.get("health", 0))]
	var disaster: bool = card.get("type", "response") == "disaster"
	var sacrifice: bool = disaster and not card.get("utility", false) and int(card.get("cost", 0)) > 0
	if sacrifice: details.text += "SAC: %d allied units to evolve.\n\n" % int(card.cost)
	elif disaster: details.text += "Cost: %d Tension.\n\n" % int(card.get("tension_cost", 1))
	else: details.text += "Cost: %d energy.\n\n" % int(card.get("cost", 0))
	details.text += "[b]PERMANENT UPGRADES  %d / 2[/b]\n" % upgrade_level(card)
	var effects: Dictionary = live_card.statuses if is_instance_valid(live_card) else card.get("statuses", {})
	var tokens: PackedStringArray = []
	for status in effects:
		if int(effects[status]) > 0: tokens.append("%s %d" % [str(status).capitalize(), int(effects[status])])
	if not tokens.is_empty(): details.text += "\n[b]CURRENT STATUSES[/b]\n" + " · ".join(tokens) + "\n"
	var combat: PackedStringArray = []
	if is_instance_valid(live_card):
		if live_card.planned_guard > 0: combat.append("Plan protection: %d" % live_card.planned_guard)
		if live_card.plan_attack_bonus > 0: combat.append("Plan attack: +%d" % live_card.plan_attack_bonus)
		if live_card.plan_ignore_taunt: combat.append("Ignore Taunt")
		if game.buff_value(live_card.card_data.type == "response", "kill_or_die") > 0: combat.append("Blood Pact: defeat a card this turn or die")
	if not combat.is_empty(): details.text += "\n[b]THIS COMBAT[/b]\n" + "\n".join(combat) + "\n"
	var rules: PackedStringArray = []
	for line in card_rules(card).split("\n"):
		if line.is_empty() or line.begins_with("Adjacent matching types:") or line.begins_with("All other matchups:") or line.begins_with("Choose an empty Response slot") or line.begins_with("Piercing:") or line.begins_with("Sluggish:"): continue
		rules.append(line)
	var active_modifiers: Array = live_card.modifiers.duplicate() if is_instance_valid(live_card) else card.get("modifiers", []).duplicate()
	var primary: String = str(card.get("modifier", "")).to_lower()
	if not primary.is_empty() and primary not in active_modifiers: active_modifiers.append(primary)
	if is_instance_valid(live_card):
		for inherited in ["piercing", "sluggish"]:
			if live_card.has_modifier(inherited) and inherited not in active_modifiers: active_modifiers.append(inherited)
	var descriptions := {
		"armored":"Armored: take %d less ordinary damage (minimum 1 before other modifiers)." % int(card.get("armor_value", 1)),
		"fragile":"Fragile: take 1 extra ordinary damage.",
		"regenerating":"Regenerating: heal 1 at upkeep.",
		"rampaging":"Rampaging: +1 unit damage when attacking second.",
		"fierce":"Fierce: +2 direct hero damage.",
		"piercing":"Piercing: also damages the opposing hero when blocked.",
		"sluggish":"Sluggish: attacks every other round."
	}
	for modifier in active_modifiers:
		rules.append(descriptions.get(modifier, str(modifier).capitalize()))
	if not rules.is_empty(): details.text += "\n[b]CARD EFFECTS[/b]\n" + "\n".join(rules)
	if not hint.is_empty(): details.text += "\n\n" + hint
	panel.add_child(details)
	return details

func fit_card_grid(grid: GridContainer, scroll: ScrollContainer) -> void:
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	var grid_ref: WeakRef = weakref(grid)
	var scroll_ref: WeakRef = weakref(scroll)
	var resize_grid := func():
		var live_grid = grid_ref.get_ref()
		var live_scroll = scroll_ref.get_ref()
		if not is_instance_valid(live_grid) or not is_instance_valid(live_scroll): return
		live_grid.columns = clampi(int((live_scroll.size.x - 16) / 236), 1, 8)
	scroll.resized.connect(resize_grid)
	resize_grid.call_deferred()

func show_deck() -> void:
	if _dragging(): return
	if screen in ["title", "title_help", "characters", "character_preview"]: return
	if screen == "deck":
		close_modal()
		return
	if screen in DECISIONS:
		saved_content = content
		saved_screen = screen
		content.get_parent().remove_child(content)
		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		modal.add_child(content)
	reset_panel("YOUR RESPONSE DECK", "%d collected cards. Browse your formation. Hold a card for its rules. Draw-pile order stays hidden." % collection.size(), "deck")
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	button("Deck (%d)" % collection.size(), deck_cards.bind(collection), tabs)
	button("Response Graveyard", func(): close_modal(); show_graveyard(), tabs).disabled = not battle_active or saved_content != null
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
		content.get_parent().remove_child(content)
		content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		modal.add_child(content)

func cancel_inspect_hold() -> void:
	inspect_hold_serial += 1
	inspect_hold_pending = false

func dismiss_inspection() -> void:
	cancel_inspect_hold()
	suppress_inspect_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var catalog_panel := root.get_node_or_null("CatalogInspection")
	if catalog_panel: catalog_panel.queue_free()
	elif screen == "inspect": close_modal()

func begin_inspect_hold(card: Node, from_hand: bool = false) -> void:
	if not battle_active or modal.visible or (_dragging() and not from_hand) or game.presentation.blocking or game.in_board_view: return
	cancel_inspect_hold()
	inspect_hold_pending = true
	inspect_hold_origin = get_viewport().get_mouse_position()
	var serial := inspect_hold_serial
	var origin := get_viewport().get_mouse_position()
	await get_tree().create_timer(INSPECT_HOLD_SECONDS).timeout
	if serial != inspect_hold_serial or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	if origin.distance_to(get_viewport().get_mouse_position()) > 12: return
	if not is_instance_valid(card) or not card.is_alive(): return
	if from_hand:
		if game.dragged_hand_card != card or not card.is_dragging: return
		card.cancel_hand_drag()
	if not game.board_input.action.is_empty() or game.presentation.blocking or modal.visible: return
	inspect_hold_pending = false
	inspect_board_card(card, from_hand)

func inspect_board_card(card: Node, allow_hand: bool = false) -> void:
	if not battle_active or modal.visible or _dragging() or not is_instance_valid(card) or (card.in_hand and not allow_hand): return
	reset_panel("CARD INSPECTION", "Click the card or outside this panel, or press Esc, to close.", "inspect")
	var box := centered_content()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	box.add_child(row)
	card._refresh_face()
	inspected_face = card_image(card._vp.get_texture(), row, 330)
	add_dossier(row, live_definition(card), "Click the card or outside this panel, or press Esc, to close.", card)

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
	save.text = "Auto-save 2 energy"
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
		var pick := choice_tile(tactic.name + " · %d Plan%s" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""], tactic.description, begin_tactic.bind(id), list)
		pick.disabled = not tactic_available(id)
		pick.get_parent().get_parent().custom_minimum_size.y = 125
	if not game.plans.armed.is_empty(): content.add_child(label("ARMED: " + str(game.plans.definition(game.plans.armed.kind).name), 18, GOLD))
	content.add_child(label("One armed tactic per round. Targeted tactics use board clicks. Esc cancels target selection without spending.", 16))
	button("Return to battle  [P / Esc]", close_modal, content)

func tactic_available(id: String) -> bool:
	var tactic: Dictionary = game.plans.definition(id)
	if game.phase != game.Phase.PLAYER_PLAY or game.plans.tokens < int(tactic.cost) or game.plans.committed_round == game.turn: return false
	var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
	if id == "coordinate": return not allies.is_empty()
	if id == "supply": return not game.deck.is_empty() and game.get_hand_cards().size() < game.HAND_SIZE_MAX
	if id == "shelter": return true
	if id == "extract": return not allies.is_empty() and game._response_slots().any(func(slot): return game._get_card_in_slot(slot) == null)
	return not allies.is_empty()

func begin_tactic(id: String) -> void:
	if not tactic_available(id): return
	close_modal()
	if id == "coordinate":
		var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
		game.board_input.pick("Click one ally. It and the nearest ally on each side gain +1 attack this combat. Esc cancels.", allies, arm_target_tactic.bind("coordinate"), Callable())
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
func select_extraction_ally(card: Node) -> void:
	extraction_card = card
	game.board_input.destination(card, arm_extraction)

func arm_extraction(slot: Node3D) -> void:
	game.plans.arm("extract", [extraction_card], slot)
	extraction_card = null

func show_graveyard() -> void:
	if not battle_active or _dragging() or not game.board_input.action.is_empty() or screen in DECISIONS or saved_content != null: return
	if screen == "graveyard":
		close_modal()
		return
	refresh_graveyard()

func refresh_graveyard() -> void:
	reset_panel("RESPONSE GRAVEYARD (%d)" % game.player_graveyard.size(), "Recovery Detail returns a destroyed Response unit once per battle.", "graveyard")
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	button("Close", close_modal, tabs)
	var sort := OptionButton.new()
	for key in SORT_KEYS: sort.add_item("Recently added" if key == "acquired" else str(key).capitalize())
	sort.select(deck_sort)
	sort.item_selected.connect(func(index): deck_sort = index; refresh_graveyard())
	tabs.add_child(sort)
	button("Descending" if deck_descending else "Ascending", func(): deck_descending = not deck_descending; refresh_graveyard(), tabs)
	for control in tabs.get_children(): control.custom_minimum_size.x = 100
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var cards: Array = game.player_graveyard
	viewed_cards.assign(cards)
	var details := RichTextLabel.new()
	details.custom_minimum_size.y = 100
	details.text = "Select an entry to read its effects."
	for index in sorted_indices(cards, deck_sort, deck_descending):
		var entry: Dictionary = cards[index]
		var row := button("%s · %s · round %d" % [entry.name, entry.get("graveyard_reason", "Destroyed"), int(entry.get("graveyard_round", 1))], func(): details.text = "%s · Cost %d · Attack %d · Health %d\n%s" % [entry.name, int(entry.get("cost", 0)), int(entry.get("attack", 0)), int(entry.get("health", 1)), card_rules(entry)], list)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cards.is_empty():
		var empty := VBoxContainer.new()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.add_child(empty)
		var title := label("NO FALLEN RESPONSE CARDS", 22, GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(title)
		var hint := label("Destroyed units and spent utilities appear here.", 16, UI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(hint)
		details.text = "RECOVERY DETAIL\nReturn a destroyed unit to your hand once per battle."
	content.add_child(details)

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
	definition.preview_attack = card.effective_attack()
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
	if effect == "grave_guard": rules += str(Rules.EFFECTS.grave_guard) + "\n"
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
	fit_card_grid(grid, scroll)
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
		if screen == "graveyard":
			refresh_graveyard()
			return
		deck_cards(viewed_cards)

func reverse_sort(workshop: bool) -> void:
	if workshop:
		upgrade_descending = not upgrade_descending
		show_upgrade()
	else:
		deck_descending = not deck_descending
		if screen == "graveyard":
			refresh_graveyard()
			return
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
	fit_card_grid(grid, scroll)
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
		elif result.get("effect", "") in ["move", "tutor", "scout", "recover"]: result.refund_energy = int(result.get("refund_energy", 0)) + 1
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
		elif coins < price: row.get_child(row.get_child_count() - 1).get_child(0).add_child(label("Need %d supplies" % price, 14, UI.MUTED))
	button("First aid · +%d HP · -15 supplies" % healing_gain(5), buy_heal, content).disabled = coins < 15 or game.player_hp >= game.hero_max_hp()
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
	if coins < 15 or game.player_hp >= game.hero_max_hp(): return
	coins -= 15
	game.player_hp = mini(game.hero_max_hp(), game.player_hp + 5)
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
	fit_card_grid(grid, scroll)
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
			button("Full treatment · +%d HP · add Paperwork" % healing_gain(8), resolve_event.bind("treatment"), content).disabled = game.player_hp >= game.hero_max_hp()
			button("Short break · +%d HP · free" % healing_gain(3), resolve_event.bind("rest"), content)
		"lost_found":
			reset_panel("LOST AND FOUND", "The supply monitor will trade for one card you no longer need.", "event")
			button("Trade 1 card · +25 supplies", show_remove_cards.bind("event"), content).disabled = collection.size() <= 5
			button("Keep your deck · +10 supplies", resolve_event.bind("safe"), content)
		_:
			reset_panel("A LOCKED CLASSROOM", "Emergency supplies wait behind broken glass. Take the risk, or search safely.", "event")
			button("Break glass · +1 card · +30 supplies · -3 HP", event_risk, content).disabled = game.player_hp <= 3
			button("Search the hallway · +10 supplies", resolve_event.bind("safe"), content)

	var box := centered_content()
	box.custom_minimum_size.x = 940

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
			game.player_hp = mini(game.hero_max_hp(), game.player_hp + 8)
			add_collection_card({"id":"paperwork", "name":"Paperwork", "type":"response", "element":"clearance", "cost":1, "attack":0, "health":1, "utility":true, "effect":"delay"})
		"rest": game.player_hp = mini(game.hero_max_hp(), game.player_hp + 3)
		_: coins += 10
	finish_room()

func event_risk() -> void: resolve_event("risk")

func show_menu() -> void:
	if _dragging(): return
	if saved_content: return
	if screen in DECISIONS: return
	reset_panel("MIDNIGHT DRRILLS", "Drag cards onto open Response slots. W / S changes the camera. Adjacent matching types grant +1 attack.", "menu")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 140
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var rules_box := VBoxContainer.new()
	rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rules_box)
	rules_box.add_child(label("Counters: Evac → Earthquake  /  Douse → Fire  /  Clearance → Flood  /  Brace → Typhoon", 17, TEAL, true))
	rules_box.add_child(label("Armored reduces damage. Fragile increases it. Regenerating heals. Rampaging boosts the second strike. Fierce boosts direct hits.", 16, UI.TEXT, true))
	rules_box.add_child(label("Piercing also hits health through blockers. Sluggish attacks every other round. Strength adds attack. Periodic statuses bypass armor.", 16, UI.TEXT, true))
	rules_box.add_child(label("BATTLE: " + buff_summary(game.player_buffs) + "\nRUN: " + buff_summary(game.player_run_buffs) + "\nJANITOR BATTLE: " + buff_summary(game.enemy_buffs) + "\nJANITOR RUN: " + buff_summary(game.enemy_run_buffs), 16, TEAL, true))
	button("Resume", close_modal, content)
	if battle_active: button("Debug values  [F3]", show_debug, content)
	button("Combat log  [L]", show_battle_log, content)
	button("Return to starting screen…", confirm_title, content)
	button("Quit game", quit_game, content)

func quit_game() -> void:
	persistence.checkpoint()
	get_tree().paused = false
	get_tree().quit()

func debug_available() -> bool:
	return battle_active and not _dragging() and game.board_input.action.is_empty() and game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]

func cancel_debug_password() -> void:
	if debug_from_menu: show_menu()
	else: close_modal()

func show_debug() -> void:
	if screen == "debug":
		close_modal()
		return
	if not debug_available() or (modal.visible and screen != "menu"): return
	debug_from_menu = screen == "menu"
	reset_panel("DEBUG ACCESS", "Enter the five-character password to open debug values.", "debug_password")
	var password := LineEdit.new()
	password.name = "DebugPassword"
	password.secret = true
	content.add_child(password)
	var error := label("", 14, UI.DANGER, true)
	error.name = "PasswordError"
	content.add_child(error)
	var submit := func():
		if password.text != "*****":
			error.text = "Incorrect password."
			return
		password.text = ""
		if not debug_available():
			cancel_debug_password()
			return
		_open_debug("*****")
	password.text_submitted.connect(func(_text): submit.call())
	button("Unlock", submit, content)
	button("Cancel", cancel_debug_password, content)
	password.grab_focus()

func _open_debug(password: String) -> void:
	if password != "*****" or screen != "debug_password" or not debug_available(): return
	reset_panel("DEBUG VALUES", "Apply changes to this run. Normal autosaves will include these values.", "debug")
	var fields := {}
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	content.add_child(grid)
	for spec in [["player_hp", "Player HP", 1, game.hero_max_hp()], ["enemy_hp", "Enemy HP", 1, game.enemy_max_hp], ["energy_cap", "Energy capacity", 1, 30], ["preparedness", "Current energy", 0, 30], ["tension_cap", "Tension capacity", 1, 30], ["tension", "Current tension", 0, 30], ["coins", "Supplies", 0, 9999], ["plans", "Plans", 0, 2]]:
		var caption := label(spec[1], 18)
		caption.custom_minimum_size.x = 160
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(caption)
		var field := SpinBox.new()
		field.custom_minimum_size.x = 140
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.min_value = spec[2]
		field.max_value = spec[3]
		field.step = 1
		field.value = coins if spec[0] == "coins" else (game.plans.tokens if spec[0] == "plans" else game.get(spec[0]))
		grid.add_child(field)
		fields[spec[0]] = field
	button("Apply values", func():
		for key in fields:
			if key == "coins": coins = int(fields[key].value)
			elif key == "plans": game.plans.tokens = int(fields[key].value)
			else: game.set(key, int(fields[key].value))
		game.preparedness = mini(game.preparedness, game.energy_cap)
		game.tension = mini(game.tension, game.tension_cap)
		game._refresh_bars()
		game.log_event("Debug values applied.")
		close_modal()
		persistence.checkpoint()
	, content)
	content.add_child(label("LIVE CARD STATUS", 20, GOLD))
	var status_row := VBoxContainer.new()
	content.add_child(status_row)
	var targets := game.get_tree().get_nodes_in_group("cards").filter(func(card): return is_instance_valid(card) and card.is_alive() and not card.preview_only)
	var target := OptionButton.new()
	target.custom_minimum_size.x = 280
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.clip_text = true
	for card in targets: target.add_item(("HAND / " if card.in_hand else "BOARD / ") + str(card.card_data.name))
	status_row.add_child(target)
	var status := OptionButton.new()
	for key in ["strength", "bleed", "burn", "poison", "barrier", "healing_reduced"]: status.add_item(key.replace("_", " ").capitalize())
	status_row.add_child(status)
	var amount := SpinBox.new()
	amount.max_value = 99
	amount.custom_minimum_size.x = 100
	status_row.add_child(amount)
	button("Set status", func():
		if target.selected < 0 or target.selected >= targets.size(): return
		var card: Node = targets[target.selected]
		if not is_instance_valid(card) or not card.is_alive(): return
		var key := status.get_item_text(status.selected).to_lower().replace(" ", "_")
		if amount.value == 0: card.statuses.erase(key)
		else: card.statuses[key] = int(amount.value)
		card._refresh_face()
		game.log_event("Debug status: %s · %s %d" % [card.card_data.name, key, int(amount.value)])
		persistence.checkpoint()
	, status_row).disabled = targets.is_empty()
	content.add_child(label("Status amount 0 clears it. Apply values saves the resource fields above.", 14, UI.MUTED))
	button("Cancel", close_modal, content)

func confirm_title() -> void:
	reset_panel("RETURN TO STARTING SCREEN?", "Your unfinished run is saved. Continue it from the starting screen, or abandon it there.", "confirm")
	confirmation_cancel = close_modal
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
	fit_card_grid(grid, scroll)
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
	grid.columns = 1
	scroll.add_child(grid)
	fit_card_grid(grid, scroll)
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
	var row := HBoxContainer.new()
	content.add_child(row)
	for buff in buff_choices:
		choice_tile(buff.name, buff.description, select_buff.bind(buff.id), row)
	content.add_child(label("YOUR BUFFS: " + buff_summary(game.player_buffs) + "\nJANITOR BUFFS: " + buff_summary(game.enemy_buffs), 16, TEAL, true))
	var box := centered_content()
	box.custom_minimum_size.x = 1060

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
	var row := HBoxContainer.new()
	content.add_child(row)
	for buff in buff_choices: choice_tile(buff.name, buff.description, select_floor_buff.bind(buff.id), row)
	button("Return to starting screen", return_title, content)
	var box := centered_content()
	box.custom_minimum_size.x = 1060

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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_inspect_hold()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence != null: quit_game()
