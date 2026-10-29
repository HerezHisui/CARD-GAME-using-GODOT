extends CanvasLayer
## Owns the persistent run. Battle copies never mutate the collection.
const UI = preload("res://scripts/ui_theme.gd")
const RouteCanvas = preload("res://scripts/route_canvas.gd")
const CardFace = preload("res://scripts/card_3d.gd")
const Rules = preload("res://scripts/battle_rules.gd")
const CardRules = preload("res://scripts/run_card_rules.gd")
const Routes = preload("res://scripts/run_routes.gd")
const RunDebug = preload("res://scripts/run_debug.gd")
const Shop = preload("res://scripts/run_shop.gd")
## Header, gauges, modal frame, idle hint, boss intent and board prompt, placed in the editor.
const ShellScene = preload("res://scenes/ui/ui_shell.tscn")
## Screen layouts that go inside the modal. Edit them in the editor.
const TitleScene = preload("res://scenes/ui/ui_title.tscn")
const MenuScene = preload("res://scenes/ui/ui_menu.tscn")
const DebugPasswordScene = preload("res://scenes/ui/ui_debug_password.tscn")
const DebugScene = preload("res://scenes/ui/ui_debug.tscn")
const MapScene = preload("res://scenes/ui/ui_map.tscn")
const SortRowScene = preload("res://scenes/ui/ui_sort_row.tscn")
const DeckScene = preload("res://scenes/ui/ui_deck.tscn")
const GraveyardScene = preload("res://scenes/ui/ui_graveyard.tscn")
const RestScene = preload("res://scenes/ui/ui_rest.tscn")
const ResultScene = preload("res://scenes/ui/ui_result.tscn")
const VictoryScene = preload("res://scenes/ui/ui_victory.tscn")
const RewardsScene = preload("res://scenes/ui/ui_rewards.tscn")
const ContingencyRewardScene = preload("res://scenes/ui/ui_contingency_reward.tscn")
const UpgradeScene = preload("res://scenes/ui/ui_upgrade.tscn")
const UpgradePreviewScene = preload("res://scenes/ui/ui_upgrade_preview.tscn")
const EventScene = preload("res://scenes/ui/ui_event.tscn")
const CharactersScene = preload("res://scenes/ui/ui_characters.tscn")
const CharacterPreviewScene = preload("res://scenes/ui/ui_character_preview.tscn")
const BattleLogScene = preload("res://scenes/ui/ui_battle_log.tscn")
const PlansScene = preload("res://scenes/ui/ui_plans.tscn")
const IntelScene = preload("res://scenes/ui/ui_intel.tscn")
const ConfirmScene = preload("res://scenes/ui/ui_confirm.tscn")
const ChooseCardsScene = preload("res://scenes/ui/ui_choose_cards.tscn")
const ChooseSlotScene = preload("res://scenes/ui/ui_choose_slot.tscn")
const BuffChoicesScene = preload("res://scenes/ui/ui_buff_choices.tscn")
const FloorBuffsScene = preload("res://scenes/ui/ui_floor_buffs.tscn")
## Pieces that many screens reuse.
const ChoiceTileScene = preload("res://scenes/ui/ui_choice_tile.tscn")
const CardTileScene = preload("res://scenes/ui/ui_card_tile.tscn")
const DossierScene = preload("res://scenes/ui/ui_dossier.tscn")
const CatalogInspectionScene = preload("res://scenes/ui/ui_catalog_inspection.tscn")
const InspectScene = preload("res://scenes/ui/ui_inspect.tscn")
static var start_after_reload := false
static var last_character := 0
const DECISIONS := ["coin", "reward", "shop", "event", "upgrade", "upgrade_preview", "result", "choice", "buff", "floor_buff", "intel", "title", "title_help", "characters", "character_preview", "victory", "inspect", "plans", "remove", "remove_confirm", "contingency_reward"]
const MAP_ROWS = Routes.MAP_ROWS
const MAX_UPGRADES := 2
const CHARACTERS := [
	{"name":"Steve · Student", "available":true, "description":"Balanced training. Units start with +1 health.", "buff":"cadet", "deck":[]},
	{"name":"Evacuation Club · Leader", "available":false, "description":"Evac formations, movement and draw. Matching neighbors gain +1 extra damage.", "buff":"marshal", "deck":["quick_dash", "quick_dash", "fire_drill", "fire_drill", "lane_marshal", "lane_marshal", "runner", "runner", "evacuation", "tutor", "shelter_brace", "rally"]},
	{"name":"Science Club · Leader", "available":false, "description":"Burn and Poison combinations. Apply +2 Burn and +1 Poison; units lose 1 health.", "buff":"chemist", "deck":["fire_truck", "fire_truck", "steam_team", "steam_team", "hazmat_team", "hazmat_team", "debris_clearance", "debris_clearance", "heat_seeker", "toxin_hunter", "cleanse", "tutor"]},
	{"name":"Safety Club · Leader", "available":false, "description":"Brace formations and Strength. Surviving blockers retaliate for 1 fixed damage.", "buff":"warden", "deck":["shelter_brace", "shelter_brace", "shard_barrier", "shard_barrier", "captain", "captain", "drill_leader", "momentum_team", "fire_truck", "field_medic", "rally", "cleanse"]}
]
var selected_character := 0
const SORT_KEYS = CardRules.SORT_KEYS
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
## True while a "choice" screen shows cards (choose_card, choose_enemy_hand), false for the lane picker.
var card_picker := false
const CARD_PICKER_WIDTH := 1000.0
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
var dashboard: PanelContainer
var remove_origin := ""
var remove_index := -1
var board_prompt: PanelContainer
var board_prompt_label: Label
var unlock_after := "cards"
var event_key := ""
var event_type := "locked"
var event_cards: Array[Dictionary] = []
var event_resolved := false
const EVENT_TYPES = Routes.EVENT_TYPES
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
	catalog.append({"id":"supply_cache", "name":"Supply Cache", "type":"response", "element":"clearance",
		"cost":2, "effect":"draw", "utility":true})
	catalog.append({"id":"emergency_exit", "name":"Emergency Exit", "type":"response", "element":"evac",
		"cost":1, "effect":"move", "utility":true})
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
	# The title, art and effects live in ui_title.tscn and title_screen.gd.
	reset_panel("", "", "title")
	# Here we only pick buttons and hook them up. The menu items are plain text, so they skip
	# hook_button's plate fill; title_screen.gd gives them their hover look.
	var title_screen: Control = TitleScene.instantiate()
	content.add_child(title_screen)
	var has_save: bool = persistence.has_run()
	if has_save:
		var saved: Dictionary = persistence.read_save()
		title_screen.get_node("%SaveLabel").text = "UNFINISHED RUN · FLOOR %d" % int(saved.director.floor_number)
		var continue_button: Button = title_screen.get_node("%ContinueButton")
		continue_button.pressed.connect(continue_saved_run)
		continue_button.grab_focus()
		title_screen.get_node("%AbandonButton").pressed.connect(confirm_abandon)
		title_screen.get_node("%StartButton").free()
	else:
		for unused in ["%SaveLabel", "%ContinueButton", "%AbandonButton"]: title_screen.get_node(unused).free()
		var start_button: Button = title_screen.get_node("%StartButton")
		start_button.pressed.connect(show_characters)
		start_button.grab_focus()
	title_screen.get_node("%QuitButton").pressed.connect(quit_game)

func continue_saved_run() -> void:
	if not persistence.resume(): show_title()

func confirm_abandon() -> void:
	reset_panel("ABANDON THIS RUN?", "Your deck, route and battle progress will be cleared.", "confirm")
	confirmation_cancel = show_title
	confirm_buttons("Abandon run", abandon_run, "Keep my run", show_title)

func abandon_run() -> void:
	run_active = false
	persistence.discard()
	game.clear_battle()
	collection.clear()
	show_title()

func show_characters() -> void:
	reset_panel("CHOOSE YOUR CHARACTER", "", "characters")
	# The layout lives in ui_characters.tscn; the character tiles are made here.
	var box := centered_screen(CharactersScene)
	var grid: Control = box.get_node("Grid")
	for i in CHARACTERS.size():
		var character: Dictionary = CHARACTERS[i]
		var pick := choice_tile(character.name, "IDENTITY %02d / %s\n\n%s" % [i + 1, "ACTIVE" if character.available else "AVAILABLE SOON", character.description], show_character_preview.bind(i), grid)
		pick.disabled = not character.available
		UI.decorate(pick.get_parent().get_parent(), not character.available)
	hook_button(box.get_node("BackButton"), show_title)

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
	# The layout lives in ui_character_preview.tscn; the card tiles are made here.
	unpack_screen(CharacterPreviewScene)
	var scroll: ScrollContainer = content.get_node("Cards")
	var grid: GridContainer = scroll.get_node("Grid")
	fit_card_grid(grid, scroll)
	for card in character_deck(index): _card_tile(card, grid)
	var begin: Button = content.get_node("BeginButton")
	begin.text = "Begin run" if CHARACTERS[index].available else "Available soon"
	hook_button(begin, start_character.bind(index)).disabled = not CHARACTERS[index].available
	hook_button(content.get_node("BackButton"), show_characters)

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

## Hooks up a button that comes from a screen scene: its click action and hover feedback.
func hook_button(b: Button, action: Callable) -> Button:
	if action.is_valid(): b.pressed.connect(action)
	game.presentation.button_feedback(b)
	return b

## Moves the nodes of a screen scene straight into content, so content keeps the same children as before.
## Find them afterwards with content.get_node("Name").
func unpack_screen(scene: PackedScene) -> void:
	var layout := scene.instantiate()
	# The nodes leave the scene, so they should not keep it as their owner.
	for node in layout.find_children("*", "", true, false): node.owner = null
	for child in layout.get_children():
		layout.remove_child(child)
		content.add_child(child)
	layout.free()

func choice_tile(title: String, description: String, action: Callable, parent: Node) -> Button:
	# The tile layout lives in ui_choice_tile.tscn.
	var panel: Control = ChoiceTileScene.instantiate()
	parent.add_child(panel)
	var pick: Button = panel.get_node("Box/PickButton")
	pick.text = title
	if compact_layout:
		pick.clip_text = true
		pick.tooltip_text = title
	hook_button(pick, action)
	panel.get_node("Box/Details").text = description
	return pick

func _build_ui() -> void:
	# Positions come from ui_shell.tscn; move things there in the editor.
	root = ShellScene.instantiate()
	add_child(root)
	UI.apply_hud(game.get_node("HUD/Root"))
	root.theme = UI.get_theme()
	# The top bar stays root child 0; other code finds it there.
	var header: Control = root.get_node("Header")
	map_button = header.get_node("%MapButton")
	menu_button = header.get_node("%MenuButton")
	var deck_button: Button = header.get_node("%DeckButton")
	deck_button.pressed.connect(show_deck)
	map_button.pressed.connect(toggle_map)
	menu_button.pressed.connect(show_menu)
	for header_button in [deck_button, map_button, menu_button]: game.presentation.button_feedback(header_button)
	# The dashboard, Plans and Graveyard buttons live in hud.tscn; the dashboard is HUD/Root child 0.
	var scene_hud := game.get_node("HUD/Root")
	dashboard = scene_hud.get_node("Dashboard")
	UI.decorate(dashboard)
	prep = _make_gauge("EnergyGauge", "PREPAREDNESS ENERGY", UI.RESPONSE, "EnergyBar")
	threat = _make_gauge("TensionGauge", "TENSION", UI.DANGER, "TensionBar")
	var modal_frame: Control = root.get_node("ModalFrame")
	modal_dimmer = modal_frame.get_node("%ModalDimmer")
	modal = modal_frame.get_node("%Modal")
	modal_scroll = modal_frame.get_node("%ModalScroll")
	content = modal_frame.get_node("%Content")
	UI.decorate(modal)
	# Keep the trim as the modal's first child, as before the scene existed.
	modal.move_child(modal.get_node("IndustrialTrim"), 0)
	modal.gui_input.connect(_modal_input)
	get_viewport().size_changed.connect(func():
		if modal.visible: _panel_layout(screen)
	)
	# Same font, size and color that label() gives.
	idle_hint = root.get_node("IdleHint")
	if compact_layout: idle_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	idle_hint.add_theme_font_override("font", UI.font(false))
	idle_hint.add_theme_font_size_override("font_size", 20)
	idle_hint.add_theme_color_override("font_color", UI.RESPONSE)
	var intent_panel: Control = root.get_node("BossIntent")
	boss_intent = intent_panel.get_node("%IntentLabel")
	plans_button = scene_hud.get_node("PlansBox/PlansButton")
	plans_button.pressed.connect(show_plans)
	graveyard_button = scene_hud.get_node("GraveyardButton")
	graveyard_button.pressed.connect(show_graveyard)
	for hud_button in [plans_button, graveyard_button]: game.presentation.button_feedback(hud_button)
	# Energy pips are drawn here; the "x / y" text stays in the gauge.
	var pips: Control = scene_hud.get_node("EnergyPips")
	pips.draw.connect(_draw_energy_pips.bind(pips))
	board_prompt = root.get_node("BoardPrompt")
	board_prompt_label = board_prompt.get_node("%PromptLabel")
	var cancel_button: Button = board_prompt.get_node("%CancelButton")
	cancel_button.pressed.connect(func(): game.board_input.cancel())
	game.presentation.button_feedback(cancel_button)

## A gauge from ui_gauge.tscn on root; returns its bar. Gauges have a title and a bar only.
func _make_gauge(box_name: String, title: String, color: Color, variation: String) -> ProgressBar:
	var box: Control = root.get_node(box_name)
	var heading: Label = box.get_node("Title")
	heading.text = title
	heading.add_theme_color_override("font_color", color)
	var bar: ProgressBar = box.get_node("%Bar")
	bar.theme_type_variation = variation
	return bar

## One square pip per energy point. Full = crimson with a gold rim, spent = dark and empty.
func _draw_energy_pips(pips: Control) -> void:
	var full := StyleBoxFlat.new()
	full.bg_color = Color("b3261e")
	full.border_color = Color("e0a93b")
	full.set_border_width_all(2)
	var spent := StyleBoxFlat.new()
	spent.bg_color = Color("1a1415")
	spent.border_color = Color("3a3032")
	spent.set_border_width_all(2)
	for i in game.energy_cap:
		var box := full if i < game.preparedness else spent
		# 5 pips per row; extra rows stack upward so the first row stays put.
		@warning_ignore("integer_division")
		var row: int = i / 5
		pips.draw_style_box(box, Rect2((i % 5) * 34, 2 - row * 30, 26, 26))

func _process(_delta: float) -> void:
	if inspect_hold_pending and not game.board_input.action.is_empty(): cancel_inspect_hold()
	if battle_active: game.plans.preview_attack()
	modal_dimmer.visible = modal.visible and battle_active and screen not in ["map", "inspect", "reward"]
	game.visible = battle_active or screen == "reward"
	board_prompt.visible = battle_active and not modal.visible and not game.board_input.action.is_empty()
	if board_prompt.visible: board_prompt_label.text = str(game.board_input.action.get("title", "Choose a board target"))
	game.opponent_hand.visible = battle_active and not modal.visible
	game.get_node("HUD/Root/EndTurnButton").disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or not game.board_input.action.is_empty() or _dragging()
	plans_button.visible = battle_active and not modal.visible
	plans_button.disabled = game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] or _dragging() or not game.board_input.action.is_empty()
	plans_button.text = "%d/2" % game.plans.tokens
	dashboard.visible = battle_active and not modal.visible
	graveyard_button.visible = battle_active and not modal.visible and not game.presentation.blocking
	graveyard_button.disabled = _dragging() or not game.board_input.action.is_empty()
	boss_intent.visible = is_instance_valid(game.final_boss) and battle_active and not modal.visible and game.board_input.action.is_empty()
	boss_intent.get_parent().visible = boss_intent.visible
	if boss_intent.visible: boss_intent.text = game.final_boss.intent()
	prep.max_value = game.energy_cap
	prep.value = game.preparedness
	threat.max_value = game.tension_cap
	threat.value = game.tension
	prep.get_parent().get_node("Title").text = "%d / %d" % [game.preparedness, game.energy_cap]
	threat.get_parent().get_node("Title").text = "TENSION  %d / %d" % [game.tension, game.tension_cap]
	game.get_node("HUD/Root").visible = battle_active and not modal.visible
	game.get_node("HUD/Root/DeckDrawButton/DeckCountLabel").text = str(game.deck.size())
	game.get_node("HUD/Root/EnergyPips").queue_redraw()
	game.get_node("HUD/TopBar/SuppliesLabel").text = "Supplies %d" % coins
	graveyard_button.text = str(game.player_graveyard.size())
	root.get_child(0).visible = screen not in ["title", "title_help", "characters", "character_preview"]
	# One shared top bar (HP, Supplies) for battle and the map, event, shop and rest screens.
	var top_bar: Control = game.get_node("HUD/TopBar")
	# In battle the bar stays up even while a popup is open.
	if battle_active: top_bar.visible = true
	else: top_bar.visible = run_active and root.get_child(0).visible and screen != "reward"
	# Outside battle nothing else updates the HP bar, so keep it current here.
	if top_bar.visible and not battle_active:
		game._set_health(game._player_hp_ui, game.player_hp, game.hero_max_hp(), false)
	map_button.disabled = saved_content != null or screen in DECISIONS or not game.board_input.action.is_empty()
	menu_button.disabled = map_button.disabled
	idle_hint.visible = false
	prep.get_parent().visible = battle_active and not modal.visible
	threat.get_parent().visible = battle_active and not modal.visible

func status_text() -> String:
	var counts := {"evac":0, "douse":0, "clearance":0, "brace":0}
	var utilities := 0
	for card in collection:
		var element := str(card.get("element", ""))
		if counts.has(element): counts[element] += 1
		if card.get("utility", false): utilities += 1
	return "HP %d/%d · Supplies %d · Deck %d\nEvac %d · Douse %d · Clear %d · Brace %d · Utility %d" % [
		game.player_hp, game.hero_max_hp(), coins, collection.size(),
		counts.evac, counts.douse, counts.clearance, counts.brace, utilities]

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
			var on_dossier: bool = is_instance_valid(inspection_dossier) \
				and inspection_dossier.get_parent().get_global_rect().has_point(event.position)
			if not on_dossier:
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
		# Card pickers are wide so 3-4 cards fit side by side; the lane picker stays narrow.
		var width := 560.0 if kind == "debug" else (CARD_PICKER_WIDTH if kind == "choice" and card_picker else 420.0)
		var panel_size := Vector2(minf(width, viewport_size.x - 32), minf(height, viewport_size.y - 48))
		modal.offset_left = (viewport_size.x - panel_size.x) / 2
		modal.offset_right = -modal.offset_left
		modal.offset_top = (viewport_size.y - panel_size.y) / 2
		modal.offset_bottom = -modal.offset_top
		# In battle the top bar stays visible, so the popup starts under it.
		if battle_active: modal.offset_top = maxf(modal.offset_top, 66)
		modal.add_theme_stylebox_override("panel", style(UI.PANEL, UI.GOLD))
		game.visible = battle_active
		return
	if content.get_parent() != modal: content.reparent(modal)
	modal_scroll.hide()
	var title_screen := kind in ["title", "title_help", "characters", "character_preview"]
	var full_screen := title_screen or not battle_active or kind in ["map", "reward", "inspect"]
	game.visible = battle_active or kind == "reward"
	modal.offset_left = 0 if full_screen else 45
	modal.offset_right = 0 if full_screen else -45
	# Battle popups start just under the header buttons, which end at y 58.
	# Full-screen panels are their own backdrop, so they start at the top bar's bottom edge (y 52).
	modal.offset_top = (0 if title_screen or not battle_active or kind == "reward" else 52) if full_screen else 66
	# Run screens outside battle start under the shared top bar (header buttons end at y 58).
	# The top bar ends at y 52, so start there with no gap.
	if run_active and not battle_active and not title_screen and kind != "reward": modal.offset_top = 52
	if kind == "shop": modal.offset_top = 52
	modal.offset_bottom = 0 if full_screen else -28
	var panel_style := style(Color(UI.BACKGROUND, 0.90) if kind in ["reward", "inspect"] else (UI.BACKGROUND if full_screen else UI.PANEL), UI.GOLD)
	if full_screen:
		panel_style.set_border_width_all(0)
		panel_style.set_corner_radius_all(0)
		panel_style.content_margin_left = 55
		panel_style.content_margin_right = 55
		panel_style.content_margin_top = 45 if title_screen else 20
		panel_style.content_margin_bottom = 35 if title_screen else 20
		# The title art runs edge to edge.
		if kind == "title": panel_style.set_content_margin_all(0)
	modal.add_theme_stylebox_override("panel", panel_style)

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
	if not title.is_empty(): content.add_child(label(title, 24 if compact_layout else 30, UI.GOLD, compact_layout))
	if not subtitle.is_empty(): content.add_child(label(subtitle, 16, UI.MUTED, true))
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
	game.get_node("HUD/TopBar/PlayerHealth/Caption").text = CHARACTERS[selected_character].name
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
	cleared.clear()
	current = -1
	Routes.generate_map(rooms, rng)

func reachable(id: int) -> bool:
	return Routes.reachable(id, rooms, current, cleared, battle_active)

func show_map() -> void:
	if _dragging(): return
	if saved_content: return
	if screen in DECISIONS: return
	reset_panel("THE SCHOOL MAP", "", "map")
	# The layout lives in ui_map.tscn; the room buttons are made here because the route changes each run.
	unpack_screen(MapScene)
	var map_scroll: ScrollContainer = content.get_node("RouteRow/MapScroll")
	var canvas: RouteCanvas = map_scroll.get_node("Canvas")
	canvas.rooms = rooms
	canvas.current = current
	canvas.cleared = cleared
	content.get_node("RouteRow/Dossier/DossierText/FloorLabel").text = "FLOOR / %02d" % floor_number
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
		if not b.disabled: b.add_theme_stylebox_override("normal", style(UI.RAISED, UI.GOLD))
		if id in cleared:
			b.add_theme_stylebox_override("disabled", style(UI.PANEL, UI.RESPONSE))
			b.add_theme_color_override("font_disabled_color", UI.RESPONSE)
		b.tooltip_text = "Room %d · %s" % [room.row + 1, room.kind]
		if room.kind == "boss" and floor_number == 3:
			b.text = "FINAL BOSS"
			b.tooltip_text = "Final boss: three telegraphed phases. Prepare healing, barriers and AoE."
		b.position = canvas.point(room) - b.size / 2
	var footer: Control = content.get_node("Footer")
	if battle_active:
		hook_button(footer.get_node("ReturnButton"), close_modal)
		footer.get_node("MenuButton").free()
	else:
		footer.get_node("ReturnButton").free()
		hook_button(footer.get_node("MenuButton"), show_menu)

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
	reset_panel("THE INFIRMARY", "", "event")
	# The layout lives in ui_rest.tscn.
	unpack_screen(RestScene)
	var rest_button: Button = content.get_node("RestButton")
	rest_button.text = "Rest · +%d HP · free" % healing_gain(7)
	hook_button(rest_button, rest).disabled = healing_gain(7) == 0
	hook_button(content.get_node("TrainButton"), show_upgrade)
	hook_button(content.get_node("DestroyButton"), show_remove_cards.bind("rest")).disabled = collection.size() <= 5
	hook_button(content.get_node("LeaveButton"), finish_room)

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
		reset_panel("TRAPPED AFTER MIDNIGHT", "", "result")
		unpack_screen(ResultScene)
		hook_button(content.get_node("ReturnButton"), return_title)
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
	reset_panel("NEW CONTINGENCY", "Unlock one tactic for this run.", "contingency_reward")
	# The layout lives in ui_contingency_reward.tscn; the tactic tiles are made here.
	var box := centered_screen(ContingencyRewardScene)
	var row: Control = box.get_node("Row")
	for tactic in buff_choices:
		choice_tile(tactic.name + " · %d Plan%s" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""], tactic.description, select_contingency_reward.bind(tactic.id), row)

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
	reset_panel("DAWN AT LAST", "", "victory")
	# The layout lives in ui_victory.tscn.
	unpack_screen(VictoryScene)
	content.get_node("Summary").text = "RUN COMPLETE · %d cards · %d supplies · %d health remaining" % [
		collection.size(), coins, game.player_hp]
	hook_button(content.get_node("ReturnButton"), return_title)
	hook_button(content.get_node("ExploreButton"), show_floor_buffs)

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
	reset_panel("DISASTER CONTAINED", "Click a card twice to keep it.", "reward")
	# The layout lives in ui_rewards.tscn; the card faces are made here.
	var box := centered_screen(RewardsScene)
	var row: Control = box.get_node("Row")
	var skip: Button = box.get_node("SkipButton")
	if reward_stock.is_empty(): reward_stock = offers(3)
	if selected >= 0 and selected < reward_stock.size():
		skip.free()
		inspected_face = reward_face(selected, row, 330)
		add_dossier(row, reward_stock[selected], "")
	else:
		reward_selection = -1
		for i in reward_stock.size():
			var column := VBoxContainer.new()
			row.add_child(column)
			var face := reward_face(i, column, 245)
			game.presentation.card_feedback(face)
			game.presentation.reveal(column)
		hook_button(skip, finish_room)

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

## Centers a screen: the screen scene needs a Center/Box node.
## The title and subtitle move to the top of that box.
func centered_screen(scene: PackedScene) -> Control:
	var headings := content.get_children().duplicate()
	unpack_screen(scene)
	var box: Control = content.get_node("Center/Box")
	for index in headings.size():
		var heading: Node = headings[index]
		heading.reparent(box)
		box.move_child(heading, index)
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
	# The tile layout lives in ui_card_tile.tscn; the card face is made here.
	var panel: Control = CardTileScene.instantiate()
	panel.add_theme_stylebox_override("panel", style(UI.PANEL, UI.BRONZE))
	parent.add_child(panel)
	var box: Control = panel.get_node("Box")
	var center: Control = box.get_node("Center")
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
	var action_button: Button = box.get_node("ActionButton")
	if not action.is_valid():
		action_button.free()
		return
	action_button.text = action_text
	if compact_layout:
		action_button.clip_text = true
		action_button.tooltip_text = action_text
	hook_button(action_button, action)

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
	# The overlay layout lives in ui_catalog_inspection.tscn.
	var overlay: Control = CatalogInspectionScene.instantiate()
	# Start at the top bar's bottom edge so no room shows above the overlay.
	if run_active: overlay.offset_top = 52
	root.add_child(overlay)
	var row: Control = overlay.get_node("Center/Row")
	add_dossier(row, card, "")
	inspected_face = card_image(texture, row, 310)

func add_dossier(parent: Node, card: Dictionary, hint: String, live_card: Node = null) -> RichTextLabel:
	# The dossier layout lives in ui_dossier.tscn; the text is written here.
	var panel: Control = DossierScene.instantiate()
	parent.add_child(panel)
	UI.decorate(panel)
	var body: Control = panel.get_node("Body")
	inspection_dossier = body
	body.get_node("InspectTitle").text = str(card.name).to_upper()
	# One box: the card face already shows attack, health and energy cost.
	var details: RichTextLabel = body.get_node("DossierText")
	var disaster: bool = card.get("type", "response") == "disaster"
	var sacrifice: bool = disaster and not card.get("utility", false) and int(card.get("cost", 0)) > 0
	if card.has("boss_role"): details.text += "Encounter hazard: created by a boss pattern. No summon cost.\n\n"
	elif sacrifice: details.text += "SAC: %d allied units to evolve.\n\n" % int(card.cost)
	elif disaster: details.text += "Cost: %d Tension.\n\n" % int(card.get("tension_cost", 1))
	var effects: Dictionary = live_card.statuses if is_instance_valid(live_card) else card.get("statuses", {})
	var status_rules := {
		"strength":"Adds attack.", "burn":"Deals damage each round, then halves its stacks.",
		"poison":"Deals damage each round, then loses one stack.",
		"bleed":"Deals damage after attacking, then loses one stack.",
		"barrier":"Absorbs attack damage, up to three stacks.",
		"healing_reduced":"Halves healing, rounded down with a minimum of one. Loses one stack each round."
	}
	var tokens: PackedStringArray = []
	for status in effects:
		if int(effects[status]) > 0:
			tokens.append("%s %d: %s" % [str(status).capitalize(), int(effects[status]), status_rules.get(status, "")])
	var status_text := ""
	if not tokens.is_empty(): status_text = "[b]CURRENT STATUSES[/b]\n" + "\n".join(tokens) + "\n"
	var combat: PackedStringArray = []
	if is_instance_valid(live_card):
		if live_card.planned_guard > 0: combat.append("Plan protection: %d" % live_card.planned_guard)
		if live_card.plan_attack_bonus > 0: combat.append("Plan attack: +%d" % live_card.plan_attack_bonus)
		if live_card.plan_ignore_taunt: combat.append("Ignore Taunt")
		if game.buff_value(live_card.card_data.type == "response", "kill_or_die") > 0: combat.append("Blood Pact: defeat a card this turn or die")
	if not combat.is_empty(): status_text += "\n[b]THIS COMBAT[/b]\n" + "\n".join(combat) + "\n"
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
	for modifier in active_modifiers:
		var description := Rules.modifier_text(card, str(modifier))
		if description not in rules: rules.append(description)
	var effect_text := "No card effects.\n" if rules.is_empty() else "[b]CARD EFFECTS[/b]\n" + "\n".join(rules) + "\n"
	# Effects, statuses and the hint all go in the same box; there are no tabs.
	details.text += effect_text
	if not status_text.is_empty(): details.text += "\n" + status_text
	if not hint.is_empty(): details.text += "\n" + hint
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
	reset_panel("", "", "deck")
	# The layout lives in ui_deck.tscn; the card tiles are made in deck_cards().
	unpack_screen(DeckScene)
	var deck_button: Button = content.get_node("Tabs/DeckButton")
	deck_button.text = "Cards (%d)" % collection.size()
	hook_button(deck_button, deck_cards.bind(collection))
	hook_button(content.get_node("Tabs/CloseButton"), close_modal)
	setup_sort_controls(content.get_node("SortRow"), false)
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
	if not battle_active or modal.visible or (_dragging() and not from_hand) or game.presentation.blocking: return
	if from_hand and game.in_board_view: return
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
	reset_panel("", "", "inspect")
	# The layout lives in ui_inspect.tscn.
	var box := centered_screen(InspectScene)
	var row: Control = box.get_node("Row")
	card._refresh_face()
	add_dossier(row, live_definition(card), "", card)
	inspected_face = card_image(card._vp.get_texture(), row, 330)

## The combat log has no HUD button; L opens and closes it.
func show_battle_log() -> void:
	if _dragging() or screen in ["title", "title_help", "characters", "character_preview"]: return
	if screen == "log":
		close_modal()
		return
	preserve_pending_decision()
	reset_panel("BATTLE LOG", "", "log")
	# The layout lives in ui_battle_log.tscn.
	unpack_screen(BattleLogScene)
	var log_view: RichTextLabel = content.get_node("Log")
	log_view.text = "\n".join(game.battle_log) if not game.battle_log.is_empty() else "No battle events yet."
	hook_button(content.get_node("CloseButton"), close_modal)

func show_plans() -> void:
	if not battle_active or _dragging() or not game.board_input.action.is_empty(): return
	if screen == "plans":
		close_modal()
		return
	if screen in DECISIONS or saved_content != null: return
	reset_panel("PREPAREDNESS · CONTINGENCIES", "Save 2 unused energy at End Turn for 1 Plan. Unlock more tactics from elite and boss wins.", "plans")
	# The layout lives in ui_plans.tscn; the tactic tiles are made here.
	unpack_screen(PlansScene)
	content.get_node("Status").text = "PLANS %d / 2 · %d TACTICS UNLOCKED" % [game.plans.tokens, game.plans.unlocked.size()]
	var list: Control = content.get_node("Scroll/List")
	for id in game.plans.unlocked:
		var tactic: Dictionary = game.plans.definition(id)
		var pick := choice_tile(tactic.name + " · %d Plan%s" % [tactic.cost, "s" if int(tactic.cost) > 1 else ""], tactic.description, begin_tactic.bind(id), list)
		pick.disabled = not tactic_available(id)
		pick.get_parent().get_parent().custom_minimum_size.y = 125
	var armed: Label = content.get_node("Armed")
	if game.plans.armed.is_empty(): armed.free()
	else: armed.text = "ARMED: " + str(game.plans.definition(game.plans.armed.kind).name)
	hook_button(content.get_node("ReturnButton"), close_modal)

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
		game.board_input.pick("Click one ally. It and the nearest ally on each side gain +1 attack this combat.",
			allies, arm_target_tactic.bind("coordinate"), Callable(), "coordinate")
	elif id == "extract":
		var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
		game.board_input.pick("Click the ally to protect with Emergency Extraction.", allies, select_extraction_ally, Callable())
	elif id in ["supply", "shelter"]: game.plans.arm(id, [])
	else:
		var allies: Array = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null)
		game.board_input.pick("Click a deployed ally for " + str(game.plans.definition(id).name) + ".", allies, arm_target_tactic.bind(id), Callable())

func arm_target_tactic(card: Node, id: String) -> void: game.plans.arm(id, [card])
func select_brace() -> void: begin_tactic("brace")
func arm_brace(card: Node) -> void:
	game.board_input.clear()
	game.plans.arm("brace", [card])
func select_coordination() -> void: begin_tactic("coordinate")
func select_extraction_ally(card: Node) -> void:
	game.board_input.destination(card, arm_extraction.bind(card))

func arm_extraction(slot: Node3D, card: Node) -> void:
	game.plans.arm("extract", [card], slot)

func show_graveyard() -> void:
	if not battle_active or _dragging() or not game.board_input.action.is_empty() or screen in DECISIONS or saved_content != null: return
	if screen == "graveyard":
		close_modal()
		return
	refresh_graveyard()

func refresh_graveyard() -> void:
	reset_panel("Graveyard", "", "graveyard")
	# The layout lives in ui_graveyard.tscn; the card tiles are made here, like the Deck view.
	unpack_screen(GraveyardScene)
	var tabs: Control = content.get_node("Tabs")
	hook_button(tabs.get_node("CloseButton"), close_modal)
	var sort: OptionButton = tabs.get_node("Sort")
	for key in SORT_KEYS: sort.add_item("Recently added" if key == "acquired" else str(key).capitalize())
	sort.select(deck_sort)
	sort.item_selected.connect(func(index): deck_sort = index; refresh_graveyard())
	var order: Button = tabs.get_node("OrderButton")
	order.text = "Descending" if deck_descending else "Ascending"
	hook_button(order, func(): deck_descending = not deck_descending; refresh_graveyard())
	var list: Control = content.get_node("Scroll/List")
	var cards: Array = game.player_graveyard
	viewed_cards.assign(cards)
	if not cards.is_empty(): list.get_node("EmptyNote").free()
	var grid := GridContainer.new()
	list.add_child(grid)
	fit_card_grid(grid, content.get_node("Scroll"))
	for index in sorted_indices(cards, deck_sort, deck_descending):
		var entry: Dictionary = cards[index]
		_card_tile(entry, grid)
		# Small status caption under the card face.
		var reason := str(entry.get("graveyard_reason", "Destroyed"))
		var caption := label("%s · round %d" % [reason, int(entry.get("graveyard_round", 1))], 14, UI.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.get_child(grid.get_child_count() - 1).get_node("Box").add_child(caption)
	if cards.is_empty():
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL

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
	if not definition.get("utility", false):
		definition.attack = card.effective_attack()
		definition.preview_attack = card.effective_attack()
	definition.modifiers = card.modifiers.duplicate()
	if not definition.get("utility", false): definition.strength = int(card.statuses.get("strength", 0))
	definition.statuses = card.statuses.duplicate()
	return definition

func card_rules(card: Dictionary) -> String:
	var effect: String = str(card.get("effect", ""))
	if card.get("utility", false):
		return Rules.utility_text(card) + "\n" + Rules.special_text(card) + "\n" \
			+ "Choose an empty Response slot to cast. Cancel before choosing a target to keep the card and energy."
	var rules := "Adjacent matching types: +1 attack.\n" + Rules.special_text(card) + "\n"
	if effect == "draw": rules += "On play: draw %d.\n" % int(card.get("draw_count", 1))
	if effect == "move_ally": rules += "On play: optionally choose another ally, then an empty lane, and move it there. Skipping movement does not undo the summon.\n"
	if effect == "heal_all": rules += "On play: heal other deployed allies by 2.\n"
	if effect == "rally_all": rules += "On play: other deployed allies gain 1 Strength.\n"
	if effect == "grave_guard": rules += str(Rules.EFFECTS.grave_guard) + "\n"
	if int(card.get("leech", 0)) > 0: rules += "Heal %d after attacking.\n" % int(card.leech)
	var modifiers: Array = card.get("modifiers", []).duplicate()
	var primary := str(card.get("modifier", "")).to_lower()
	if not primary.is_empty() and primary not in modifiers: modifiers.append(primary)
	for modifier in modifiers: rules += Rules.modifier_text(card, str(modifier)) + "\n"
	if card.has("on_hit"):
		for status in card.on_hit: rules += "On hit: %s %d to a surviving blocker.\n" % [str(status).capitalize(), int(card.on_hit[status])]
	for element in game.TYPE_CHART.get(card.element, {}):
		var mult: float = float(game.TYPE_CHART[card.element][element])
		# Whole numbers read "2x", others "0.5x".
		var amount := str(int(mult)) if is_equal_approx(mult, roundf(mult)) else str(mult)
		rules += "Deals %sx damage to %s\n" % [amount, str(element).capitalize()]
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
	if cards.is_empty(): grid.add_child(label("No cards here yet.", 20, UI.RESPONSE))

func sorted_indices(cards: Array, key_index: int, descending: bool) -> Array:
	return CardRules.sorted_indices(cards, key_index, descending)

## Adds a sort row from ui_sort_row.tscn to the end of content.
func add_sort_controls(workshop: bool) -> void:
	var row: Control = SortRowScene.instantiate()
	content.add_child(row)
	setup_sort_controls(row, workshop)

## Fills a sort row: the picker items, the current sort and the order button.
func setup_sort_controls(row: Control, workshop: bool) -> void:
	var picker: OptionButton = row.get_node("Picker")
	for title in ["Name", "Type", "Cost", "Attack", "Health", "Modifier", "Recently added"]: picker.add_item(title)
	picker.select(upgrade_sort if workshop else deck_sort)
	picker.item_selected.connect(change_sort.bind(workshop))
	var descending := upgrade_descending if workshop else deck_descending
	var order: Button = row.get_node("OrderButton")
	order.text = "Descending ↓" if descending else "Ascending ↑"
	hook_button(order, reverse_sort.bind(workshop))

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
	reset_panel("THE WORKSHOP", "Each card can upgrade twice.", "upgrade")
	# The layout lives in ui_upgrade.tscn; the card tiles are made here.
	unpack_screen(UpgradeScene)
	setup_sort_controls(content.get_node("SortRow"), true)
	var scroll: ScrollContainer = content.get_node("Cards")
	var grid: GridContainer = scroll.get_node("Grid")
	fit_card_grid(grid, scroll)
	for i in sorted_indices(collection, upgrade_sort, upgrade_descending):
		var card := collection[i]
		_card_tile(card, grid, show_upgrade_preview.bind(i) if can_upgrade(card) else Callable(), "Preview upgrade")
		if not can_upgrade(card):
			grid.get_child(grid.get_child_count() - 1).tooltip_text = "This card has reached its two-upgrade limit."
			grid.get_child(grid.get_child_count() - 1).get_child(0).add_child(label("Fully upgraded", 14, UI.GOLD))
	hook_button(content.get_node("LeaveButton"), finish_room)

func upgrade(index: int) -> void:
	if index < 0 or index >= collection.size() or not can_upgrade(collection[index]): return
	collection[index] = upgraded_definition(collection[index])
	finish_room()

func upgrade_level(card: Dictionary) -> int:
	return CardRules.upgrade_level(card)

func can_upgrade(card: Dictionary) -> bool:
	return CardRules.can_upgrade(card, MAX_UPGRADES)

func upgraded_definition(card: Dictionary) -> Dictionary:
	var result: Dictionary = card.duplicate(true)
	if not can_upgrade(card): return result
	var tier := upgrade_level(card) + 1
	result.upgrades = tier
	if result.get("utility", false):
		if tier == 1 and int(result.cost) > 0: result.cost = int(result.cost) - 1
		elif result.get("effect", "") in ["move", "tutor", "scout", "recover"]:
			if tier == 2: result.refund_energy = int(result.get("refund_energy", 0)) + 1
		else: result.utility_power = int(result.get("utility_power", 0)) + 1
	else:
		match str(result.get("element", "")):
			"evac":
				if tier == 1:
					result.attack = int(result.attack) + 1
					if int(result.get("on_play_draw", 0)) > 0:
						result.on_play_draw = int(result.on_play_draw) + 1
				else:
					result.health = int(result.health) + 1
					result.cost = maxi(0, int(result.cost) - 1)
					if int(result.get("on_play_draw", 0)) == 0: result.on_play_draw = 1
			"douse":
				if tier == 1:
					result.attack = int(result.attack) + 1
				var has_burn: bool = int(result.get("on_hit", {}).get("burn", 0)) > 0
				if (tier == 1 and has_burn) or (tier == 2 and not has_burn):
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.burn = int(hits.get("burn", 0)) + 1
					result.on_hit = hits
				if tier == 2:
					result.health = int(result.health) + 1
					result.leech = int(result.get("leech", 0)) + 1
			"clearance":
				if tier == 1:
					result.attack = int(result.attack) + 1
				var has_poison: bool = int(result.get("on_hit", {}).get("poison", 0)) > 0
				if (tier == 1 and has_poison) or (tier == 2 and not has_poison):
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.poison = int(hits.get("poison", 0)) + 1
					result.on_hit = hits
				if tier == 2:
					result.health = int(result.health) + 1
					result.status_bonus = int(result.get("status_bonus", 0)) + 2
			"brace":
				if tier == 1:
					result.health = int(result.health) + 2
				var armored: bool = game.definition_has_modifier(result, "armored")
				if (tier == 1 and armored) or (tier == 2 and not armored):
					result.armor_value = int(result.get("armor_value", 1 if game.definition_has_modifier(result, "armored") else 0)) + 1
					var traits: Array = result.get("modifiers", []).duplicate()
					if result.get("modifier", "") != "armored" and "armored" not in traits: traits.append("armored")
					result.modifiers = traits
				if tier == 2:
					result.health = int(result.health) + 1
					result.thorns = int(result.get("thorns", 0)) + 1
			_:
				result.attack = int(result.attack) + 1
				result.health = int(result.health) + 1
	result.name = str(result.name) + "+"
	return result

func show_upgrade_preview(index: int) -> void:
	if not can_upgrade(collection[index]): return
	reset_panel("UPGRADE PREVIEW", "", "upgrade_preview")
	# The layout lives in ui_upgrade_preview.tscn; the two card tiles go on each side of the arrow.
	unpack_screen(UpgradePreviewScene)
	var row: Control = content.get_node("Row")
	_card_tile(collection[index], row)
	row.move_child(row.get_child(row.get_child_count() - 1), 0)
	_card_tile(upgraded_definition(collection[index]), row)
	hook_button(content.get_node("ConfirmButton"), upgrade.bind(index))
	hook_button(content.get_node("BackButton"), show_upgrade)

func show_shop() -> void: Shop.show_shop(self)

func shop_price(card: Dictionary) -> int: return Shop.shop_price(card)

func buy(card: Dictionary) -> void: Shop.buy(self, card)

func buy_heal() -> void: Shop.buy_heal(self)

func show_remove_cards(origin: String) -> void: Shop.show_remove_cards(self, origin)

func preview_remove(index: int) -> void: Shop.preview_remove(self, index)

func confirm_remove() -> void: Shop.confirm_remove(self)

func cancel_remove() -> void: Shop.cancel_remove(self)

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
	var group_name: String
	match event_type:
		"radio":
			reset_panel("THE EMERGENCY RADIO", "Kit: Hazard Forecast, Search and Rescue.", "event")
			group_name = "Radio"
		"rooftop":
			reset_panel("ROOFTOP DRILLS", "Energy loss lasts the rest of the run.", "event")
			group_name = "Rooftop"
		"science":
			reset_panel("THE SCIENCE LAB", "", "event")
			group_name = "Science"
		"infirmary":
			reset_panel("A VOLUNTEER'S OFFER", "Paperwork: spend 1 energy to discard it.", "event")
			group_name = "Infirmary"
		"lost_found":
			reset_panel("LOST AND FOUND", "", "event")
			group_name = "LostFound"
		_:
			reset_panel("A LOCKED CLASSROOM", "", "event")
			group_name = "Locked"
	# The layout lives in ui_event.tscn: one group of buttons per event. Only this event's group stays.
	var box := centered_screen(EventScene)
	for other in box.get_children():
		if other is VBoxContainer and other.name != group_name: other.free()
	var group: Control = box.get_node(group_name)
	match group_name:
		"Radio":
			hook_button(group.get_node("BuyButton"), resolve_event.bind("radio_buy")).disabled = coins < 20
		"Rooftop":
			hook_button(group.get_node("TrainButton"), resolve_event.bind("training"))
		"Science":
			var row: Control = group.get_node("Stock")
			for i in range(event_cards.size()): _card_tile(event_cards[i], row, resolve_event.bind("science_%d" % i) if game.player_hp > 3 else Callable(), "Take card · -3 HP")
		"Infirmary":
			var treatment: Button = group.get_node("TreatmentButton")
			treatment.text = "Full treatment · +%d HP · add Paperwork" % healing_gain(8)
			hook_button(treatment, resolve_event.bind("treatment")).disabled = game.player_hp >= game.hero_max_hp()
			var short_break: Button = group.get_node("RestButton")
			short_break.text = "Short break · +%d HP · free" % healing_gain(3)
			hook_button(short_break, resolve_event.bind("rest"))
		"LostFound":
			hook_button(group.get_node("TradeButton"), show_remove_cards.bind("event")).disabled = collection.size() <= 5
		"Locked":
			hook_button(group.get_node("RiskButton"), event_risk).disabled = game.player_hp <= 3
	if group.has_node("SafeButton"): hook_button(group.get_node("SafeButton"), resolve_event.bind("safe"))

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
	# Pressing Menu again closes it, like Resume.
	if screen == "menu":
		close_modal()
		return
	if saved_content: return
	if screen in DECISIONS: return
	reset_panel("MIDNIGHT DRRILLS", "", "menu")
	# The layout lives in ui_menu.tscn; here we only fill in text and hook up buttons.
	unpack_screen(MenuScene)
	content.get_node("RulesScroll/Rules/Adaptations").text = "Adaptations: " + buff_summary(game.player_buffs)
	content.get_node("RulesScroll/Rules/Augmentations").text = "Augmentations: " + buff_summary(game.player_run_buffs)
	hook_button(content.get_node("ResumeButton"), close_modal)
	if battle_active: hook_button(content.get_node("DebugButton"), show_debug)
	else: content.get_node("DebugButton").free()
	hook_button(content.get_node("TitleButton"), confirm_title)
	hook_button(content.get_node("QuitButton"), quit_game)

func quit_game() -> void:
	persistence.checkpoint()
	get_tree().paused = false
	get_tree().quit()

func debug_available() -> bool:
	return RunDebug.debug_available(game, battle_active)

func cancel_debug_password() -> void:
	if debug_from_menu: show_menu()
	else: close_modal()

func show_debug() -> void:
	if screen == "debug":
		close_modal()
		return
	if not debug_available() or (modal.visible and screen != "menu"): return
	debug_from_menu = screen == "menu"
	reset_panel("DEBUG ACCESS", "", "debug_password")
	# The layout lives in ui_debug_password.tscn.
	unpack_screen(DebugPasswordScene)
	var password: LineEdit = content.get_node("DebugPassword")
	var error: Label = content.get_node("PasswordError")
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
	hook_button(content.get_node("UnlockButton"), submit)
	hook_button(content.get_node("CancelButton"), cancel_debug_password)
	password.grab_focus()

func _open_debug(password: String) -> void:
	if password != "*****" or screen != "debug_password" or not debug_available(): return
	reset_panel("DEBUG VALUES", "", "debug")
	# The layout lives in ui_debug.tscn; each SpinBox there is named after its value.
	unpack_screen(DebugScene)
	var fields := {}
	for spec in [
		["player_hp", "Player HP", 1, game.hero_max_hp()], ["enemy_hp", "Enemy HP", 1, game.enemy_max_hp],
		["energy_cap", "Energy cap", 1, 30], ["preparedness", "Energy", 0, 30],
		["tension_cap", "Tension cap", 1, 30], ["tension", "Tension", 0, 30],
		["coins", "Supplies", 0, 9999], ["plans", "Plans", 0, 2],
	]:
		var field: SpinBox = content.get_node("Values/" + spec[0])
		field.min_value = spec[2]
		field.max_value = spec[3]
		field.value = coins if spec[0] == "coins" else (game.plans.tokens if spec[0] == "plans" else game.get(spec[0]))
		fields[spec[0]] = field
	hook_button(content.get_node("ApplyButton"), func():
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
	)
	_debug_card_controls()
	hook_button(content.get_node("CancelButton"), close_modal)

func _debug_card_controls() -> void:
	var status_row: Control = content.get_node("StatusRow")
	var targets := game.get_tree().get_nodes_in_group("cards").filter(func(card):
		return card.is_alive() and not card.preview_only and (card.in_hand or is_instance_valid(card.current_slot)))
	var target: OptionButton = status_row.get_node("DebugCard")
	for i in targets.size():
		var card: Node = targets[i]
		var location := "HAND" if card.in_hand else str(card.card_data.get("type", "")).to_upper()
		target.add_item("%d / %s / %s" % [i + 1, location, card.card_data.name])
	if targets.is_empty(): target.add_item("No cards")
	target.disabled = targets.is_empty()
	var fields := {}
	for spec in [["cost", "Cost"], ["attack", "ATK"], ["health", "HP"]]:
		var field: SpinBox = status_row.get_node("Stats/Debug" + str(spec[1]))
		fields[spec[0]] = field
		field.value_changed.connect(_debug_set_card_stat.bind(targets, target, spec[0]))
	target.item_selected.connect(func(_index): _debug_load_card_stats(targets, target, fields))
	_debug_load_card_stats(targets, target, fields)
	var status: OptionButton = status_row.get_node("Status")
	for key in ["strength", "bleed", "burn", "poison", "barrier", "healing_reduced"]: status.add_item(key)
	var amount: SpinBox = status_row.get_node("Amount")
	hook_button(status_row.get_node("SetStatusButton"), func():
		var card := _debug_selected_card(targets, target)
		if card == null: return
		var key := status.get_item_text(status.selected)
		if amount.value == 0: card.statuses.erase(key)
		else: card.statuses[key] = int(amount.value)
		card._refresh_face()
		game.log_event("Debug status: %s · %s %d" % [card.card_data.name, key, int(amount.value)])
		persistence.checkpoint()
	).disabled = targets.is_empty()

func _debug_selected_card(targets: Array, picker: OptionButton) -> Node:
	return RunDebug._debug_selected_card(targets, picker.selected)

func _debug_load_card_stats(targets: Array, picker: OptionButton, fields: Dictionary) -> void:
	var card := _debug_selected_card(targets, picker)
	for key in fields:
		var field: SpinBox = fields[key]
		var editable: bool = card != null and (key == "cost" or not card.card_data.get("utility", false))
		field.editable = editable
		field.set_value_no_signal(int(card.card_data.get(key, 0)) if editable else field.min_value)

func _debug_set_card_stat(value: float, targets: Array, picker: OptionButton, key: String) -> void:
	var card := _debug_selected_card(targets, picker)
	if RunDebug._debug_set_card_stat(value, card, key):
		persistence.checkpoint()

func confirm_title() -> void:
	reset_panel("RETURN TO STARTING SCREEN?", "Your run is saved.", "confirm")
	confirmation_cancel = close_modal
	confirm_buttons("Return to starting screen", return_title, "Keep playing", close_modal)

## The two buttons of a confirm dialog, from ui_confirm.tscn.
func confirm_buttons(yes_text: String, yes: Callable, no_text: String, no: Callable) -> void:
	unpack_screen(ConfirmScene)
	var yes_button: Button = content.get_node("ConfirmButton")
	var no_button: Button = content.get_node("CancelButton")
	yes_button.text = yes_text
	yes_button.tooltip_text = yes_text
	no_button.text = no_text
	no_button.tooltip_text = no_text
	# Same rule as button(): risky actions get the primary style.
	if yes_text.begins_with("Abandon"): yes_button.theme_type_variation = "PrimaryButton"
	hook_button(yes_button, yes)
	hook_button(no_button, no)

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

func choose_card(title: String, cards: Array, callback: Callable, cancel: Callable, subtitle: String = "") -> void:
	card_picker = true
	reset_panel(title, subtitle, "choice")
	action_cancel = cancel
	# The layout lives in ui_choose_cards.tscn: one row of cards that scrolls sideways.
	unpack_screen(ChooseCardsScene)
	var row: Control = content.get_node("Cards/Row")
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b):
		var first: Dictionary = a.card_data if a is Node else a
		var second: Dictionary = b.card_data if b is Node else b
		return str(first.name) < str(second.name)
	)
	for entry in sorted:
		var definition: Dictionary = live_definition(entry) if entry is Node else entry
		_card_tile(definition, row, callback.bind(entry), "Choose")
	hook_button(content.get_node("CancelButton"), cancel)

func choose_enemy_hand(cards: Array, callback: Callable, cancel: Callable) -> void:
	if intel_revealed:
		choose_card("CHOOSE AN ENEMY HAND CARD", cards, callback, cancel)
		return
	card_picker = true
	reset_panel("CHOOSE AN ENEMY HAND CARD", "Only cards currently held by the Janitor can be targeted. Cast Hazard Forecast to reveal their faces first.", "choice")
	action_cancel = cancel
	# Same layout as choose_card(), from ui_choose_cards.tscn.
	unpack_screen(ChooseCardsScene)
	var row: Control = content.get_node("Cards/Row")
	for i in range(cards.size()):
		var box := VBoxContainer.new()
		row.add_child(box)
		var back := TextureRect.new()
		back.texture = CardFace._card_back()
		back.custom_minimum_size = Vector2(180, 235)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(back)
		button("Hand card %d" % (i + 1), callback.bind(cards[i]), box)
	var cancel_button: Button = content.get_node("CancelButton")
	cancel_button.text = "Cancel"
	cancel_button.tooltip_text = "Cancel"
	hook_button(cancel_button, cancel)

func choose_slot(slots: Array, callback: Callable, cancel: Callable) -> void:
	card_picker = false
	reset_panel("CHOOSE AN EMPTY LANE", "", "choice")
	action_cancel = cancel
	for slot in slots: button("Lane %d" % (game._response_slots().find(slot) + 1), callback.bind(slot), content)
	# The lane buttons change each time; the Skip button comes from ui_choose_slot.tscn.
	unpack_screen(ChooseSlotScene)
	hook_button(content.get_node("SkipButton"), cancel)

func show_intel() -> void:
	intel_revealed = true
	reset_panel("HAZARD FORECAST", "Revealed until the encounter ends.", "intel")
	# The layout lives in ui_intel.tscn: a scrollable row for a full hand.
	unpack_screen(IntelScene)
	var row: Control = content.get_node("Scroll/Row")
	if not game.enemy_hand.is_empty(): row.get_node("EmptyLabel").free()
	for card in game.enemy_hand: _card_tile(card, row)
	hook_button(content.get_node("ReturnButton"), close_modal)

func show_buff_choices(restore_offers: bool = false) -> void:
	if not restore_offers: buff_choices.clear()
	var pool: Array = Rules.BUFFS.duplicate(true)
	if not restore_offers:
		for i in range(3):
			var index := rng.randi_range(0, pool.size() - 1)
			buff_choices.append(pool.pop_at(index))
	reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn,
		"Lasts this battle.", "buff")
	# The layout lives in ui_buff_choices.tscn; the buff tiles are made here.
	var box := centered_screen(BuffChoicesScene)
	var row: Control = box.get_node("Row")
	for buff in buff_choices:
		choice_tile(buff.name, buff.description, select_buff.bind(buff.id), row)
	box.get_node("Summary").text = "YOUR BUFFS: " + buff_summary(game.player_buffs)

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
	reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % floor_number,
		"Lasts the whole run.", "floor_buff")
	# The layout lives in ui_floor_buffs.tscn; the buff tiles are made here.
	var box := centered_screen(FloorBuffsScene)
	var row: Control = box.get_node("Row")
	for buff in buff_choices: choice_tile(buff.name, buff.description, select_floor_buff.bind(buff.id), row)
	hook_button(box.get_node("ReturnButton"), return_title)

func select_floor_buff(id: String) -> void:
	if screen != "floor_buff" or not buff_choices.any(func(buff): return buff.id == id): return
	game.add_global_buff(true, id, true)
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
