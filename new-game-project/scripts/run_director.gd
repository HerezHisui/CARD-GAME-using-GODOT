extends CanvasLayer
## Owns the persistent run. Battle copies never mutate the collection.
const RouteCanvas = preload("res://scripts/route_canvas.gd")
const CardFace = preload("res://scripts/card_3d.gd")
const Rules = preload("res://scripts/battle_rules.gd")
const TITLE_ART_PATH := "res://assets/title_screen.png"
static var start_after_reload := false
static var last_character := 0
const DECISIONS := ["reward", "shop", "event", "upgrade", "upgrade_preview", "result", "choice", "buff", "floor_buff", "intel", "title", "title_help", "characters", "character_preview"]
const MAP_ROWS := 11
const MAX_UPGRADES := 2
const CHARACTERS := [
	{"name":"Alex · Cadet", "description":"Balanced training. Units start with +1 health.", "buff":"cadet", "deck":[]},
	{"name":"Mika · Route Marshal", "description":"Evac formations, movement and draw. Matching neighbors gain +1 extra damage.", "buff":"marshal", "deck":["quick_dash", "quick_dash", "fire_drill", "fire_drill", "lane_marshal", "lane_marshal", "runner", "runner", "evacuation", "tutor", "shelter_brace", "rally"]},
	{"name":"Sam · Hazmat Specialist", "description":"Burn and Poison combinations. Apply +2 Burn and +1 Poison; units lose 1 health.", "buff":"chemist", "deck":["fire_truck", "fire_truck", "steam_team", "steam_team", "hazmat_team", "hazmat_team", "debris_clearance", "debris_clearance", "heat_seeker", "toxin_hunter", "cleanse", "tutor"]},
	{"name":"Jo · Barricade Captain", "description":"Brace formations and Strength. Surviving blockers retaliate for 1 fixed damage.", "buff":"warden", "deck":["shelter_brace", "shelter_brace", "shard_barrier", "shard_barrier", "captain", "captain", "drill_leader", "momentum_team", "fire_truck", "field_medic", "rally", "cleanse"]}
]
var selected_character := 0
const SORT_KEYS := ["name", "element", "cost", "attack", "health", "modifier"]
const GOLD := Color("c9aa70")
const TEAL := Color("75d6c6")
const BG := Color("0c141f")
var game: Node
var collection: Array[Dictionary] = []
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
var saved_content: VBoxContainer
var saved_screen := ""
var map_button: Button
var menu_button: Button
var action_cancel: Callable
var buff_choices: Array = []
var intel_revealed := false
var idle_hint: Label
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
	game.load_deck_from_json("res://data/starter_deck.json", catalog)
	game.load_deck_from_json("res://data/response_expansion.json", catalog)
	# Utility cards belong to the reward pool, preserving the original starter deck.
	catalog.append({"id":"supply_cache", "name":"Supply Cache", "type":"response", "element":"clearance", "cost":1, "attack":0, "health":1, "effect":"draw", "utility":true})
	catalog.append({"id":"emergency_exit", "name":"Emergency Exit", "type":"response", "element":"evac", "cost":1, "attack":0, "health":1, "effect":"move", "utility":true})
	if start_after_reload:
		start_after_reload = false
		new_run()
	else:
		game.clear_battle()
		show_title()

func show_title() -> void:
	get_tree().paused = false
	battle_active = false
	reset_panel("MIDNIGHT DRRILLS", "The school is silent. The Janitor is waiting.", "title")
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(400, 240)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(TITLE_ART_PATH): art.texture = load(TITLE_ART_PATH)
	content.add_child(art)
	content.add_child(label("BUILD YOUR RESPONSE. CONTAIN THE DISASTER. SURVIVE THE NIGHT.", 20, TEAL))
	button("Start a new run", show_characters, content).grab_focus()
	button("How to play", show_title_help, content)
	button("Quit", func(): get_tree().quit(), content)

func show_characters() -> void:
	reset_panel("CHOOSE YOUR CHARACTER", "Each character has a 12-card starter deck and a permanent starting perk.", "characters")
	for i in CHARACTERS.size():
		var character: Dictionary = CHARACTERS[i]
		button(character.name + "\n" + character.description, show_character_preview.bind(i), content)
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
	button("Begin run", func(): selected_character = index; last_character = index; new_run(), content)
	button("Back to characters", show_characters, content)

func show_title_help() -> void:
	reset_panel("HOW TO SURVIVE", "Choose connected school rooms, collect cards, and defeat the Janitor at the end of each floor.", "title_help")
	content.add_child(label("Drag Response cards onto empty lower slots. Draw before playing. Space ends your turn. W / S changes the camera.", 18))
	content.add_child(label("D views your deck. M opens and closes the map during battle. Esc opens the menu. These screens pause the battle.", 18))
	content.add_child(label("Blocking cards stop all normal damage. Piercing strikes the blocker AND the opposing health pool. Sluggish skips every other round.", 18))
	content.add_child(label("Burn: upkeep damage, then halve stacks. Poison: upkeep damage, then lose 1 stack. Bleed: damage after attacking, then lose 1 stack.", 18))
	content.add_child(label("Every 5 rounds: choose 1 of 3 battle-only adaptations. After a boss: choose a permanent floor reward. Both sides receive buffs.", 18, TEAL))
	button("Back", show_title, content)

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
	b.pressed.connect(action)
	parent.add_child(b)
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
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	modal.add_child(content)
	idle_hint = label("Choose your next room with School map  [M]", 20, TEAL)
	idle_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(idle_hint)
	idle_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	idle_hint.offset_top = -60
	idle_hint.offset_bottom = -20
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
	for name in ["OrbGauge_2", "OrbGauge_3", "HintW", "HintS", "EnemyDeckPlaque", "DeckShadow"]:
		hud.get_node(name).hide()
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
	summary.text = "Floor %d  /  HP %d  /  %d supplies  /  %d cards" % [floor_number, game.player_hp, coins, collection.size()]
	prep.max_value = game.energy_cap
	prep.value = game.preparedness
	threat.max_value = game.tension_cap
	threat.value = game.tension
	prep.get_parent().get_child(0).text = "PREPAREDNESS  %d / %d" % [game.preparedness, game.energy_cap]
	threat.get_parent().get_child(0).text = "TENSION  %d / %d" % [game.tension, game.tension_cap]
	threat.get_parent().get_child(2).text = "Deck %d  /  Evolutions %d" % [game.enemy_deck.size(), game.enemy_evolution_deck.size()]
	prep.get_parent().get_child(2).text = "Deck %d  /  Hand %d" % [game.deck.size(), game.get_hand_cards().size()]
	game.get_node("HUD/Root").visible = battle_active and not modal.visible
	game.get_node("HUD/Root/DeckDrawButton/DeckCountLabel").text = "Draw · %d left" % game.deck.size()
	root.get_child(0).visible = screen not in ["title", "title_help", "characters", "character_preview"]
	map_button.disabled = saved_content != null or screen in DECISIONS
	menu_button.disabled = map_button.disabled
	idle_hint.visible = not battle_active and not modal.visible
	prep.get_parent().visible = battle_active and not modal.visible
	threat.get_parent().visible = battle_active and not modal.visible

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if screen in ["title", "title_help", "characters", "character_preview"]: return
		match event.keycode:
			KEY_D: show_deck()
			KEY_M: toggle_map()
			KEY_ESCAPE:
				if screen == "choice" and action_cancel.is_valid():
					action_cancel.call()
				elif screen == "intel": close_modal()
				elif screen == "deck" or (modal.visible and screen in ["map", "menu"] and battle_active):
					close_modal()
				else:
					show_menu()
			_: return
		get_viewport().set_input_as_handled()

func reset_panel(title: String, subtitle: String, kind: String) -> void:
	if battle_active: get_tree().paused = true
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	screen = kind
	modal.show()
	content.add_child(label(title, 30, GOLD))
	content.add_child(label(subtitle, 16, Color("9cacb9")))

func close_modal() -> void:
	if saved_content:
		modal.remove_child(content)
		content.queue_free()
		content = saved_content
		modal.add_child(content)
		saved_content = null
		screen = saved_screen
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
	get_tree().paused = false
	if saved_content:
		saved_content.queue_free()
		saved_content = null
	screen = ""
	saved_screen = ""
	action_cancel = Callable()
	intel_revealed = false
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
	collection = character_deck(selected_character)
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
			rooms.append({"id":rooms.size(), "row":row, "lane":lane if row < MAP_ROWS - 1 else 1, "kind":kind, "links":[]})
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
	reset_panel("THE SCHOOL MAP", "11 rooms to the boss. Every route includes at least 4 combat encounters. Scroll sideways to explore.  •  Seed %d" % run_seed, "map")
	var canvas := RouteCanvas.new()
	canvas.rooms = rooms
	canvas.current = current
	canvas.cleared = cleared
	canvas.custom_minimum_size = Vector2(1670, 390)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(map_scroll)
	map_scroll.add_child(canvas)
	if current >= 0: map_scroll.set_deferred("scroll_horizontal", maxi(0, int(rooms[current].row) * 150 - 400))
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
		b.position = canvas.point(room) - b.size / 2
	var footer := HBoxContainer.new()
	content.add_child(footer)
	footer.add_child(label("Battle  /  Elite  /  Rest  /  Workshop  /  Event  /  Shop  →  JANITOR", 16, TEAL))
	if battle_active: button("Return to battle", close_modal, footer)
	else: button("Close map  [M]", toggle_map, footer)

func toggle_map() -> void:
	if _dragging() or saved_content or screen in DECISIONS: return
	if screen == "map":
		get_tree().paused = false
		modal.hide()
		screen = ""
	else:
		show_map()

func visit(id: int) -> void:
	if not reachable(id): return
	current = id
	encounter = rooms[id].kind
	match encounter:
		"battle", "elite", "boss":
			intel_revealed = false
			battle_active = true
			modal.hide()
			screen = ""
			game.start_encounter(collection, encounter, floor_number, rng.randi_range(0, 3))
		"rest":
			reset_panel("THE INFIRMARY", "A brief shelter from the night. Recover 7 health, or train a card.", "event")
			button("Rest · heal 7 HP", rest, content)
			button("Train · upgrade a card", show_upgrade, content)
		"upgrade": show_upgrade()
		"shop": show_shop()
		"event": show_event()

func finish_room() -> void:
	if current not in cleared: cleared.append(current)
	screen = ""
	game._refresh_bars()
	show_map()

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
		reset_panel("TRAPPED AFTER MIDNIGHT", "Your run has ended. Begin again with a new school layout.", "result")
		button("Start a new run", restart_scene, content)
		return
	coins += 35 if encounter == "elite" else (60 if encounter == "boss" else 20)
	if encounter == "boss":
		game.clear_battle(true)
		show_floor_buffs()
	else:
		show_rewards()

func next_floor() -> void:
	floor_number += 1
	game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 5)
	game.clear_battle()
	generate_map()
	screen = ""
	show_map()

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	content.add_child(row)
	for card in offers(3):
		_card_tile(card, row, func(): collection.append(card.duplicate(true)); finish_room(), "Take card")
	button("Skip card reward", finish_room, content)

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
	if intel_revealed: button("Janitor hand", func(): deck_cards(game.enemy_hand), tabs)
	button("Close", close_modal, tabs)
	add_sort_controls(false)
	var scroll := ScrollContainer.new()
	scroll.name = "Cards"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	deck_cards(collection)

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

func sorted_indices(cards: Array, key_index: int, descending: bool) -> Array:
	var indices: Array = range(cards.size())
	var key: String = SORT_KEYS[key_index]
	indices.sort_custom(func(a, b):
		var left: Variant = cards[a].get(key, "")
		var right: Variant = cards[b].get(key, "")
		var comparison := 0
		if key in ["cost", "attack", "health"]:
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
	for title in ["Name", "Type", "Cost", "Attack", "Health", "Modifier"]: picker.add_item(title)
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
		shop_purchased.clear()
	reset_panel("THE SUPPLY ROOM", "Buy as many stocked items as you can afford. Card prices scale with power. Repeatable first aid: 15. Stock stays fixed.", "shop")
	var row := HBoxContainer.new()
	content.add_child(row)
	for card in shop_stock:
		var sold: bool = card.id in shop_purchased
		var price := shop_price(card)
		_card_tile(card, row, buy.bind(card) if not sold and coins >= price else Callable(), "Buy · %d" % price)
		if sold: row.get_child(row.get_child_count() - 1).get_child(0).add_child(label("SOLD OUT", 16, GOLD))
		elif coins < price: row.get_child(row.get_child_count() - 1).get_child(0).add_child(label("Need %d supplies" % price, 14, Color("9cacb9")))
	button("First aid · 5 HP · 15 supplies", buy_heal, content).disabled = coins < 15 or game.player_hp >= game.PLAYER_MAX_HP
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
	collection.append(definition.duplicate(true))
	shop_purchased.append(definition.id)
	show_shop()

func buy_heal() -> void:
	if coins < 15 or game.player_hp >= game.PLAYER_MAX_HP: return
	coins -= 15
	game.player_hp = mini(game.PLAYER_MAX_HP, game.player_hp + 5)
	show_shop()

func show_event() -> void:
	reset_panel("A LOCKED CLASSROOM", "Emergency supplies wait behind broken glass. Take the risk, or search safely.", "event")
	button("Break the glass · lose 3 HP, gain a card and 30 supplies", event_risk, content).disabled = game.player_hp <= 3
	button("Search the hallway · gain 10 supplies", func(): coins += 10; finish_room(), content)

func event_risk() -> void:
	game.player_hp -= 3
	coins += 30
	collection.append(offers(1)[0])
	finish_room()

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
	button("Restart run…", confirm_restart, content)
	button("Quit game", quit_game, content)

func quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()

func confirm_restart() -> void:
	reset_panel("RESTART THIS RUN?", "Your current deck, supplies, and route will be replaced by a fresh run.", "menu")
	button("Start new run", restart_scene, content)
	button("Keep playing", close_modal, content)

func _dragging() -> bool:
	for card in game.get_hand_cards():
		if card.is_dragging: return true
	return false

func restart_scene() -> void:
	get_tree().paused = false
	start_after_reload = true
	get_tree().call_deferred("reload_current_scene")

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

func show_buff_choices() -> void:
	buff_choices.clear()
	var pool: Array = Rules.BUFFS.duplicate(true)
	for i in range(3):
		var index := rng.randi_range(0, pool.size() - 1)
		buff_choices.append(pool.pop_at(index))
	var enemy_choice: Dictionary = game.choose_ai_buff(buff_choices)
	game.add_global_buff(false, enemy_choice.id)
	reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn, "These buffs expire after this battle. The Janitor chose: %s." % enemy_choice.name, "buff")
	for buff in buff_choices:
		button(buff.name + "\n" + buff.description, select_buff.bind(buff.id), content)
	content.add_child(label("YOUR BUFFS: " + buff_summary(game.player_buffs) + "\nJANITOR BUFFS: " + buff_summary(game.enemy_buffs), 16, TEAL))

func select_buff(id: String) -> void:
	if screen != "buff" or not buff_choices.any(func(buff): return buff.id == id): return
	game.add_global_buff(true, id)
	close_modal()
	game.continue_round()

func show_floor_buffs() -> void:
	buff_choices.clear()
	var pool: Array = Rules.RUN_BUFFS.duplicate(true)
	for i in range(3): buff_choices.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % floor_number, "Choose one buff for the entire run, then climb to the next floor. The Janitor also adapts permanently.", "floor_buff")
	for buff in buff_choices: button(buff.name + "\n" + buff.description, select_floor_buff.bind(buff.id), content)
	button("Start a new run instead", restart_scene, content)

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
