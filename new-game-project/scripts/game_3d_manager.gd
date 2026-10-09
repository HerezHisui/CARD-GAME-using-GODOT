extends Node3D
## Main game manager: builds the creepy classroom, the pixel-art board,
## the gothic HUD, and controls the deck + fanned card hand.

const Card3DScene = preload("res://scenes/card_3d.tscn")

const HAND_SIZE_MAX := 8
const HAND_DIST := 3.0        # Smaller hand leaves space for the board and HUD.
const HAND_Y := -1.35         # Keep card names and bottom stats inside the viewport.
const UPRIGHT := Basis(Vector3.RIGHT, PI / 2.0)

# Palette
const BONE := Color(0.88, 0.82, 0.68)
const GOLD := Color(0.72, 0.55, 0.22)
const INK := Color(0.04, 0.03, 0.04, 0.92)

var deck: Array[Dictionary] = []
var enemy_deck: Array[Dictionary] = []
var enemy_evolution_deck: Array[Dictionary] = []
var enemy_hand: Array[Dictionary] = []
var hand: Array = []
var turn := 1
var in_board_view := false
var run_director: CanvasLayer
var enemy_max_hp := ENEMY_MAX_HP
var camera_tween: Tween
var player_buffs: Dictionary = {}
var enemy_buffs: Dictionary = {}
var player_run_buffs: Dictionary = {}
var enemy_run_buffs: Dictionary = {}
var encounter_kind := "battle"
var moving_ally: Node
var adapted_round := 0
var pending_utility: Node
var pending_effect := ""

# ---- Turn system -------------------------------------------------------
enum Phase { SETUP, PLAYER_DRAW, PLAYER_PLAY, ENEMY, COMBAT, GAME_OVER }
const STARTING_HAND := 3
const ENERGY_START := 3
const ENERGY_MAX := 10
const TENSION_START := 3
const TENSION_MAX := 10
const PLAYER_MAX_HP := 20
const ENEMY_MAX_HP := 20

var phase: Phase = Phase.SETUP
var player_first := true      # who acts (and attacks) first this round
var energy_cap := ENERGY_START
var preparedness := ENERGY_START  # current Response energy
var tension_cap := TENSION_START  # Disaster tension cap
var tension := TENSION_START      # current Disaster tension
## Unblocked attacks hit the opposing side's HP. 0 HP = that side loses.
var player_hp := PLAYER_MAX_HP
var enemy_hp := ENEMY_MAX_HP

# ---- Camera views (pivot position, pivot rotation in degrees, camera distance)
const DESK_VIEW := {"pos": Vector3(0, 1.25, 0.4), "rot": Vector3(-42, 0, 0), "dist": 6.2}
const BOARD_VIEW := {"pos": Vector3(0, 1.0, 0.0), "rot": Vector3(-90, 0, 0), "dist": 4.8}

# HUD references
@onready var _deck_count: Label = $HUD/Root/DeckDrawButton/DeckCountLabel
@onready var _turn_label: Label = $HUD/Root/TurnPlaque/TurnLabel
@onready var _hint_w: Label = $HUD/Root/HintW
@onready var _hint_s: Label = $HUD/Root/HintS
@onready var _phase_label: Label = $HUD/Root/PhaseLabel
@onready var _end_turn_btn: Button = $HUD/Root/EndTurnButton

@onready var _prep_fill: ColorRect = $HUD/Root/OrbGauge_2/Mask/Fill
@onready var _prep_label: Label = $HUD/Root/OrbGauge_2/ValueLabel
@onready var _tension_fill: ColorRect = $HUD/Root/OrbGauge_3/Mask/Fill
@onready var _tension_label: Label = $HUD/Root/OrbGauge_3/ValueLabel
@onready var _player_hp_ui: Control = $HUD/Root/PlayerHealth
@onready var _enemy_hp_ui: Control = $HUD/Root/EnemyHealth
@onready var _enemy_deck_count: Label = $HUD/Root/EnemyDeckPlaque/VBox/EnemyDeckCountLabel

var hand_container: Node3D
var is_hand_tucked := false
var hand_tuck_tween: Tween

@onready var camera: Camera3D = $CameraPivot/Camera3D

func _ready() -> void:
	hand_container = Node3D.new()
	camera.add_child(hand_container)
	_apply_view(DESK_VIEW)
	
	var vp := get_viewport()
	vp.physics_object_picking = true
	vp.physics_object_picking_sort = true
	vp.physics_object_picking_first_only = true

	_build_environment()
	_build_board()
	_build_lighting()
	$HUD/Root/DeckDrawButton.pressed.connect(_on_draw_button_pressed)
	_end_turn_btn.pressed.connect(_on_end_turn_pressed)

	load_deck_from_json("res://data/starter_deck.json", deck)
	var all_disaster: Array[Dictionary] = []
	load_deck_from_json("res://data/disaster_deck.json", all_disaster)
	enemy_deck.clear()
	enemy_evolution_deck.clear()
	for c in all_disaster:
		if int(c.get("cost", 0)) > 0:
			enemy_evolution_deck.append(c)
		else:
			enemy_deck.append(c)
	deck.shuffle()
	enemy_deck.shuffle()
	enemy_evolution_deck.shuffle()
	
	update_deck_label()
	_refresh_bars()
	_refresh_view_hints()
	run_director = preload("res://scripts/run_director.gd").new()
	add_child(run_director)

func clear_battle(preserve_result: bool = false) -> void:
	player_buffs.clear()
	enemy_buffs.clear()
	moving_ally = null
	pending_utility = null
	pending_effect = ""
	adapted_round = 0
	if not preserve_result: _set_phase(Phase.SETUP, "Choose your next room on the school map")
	for card in get_tree().get_nodes_in_group("cards"):
		card.remove_from_group("cards")
		card.queue_free()
	hand.clear()
	deck.clear()
	enemy_deck.clear()
	enemy_hand.clear()
	enemy_evolution_deck.clear()

func start_encounter(collection: Array[Dictionary], kind: String, floor_level: int, specialty: int) -> void:
	clear_battle()
	encounter_kind = kind
	run_director.intel_revealed = false
	turn = 1
	energy_cap = maxi(1, ENERGY_START + buff_value(true, "energy"))
	preparedness = energy_cap
	tension_cap = maxi(1, TENSION_START + buff_value(false, "energy"))
	tension = tension_cap
	enemy_max_hp = 20 + (floor_level - 1) * 3 + (4 if kind == "elite" else (8 if kind == "boss" else 0))
	enemy_hp = enemy_max_hp
	for definition in collection: deck.append(definition.duplicate(true))
	var threats: Array[Dictionary] = []
	load_deck_from_json("res://data/disaster_deck.json", threats)
	load_deck_from_json("res://data/disaster_expansion.json", threats)
	var favored: String = ["fire", "earthquake", "flood", "typhoon"][specialty]
	_enemy_hp_ui.get_node("Caption").text = "JANITOR / %s / %s" % [kind.to_upper(), favored.to_upper()]
	_enemy_hp_ui.get_node("Caption").add_theme_font_size_override("font_size", 14)
	for definition in threats:
		var c: Dictionary = definition.duplicate(true)
		c.attack = int(c.attack) + (floor_level - 1) + (1 if kind == "boss" else 0)
		c.health = int(c.health) + (1 if kind in ["elite", "boss"] else 0)
		if int(c.cost) > 0:
			enemy_evolution_deck.append(c)
		else:
			enemy_deck.append(c)
			if c.element == favored: enemy_deck.append(c.duplicate(true))
	# Modest reserves keep encounters from becoming endless reinforcement chains.
	var base_limit := 20 if kind == "battle" else (21 if kind == "elite" else 22)
	var evolution_limit := 12 if kind == "battle" else (13 if kind == "elite" else 14)
	enemy_deck.shuffle()
	enemy_deck.sort_custom(func(a, b): return a.element == favored and b.element != favored)
	enemy_deck.resize(mini(base_limit, enemy_deck.size()))
	enemy_evolution_deck.shuffle()
	enemy_evolution_deck.resize(mini(evolution_limit, enemy_evolution_deck.size()))
	if kind == "elite":
		enemy_evolution_deck.append({"id":"elite_guardian", "name":"Hallway Guardian", "type":"disaster", "element":favored, "cost_type":"sacrifice", "cost":2, "attack":4 + floor_level, "health":5, "modifier":"armored"})
	if kind == "boss":
		enemy_evolution_deck.append({"id":"midnight_cataclysm", "name":"Midnight Cataclysm", "type":"disaster", "element":favored, "cost_type":"sacrifice", "cost":3, "attack":6 + floor_level, "health":8, "modifier":"fierce"})
	deck.shuffle()
	enemy_deck.shuffle()
	enemy_evolution_deck.shuffle()
	_refresh_bars()
	set_board_view(false)
	_start_match()

func _load_tex(path: String) -> Texture2D:
	var tex = load(path)
	if tex: return tex
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(img)
	return null

# =================================================================== ENVIRONMENT
func _build_environment() -> void:
	var tex_room = _load_tex("res://assets/pixel_classroom.jpg")
	var tex_wood = _load_tex("res://assets/dark_wood_desk.jpg")

	var room := Node3D.new()
	room.name = "ClassroomEnvironment"
	add_child(room)

	var mat_walls := StandardMaterial3D.new()
	mat_walls.albedo_texture = _load_tex("res://assets/creepy_wallpaper.jpg")
	mat_walls.albedo_color = Color(0.3, 0.3, 0.35)
	mat_walls.uv1_scale = Vector3(6, 4, 6)
	mat_walls.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var walls := CSGBox3D.new()
	walls.size = Vector3(40, 16, 40)
	walls.position = Vector3(0, 8, 0)
	walls.flip_faces = true
	walls.material_override = mat_walls
	walls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(walls)

	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.05, 0.05, 0.06)
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_box.position = Vector3(0, -0.5, 0)
	floor_box.material_override = mat_floor
	room.add_child(floor_box)

	var mat_chalk := StandardMaterial3D.new()
	mat_chalk.albedo_color = Color(0.1, 0.15, 0.1)
	var board := CSGBox3D.new()
	board.size = Vector3(16, 6, 0.5)
	board.position = Vector3(0, 7, -19.5)
	board.material_override = mat_chalk
	room.add_child(board)

	if tex_room:
		var chalk_art := Sprite3D.new()
		chalk_art.texture = tex_room
		chalk_art.pixel_size = 0.03
		chalk_art.position = Vector3(0, 7, -19.2)
		chalk_art.modulate = Color(0.5, 1.0, 0.5, 0.8)
		room.add_child(chalk_art)

	var mat_desk := StandardMaterial3D.new()
	mat_desk.albedo_texture = tex_wood
	mat_desk.albedo_color = Color(0.3, 0.25, 0.25)
	mat_desk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for pos in [Vector3(-8, 1.5, -8), Vector3(-12, 1.5, -6), Vector3(9, 1.5, -10),
			Vector3(14, 1.5, -7), Vector3(-7, 1.5, -15), Vector3(8, 1.5, -16)]:
		var d := CSGBox3D.new()
		d.size = Vector3(3, 3, 2.5)
		d.position = pos
		d.material_override = mat_desk
		d.rotation_degrees = Vector3(0, pos.x * 7 + 15, 0)
		room.add_child(d)

	var table = get_node_or_null("Table")
	if table and tex_wood:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex_wood
		mat.albedo_color = Color(0.4, 0.35, 0.35)
		mat.uv1_scale = Vector3(2, 2, 2)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		table.material = mat

# =================================================================== BOARD
## Procedurally paints a crisp pixel-art playmat (burgundy felt, gold trim,
## slot outlines exactly where the slot colliders are).
const BOARD_W := 6.2
const BOARD_H := 4.2
const PPU := 32 # pixels per world unit

func _build_board() -> void:
	var w := int(BOARD_W * PPU)
	var h := int(BOARD_H * PPU)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)

	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.04
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var felt := Color(0.07, 0.15, 0.18)
	for y in h:
		for x in w:
			var v := noise.get_noise_2d(x, y) * 0.035 + rng.randf_range(-0.012, 0.012)
			img.set_pixel(x, y, Color(felt.r + v, felt.g + v * 0.4, felt.b + v * 0.4))

	var dark := Color(0.025, 0.055, 0.08)
	var gold_dim := Color(0.48, 0.35, 0.14)
	# Outer rim + double gold frame
	_rect_outline(img, Rect2i(0, 0, w, h), 3, dark)
	_rect_outline(img, Rect2i(5, 5, w - 10, h - 10), 2, GOLD)
	_rect_outline(img, Rect2i(9, 9, w - 18, h - 18), 1, gold_dim)
	for c in [Vector2i(9, 9), Vector2i(w - 10, 9), Vector2i(9, h - 10), Vector2i(w - 10, h - 10)]:
		_diamond(img, c, 4, GOLD)

	# Dashed divider between the Threat row and the Response row
	var mid := h / 2
	for x in range(18, w - 18):
		if (x / 4) % 2 == 0:
			img.set_pixel(x, mid, gold_dim)
	_diamond(img, Vector2i(14, mid), 3, GOLD)
	_diamond(img, Vector2i(w - 15, mid), 3, GOLD)

	# Slot wells
	var slots_node = get_node_or_null("Slots")
	if slots_node:
		for slot in slots_node.get_children():
			if slot is MeshInstance3D:
				slot.visible = false # collider stays active; the art is painted below
				var cx := int((slot.position.x + BOARD_W / 2.0) * PPU)
				var cy := int((slot.position.z + BOARD_H / 2.0) * PPU)
				var sw := int(1.1 * PPU)
				var sh := int(1.5 * PPU)
				var r := Rect2i(cx - sw / 2, cy - sh / 2, sw, sh)
				img.fill_rect(r, Color(0.035, 0.085, 0.11))
				_rect_outline(img, r, 1, gold_dim)
				# subtle bevel: dark top/left inner edge for an inset look
				img.fill_rect(Rect2i(r.position.x + 1, r.position.y + 1, sw - 2, 2), Color(0.06, 0.01, 0.02))
				img.fill_rect(Rect2i(r.position.x + 1, r.position.y + 1, 2, sh - 2), Color(0.06, 0.01, 0.02))

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color(0.75, 0.72, 0.72)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.95
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOARD_W, BOARD_H)
	var board := MeshInstance3D.new()
	board.name = "Playmat"
	board.mesh = plane
	board.material_override = mat
	board.position = Vector3(0, 1.006, 0)
	add_child(board)

func _rect_outline(img: Image, r: Rect2i, t: int, col: Color) -> void:
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, t), col)
	img.fill_rect(Rect2i(r.position.x, r.end.y - t, r.size.x, t), col)
	img.fill_rect(Rect2i(r.position.x, r.position.y, t, r.size.y), col)
	img.fill_rect(Rect2i(r.end.x - t, r.position.y, t, r.size.y), col)

func _diamond(img: Image, c: Vector2i, rad: int, col: Color) -> void:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if abs(dx) + abs(dy) <= rad:
				var p := c + Vector2i(dx, dy)
				if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
					img.set_pixelv(p, col)

# =================================================================== LIGHTING
func _build_lighting() -> void:
	var light = get_node_or_null("SpookyLight")
	if light is SpotLight3D:
		light.light_color = Color(1.0, 0.75, 0.5)
		light.light_energy = 5.0
		light.spot_angle = 80.0
		light.spot_range = 25.0
		light.position = Vector3(0, 5.5, 1.5)
		light.shadow_enabled = true

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Color(0.5, 0.6, 0.8)
	moon.light_energy = 0.8
	moon.rotation_degrees = Vector3(-45, 120, 0)
	moon.shadow_enabled = true
	add_child(moon)

	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.3, 0.35, 0.45)
		env.ambient_light_energy = 1.0
		env.volumetric_fog_enabled = false # Compatibility renderer does not support volumetric fog.
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = Color(0.2, 0.3, 0.4)

func _set_orb(fill: ColorRect, value_label: Label, amount: int, max_amount: int) -> void:
	if not fill or not value_label: return
	var r: float = 52.0
	var ratio := clampf(float(amount) / float(max_amount), 0.0, 1.0)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(fill, "position:y", r * 2.0 * (1.0 - ratio), 0.35)
	value_label.text = "%d/%d" % [amount, max_amount]

func _refresh_bars() -> void:
	_set_orb(_prep_fill, _prep_label, preparedness, energy_cap)
	_set_orb(_tension_fill, _tension_label, tension, tension_cap)
	_set_health(_player_hp_ui, player_hp, PLAYER_MAX_HP, false)
	_set_health(_enemy_hp_ui, enemy_hp, enemy_max_hp, false)
	update_deck_label()

## Updates a health widget (HUD/Root/PlayerHealth or EnemyHealth).
## The main bar drops instantly-ish, the pale "lag" bar trails behind it.
func _set_health(ui: Control, hp: int, max_hp: int, animate: bool) -> void:
	if not ui: return
	var bar: ProgressBar = ui.get_node("Bar")
	var lag: ProgressBar = ui.get_node("LagBar")
	var value: Label = ui.get_node("Value")
	bar.max_value = max_hp
	lag.max_value = max_hp
	value.text = "%d / %d" % [maxi(hp, 0), max_hp]
	if not animate:
		bar.value = hp
		lag.value = hp
		return
	var t := create_tween()
	t.tween_property(bar, "value", float(hp), 0.15).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.35)
	t.tween_property(lag, "value", float(hp), 0.45).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

## Unblocked hit on a side's HP: drain bar, shake the widget, float the number.
func _damage_side(player_side: bool, amt: int) -> void:
	var ui := _player_hp_ui if player_side else _enemy_hp_ui
	if player_side:
		player_hp = maxi(0, player_hp - amt)
		_set_health(ui, player_hp, PLAYER_MAX_HP, true)
	else:
		enemy_hp = maxi(0, enemy_hp - amt)
		_set_health(ui, enemy_hp, enemy_max_hp, true)
	shake_camera(0.12 + amt * 0.02, 0.3)

	# Widget shake + red flash
	var home := ui.position
	var t := create_tween()
	ui.modulate = Color(1, 0.45, 0.45)
	for i in 5:
		t.tween_property(ui, "position", home + Vector2(randf_range(-7, 7), randf_range(-4, 4)), 0.035)
	t.tween_property(ui, "position", home, 0.04)
	t.parallel().tween_property(ui, "modulate", Color.WHITE, 0.3)

	# Floating "-N" next to the bar
	var l := Label.new()
	l.text = "-%d" % amt
	l.add_theme_font_override("font", ui.get_node("Value").get_theme_font("font"))
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	l.position = Vector2(110, 20)
	var lt := l.create_tween().set_parallel(true)
	lt.tween_property(l, "position:y", l.position.y - 50, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	lt.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	lt.chain().tween_callback(l.queue_free)

func update_deck_label() -> void:
	if _deck_count:
		_deck_count.text = str(deck.size())
	if _enemy_deck_count:
		_enemy_deck_count.text = "%d cards" % enemy_deck.size()

func enemy_draw_cards(count: int) -> void:
	for i in range(count):
		if enemy_hand.size() >= 6: break
		var available := enemy_deck.filter(func(c): return not is_sealed(c))
		if available.is_empty(): break
		var picked: Dictionary = available.back()
		enemy_deck.erase(picked)
		enemy_hand.append(picked)
	update_deck_label()

func _refresh_view_hints() -> void:
	if _hint_w:
		_hint_w.modulate.a = 0.35 if in_board_view else 0.9
		_hint_s.modulate.a = 0.9 if in_board_view else 0.35

# =================================================================== CAMERA & INPUT
func _unhandled_key_input(event: InputEvent) -> void:
	if run_director and run_director.modal.visible: return
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_SPACE:
		_on_end_turn_pressed()
	elif phase == Phase.COMBAT:
		return   # the camera is busy showing the fight
	elif event.keycode == KEY_W and not in_board_view:
		set_board_view(true)
	elif event.keycode == KEY_S and in_board_view:
		set_board_view(false)

func set_board_view(on: bool) -> void:
	in_board_view = on
	_shift_camera(BOARD_VIEW if on else DESK_VIEW)
	_refresh_view_hints()

func _apply_view(v: Dictionary) -> void:
	$CameraPivot.position = v.pos
	$CameraPivot.rotation_degrees = v.rot
	camera.position = Vector3(0, 0, v.dist)
	camera.rotation = Vector3.ZERO

func _shift_camera(v: Dictionary, dur: float = 0.55) -> void:
	var pivot = $CameraPivot
	if camera_tween: camera_tween.kill()
	var tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	camera_tween = tween
	tween.tween_property(pivot, "position", v.pos, dur)
	tween.tween_property(pivot, "rotation_degrees", v.rot, dur)
	tween.tween_property(camera, "position", Vector3(0, 0, v.dist), dur)
	tween.tween_property(camera, "rotation", Vector3.ZERO, dur)

## Screen shake using the camera's view offsets (doesn't fight the view tweens).
func shake_camera(strength: float, duration: float) -> void:
	var t := create_tween()
	var steps := int(duration / 0.03)
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		t.tween_property(camera, "h_offset", randf_range(-1, 1) * strength * falloff, 0.03)
		t.parallel().tween_property(camera, "v_offset", randf_range(-1, 1) * strength * falloff, 0.03)
	t.tween_property(camera, "h_offset", 0.0, 0.03)
	t.parallel().tween_property(camera, "v_offset", 0.0, 0.03)

# =================================================================== DECK / HAND
func load_deck_from_json(path: String, target_deck: Array) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK: return
	if typeof(json.data) == TYPE_ARRAY:
		for def in json.data:
			for i in range(def.get("count", 1)):
				var card = def.duplicate()
				card.erase("count")
				target_deck.append(card)

func hand_parent() -> Node3D:
	return hand_container

func _process(delta: float) -> void:
	if phase == Phase.COMBAT:
		if not is_hand_tucked:
			set_hand_tucked(true)
		return

	if in_board_view:
		var mouse_y = get_viewport().get_mouse_position().y
		var screen_h = get_viewport().get_visible_rect().size.y
		# Untuck if hovering in the bottom 25% of the screen
		var should_tuck = mouse_y < screen_h * 0.75
		
		# Keep tucked if holding a card (so you can see slots clearly)
		for c in get_hand_cards():
			if c.is_dragging:
				should_tuck = true
				break
				
		if should_tuck != is_hand_tucked:
			set_hand_tucked(should_tuck)
	else:
		if is_hand_tucked:
			set_hand_tucked(false)

func set_hand_tucked(tucked: bool) -> void:
	is_hand_tucked = tucked
	if hand_tuck_tween: hand_tuck_tween.kill()
	hand_tuck_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Drop the entire container by 1.6 units to hide it safely off-screen
	var target_y = -1.6 if tucked else 0.0
	hand_tuck_tween.tween_property(hand_container, "position:y", target_y, 0.35)

func draw_cards(count: int) -> void:
	for i in range(count):
		if get_hand_cards().size() >= HAND_SIZE_MAX or deck.is_empty():
			break
		var available := deck.filter(func(c): return not is_sealed(c))
		if available.is_empty(): break
		var picked: Dictionary = available.back()
		deck.erase(picked)
		add_card_to_hand(picked)
	update_deck_label()
	arrange_hand_centered()

func add_card_to_hand(definition: Dictionary) -> void:
	var card = Card3DScene.instantiate()
	hand_container.add_child(card)
	card.add_to_group("cards")
	card.setup(definition)
	card.position = Vector3(2.6, -0.6, -HAND_DIST)
	card.transform.basis = UPRIGHT
	hand.append(card)
	arrange_hand_centered()
	update_deck_label()

func is_sealed(definition: Dictionary) -> bool:
	return int(definition.get("locked_until", 0)) > turn

func buffs_for(definition: Dictionary) -> Dictionary:
	var response: bool = definition.get("type", "response") == "response"
	return preload("res://scripts/battle_rules.gd").totals(player_buffs if response else enemy_buffs, player_run_buffs if response else enemy_run_buffs)

func buff_value(response: bool, id: String) -> int:
	return int(buffs_for({"type":"response" if response else "disaster"}).get(id, 0))

func attack_bonus(card: Node) -> int:
	var buffs := buffs_for(card.card_data)
	return int(buffs.get("strength", 0)) - (int(buffs.get("isolation", 0)) if card.current_slot != null and _synergy_bonus(card) == 0 else 0)

func prepare_card_data(definition: Dictionary) -> Dictionary:
	if not definition.get("utility", false): definition.health = maxi(1, int(definition.get("health", 0)) + int(buffs_for(definition).get("health", 0)))
	return definition

func add_global_buff(response_side: bool, id: String, permanent: bool = false) -> void:
	var old_health := buff_value(response_side, "health")
	var old_bleed := buff_value(response_side, "self_bleed")
	var old_energy := buff_value(response_side, "energy")
	var buffs := (player_run_buffs if response_side else enemy_run_buffs) if permanent else (player_buffs if response_side else enemy_buffs)
	buffs[id] = int(buffs.get(id, 0)) + 1
	var health_delta := buff_value(response_side, "health") - old_health
	var bleed_delta := buff_value(response_side, "self_bleed") - old_bleed
	for card in get_tree().get_nodes_in_group("cards"):
		if (card.card_data.get("type", "response") == "response") != response_side or not card.is_alive(): continue
		if not card.card_data.get("utility", false):
			var previous_max: int = card.max_health
			card.max_health = maxi(1, previous_max + health_delta)
			card.card_data.health = clampi(int(card.card_data.health) + card.max_health - previous_max, 1, card.max_health)
			if bleed_delta > 0: card.add_status("bleed", bleed_delta)
		card._refresh_face()
	if response_side: energy_cap = maxi(1, energy_cap + buff_value(true, "energy") - old_energy)

func get_hand_cards() -> Array:
	hand = hand.filter(func(c): return is_instance_valid(c))
	return hand.filter(func(c): return c.in_hand)

## Tight, overlapping, upright hand along the bottom of the screen.
func arrange_hand_centered() -> void:
	var active = get_hand_cards().filter(func(c): return not c.is_dragging)
	var count: int = active.size()
	if count == 0: return
	var spacing: float = min(0.6, 3.4 / count)
	for i in count:
		var n := i - (count - 1) / 2.0
		var pos := Vector3(n * spacing, HAND_Y - n * n * 0.012, -HAND_DIST + i * 0.002)
		var roll := deg_to_rad(-n * 2.5)
		var b := Basis(Vector3.BACK, roll) * UPRIGHT
		active[i].move_in_hand(pos, b, i)

# =================================================================== TURN SYSTEM
## Round flow:
##   coin flip (once) -> [first side: draw + play] -> [second side: draw + play]
##   -> combat (first side attacks first, then the other side) -> next round,
##   and the side that goes first swaps every round.

func can_player_act() -> bool:
	return phase == Phase.PLAYER_PLAY and (not run_director or not run_director.modal.visible)

func try_play_card(card: Node) -> bool:
	return can_player_act() and not is_sealed(card.card_data) and preparedness >= int(card.card_data.get("cost", 0))

func on_card_played(card: Node) -> void:
	hand.erase(card)
	preparedness = maxi(0, preparedness - int(card.card_data.get("cost", 0)))
	_refresh_bars()
	arrange_hand_centered()
	if not card.card_data.get("utility", false) and card.card_data.get("effect", "") == "draw": draw_cards(int(card.card_data.get("draw_count", 1)))
	if not card.card_data.get("utility", false):
		if int(card.card_data.get("on_play_draw", 0)) > 0: draw_cards(int(card.card_data.on_play_draw))
		apply_formation_effect(card)
		if card.card_data.get("effect", "") == "move_ally": begin_move_effect(card)

func apply_formation_effect(source: Node) -> void:
	var effect: String = source.card_data.get("effect", "")
	var slots := _response_slots() if source.card_data.type == "response" else _threat_slots()
	for slot in slots:
		var ally = _get_card_in_slot(slot)
		if ally == null or ally == source: continue
		if effect == "heal_all": ally.heal(2)
		elif effect == "rally_all": ally.add_status("strength", 1)

func begin_move_effect(source: Node) -> void:
	var allies := _response_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c != source and c.is_alive())
	if allies.is_empty() or _response_slots().all(func(s): return _get_card_in_slot(s) != null): return
	run_director.choose_card("LANE MARSHAL · RELOCATE AN ALLY", allies, select_moving_ally, cancel_move_effect, "Optional: choose another ally, then an empty lane. Skipping keeps the played unit on board.")

func select_moving_ally(card: Node) -> void:
	moving_ally = card
	var slots := _response_slots().filter(func(s): return _get_card_in_slot(s) == null)
	run_director.choose_slot(slots, complete_move_effect, cancel_move_effect)

func complete_move_effect(slot: Node3D) -> void:
	if is_instance_valid(moving_ally) and _get_card_in_slot(slot) == null: moving_ally.place_on_slot(slot)
	cancel_move_effect()

func cancel_move_effect() -> void:
	moving_ally = null
	run_director.action_cancel = Callable()
	run_director.close_modal()

func try_utility(card: Node, slot: Node3D) -> bool:
	if not try_play_card(card): return false
	if slot not in _response_slots() or _get_card_in_slot(slot) != null: return false
	var effect: String = card.card_data.get("effect", "")
	if effect == "move":
		var allies := _response_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c != card and c.is_alive())
		if allies.is_empty(): return false
		allies.sort_custom(func(a, b): return a.global_position.distance_squared_to(slot.global_position) < b.global_position.distance_squared_to(slot.global_position))
		allies[0].place_on_slot(slot)
	elif effect in ["tutor", "seal", "tax", "rally", "cleanse"]:
		var choices: Array = []
		match effect:
			"tutor": choices = deck.filter(func(c): return not is_sealed(c))
			"seal": choices = (enemy_deck + enemy_evolution_deck + enemy_hand).filter(func(c): return not is_sealed(c))
			"tax": choices = enemy_hand + enemy_evolution_deck
			"rally", "cleanse": choices = _response_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c.is_alive())
		if choices.is_empty(): return false
		pending_utility = card
		pending_effect = effect
		if card.get_parent() != hand_container: card.reparent(hand_container, true)
		arrange_hand_centered()
		run_director.choose_card("CHOOSE A TARGET · " + str(card.card_data.name).to_upper(), choices, complete_utility_choice, cancel_utility_choice)
		return true
	consume_utility(card)
	if effect == "draw": draw_cards(2 + int(card.card_data.get("utility_power", 0)))
	elif effect == "scout": run_director.show_intel()
	return true

func consume_utility(card: Node) -> void:
	on_card_played(card)
	preparedness = mini(energy_cap, preparedness + int(card.card_data.get("refund_energy", 0)))
	_refresh_bars()
	card.in_hand = false
	card.remove_from_group("cards")
	card.queue_free()

func complete_utility_choice(target: Variant) -> void:
	if not is_instance_valid(pending_utility): return
	var power := int(pending_utility.card_data.get("utility_power", 0))
	match pending_effect:
		"tutor":
			deck.erase(target)
		"seal": target.locked_until = turn + 2 + power
		"tax":
			for i in range(1 + power): increase_cost(target)
		"rally": target.add_status("strength", 2 + power)
		"cleanse":
			target.cleanse()
			if power > 0: target.heal(2 * power)
	var tutoring := pending_effect == "tutor"
	consume_utility(pending_utility)
	pending_utility = null
	pending_effect = ""
	run_director.action_cancel = Callable()
	run_director.close_modal()
	if tutoring: add_card_to_hand(target)
	_refresh_bars()

func cancel_utility_choice() -> void:
	pending_utility = null
	pending_effect = ""
	run_director.action_cancel = Callable()
	run_director.close_modal()
	arrange_hand_centered()

func increase_cost(definition: Dictionary) -> void:
	if definition.get("type", "response") == "response" or int(definition.get("cost", 0)) > 0:
		definition.cost = int(definition.get("cost", 0)) + 1
	else:
		definition.tension_cost = int(definition.get("tension_cost", 1)) + 1

func enemy_utility(definition: Dictionary) -> void:
	var effect: String = definition.get("effect", "")
	if effect == "seal":
		var choices := get_hand_cards().filter(func(c): return not is_sealed(c.card_data))
		if not choices.is_empty():
			var target = choices.pick_random()
			if encounter_kind in ["elite", "boss"]: target = best_disruption_target(choices, false)
			target.card_data.locked_until = turn + 2
			target._refresh_face()
			target.spawn_popup("SEALED · 2 ROUNDS", Color("da857c"))
		elif not deck.is_empty(): deck.pick_random().locked_until = turn + 2
	elif effect == "tax":
		var choices := get_hand_cards()
		if not choices.is_empty():
			var target = choices.pick_random()
			if encounter_kind in ["elite", "boss"]: target = best_disruption_target(choices, true)
			increase_cost(target.card_data)
			target.refresh_cost()
			target.spawn_popup("COST +1", Color("da857c"))

func best_disruption_target(cards: Array, tax: bool) -> Node:
	var best: Node = cards[0]
	var best_score := -INF
	for card in cards:
		var score: float = card.effective_attack() * 2.0 + float(card.card_data.health) * 0.5
		if card.card_data.get("utility", false): score += 4
		if tax and int(card.card_data.cost) <= preparedness and int(card.card_data.cost) + 1 > preparedness: score += 12
		if score > best_score:
			best_score = score
			best = card
	return best

func _set_phase(p: Phase, text: String = "") -> void:
	phase = p
	$HUD/Root/DeckDrawButton.disabled = p != Phase.PLAYER_DRAW
	if text != "" and _phase_label:
		_phase_label.text = text
	if _end_turn_btn:
		_end_turn_btn.disabled = not (p == Phase.PLAYER_DRAW or p == Phase.PLAYER_PLAY)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func _start_match() -> void:
	_set_phase(Phase.SETUP, "Flipping a coin...")
	draw_cards(STARTING_HAND)
	enemy_draw_cards(STARTING_HAND)
	await _wait(1.0)
	player_first = randf() < 0.5
	_set_phase(Phase.SETUP, "Heads - Response goes first" if player_first else "Tails - Disaster goes first")
	await _wait(1.4)
	_begin_round()

func _begin_round() -> void:
	# A depleted draw pile is still playable while hand or board cards remain.
	if deck.is_empty() and get_hand_cards().is_empty() and _response_slots().all(func(s): return _get_card_in_slot(s) == null):
		_set_phase(Phase.GAME_OVER, "No Response cards remain")
		run_director.battle_finished(false)
		return
	if enemy_deck.is_empty() and enemy_hand.is_empty() and _threat_slots().all(func(s): return _get_card_in_slot(s) == null):
		_set_phase(Phase.GAME_OVER, "The Janitor has no threats left")
		run_director.battle_finished(true)
		return
	if turn % preload("res://scripts/battle_rules.gd").BUFF_INTERVAL == 0 and adapted_round != turn:
		adapted_round = turn
		_set_phase(Phase.SETUP, "Choose your adaptation")
		run_director.show_buff_choices()
		return
	continue_round()

func continue_round() -> void:
	if _turn_label: _turn_label.text = "Turn %d" % turn
	# Response energy refills to the cap (cap grows by 1 each round)
	preparedness = energy_cap
	# Disaster tension refills to the cap (cap grows by 1 each round, starts at 3)
	var bonus := buff_value(false, "energy")
	tension_cap = clampi(TENSION_START + (turn - 1) + bonus, 1, maxi(1, TENSION_MAX + bonus))
	tension = tension_cap
	_refresh_bars()
	player_hp = mini(PLAYER_MAX_HP, player_hp + buff_value(true, "hero_regen"))
	enemy_hp = mini(enemy_max_hp, enemy_hp + buff_value(false, "hero_regen"))
	_refresh_bars()

	# Upkeep phase: Regenerating cards heal 1 HP
	for c in get_tree().get_nodes_in_group("cards"):
		if not c.in_hand: c.status_upkeep()
		else: c._refresh_face()

	# Disaster modifier escalation based on round count (from GDD)
	_apply_round_modifiers()

	if player_first:
		_begin_player_turn()
	else:
		await _enemy_turn()
		if phase != Phase.GAME_OVER:
			_begin_player_turn()

func _apply_round_modifiers() -> void:
	if turn >= 7:
		var threats = _threat_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c.is_alive())
		if not threats.is_empty():
			var target = threats.pick_random()
			var mod_pool = ["armored", "rampaging", "fierce", "regenerating"]
			var picked: String = mod_pool.pick_random()
			if not target.has_modifier(picked):
				target.add_modifier(picked)

func _begin_player_turn() -> void:
	if deck.is_empty() or get_hand_cards().size() >= HAND_SIZE_MAX:
		_set_phase(Phase.PLAYER_PLAY, "Your turn - play cards, then End Turn")
	else:
		_set_phase(Phase.PLAYER_DRAW, "Your turn - draw a card from the deck")

func _on_draw_button_pressed() -> void:
	if run_director and run_director.modal.visible: return
	if phase != Phase.PLAYER_DRAW:
		return
	draw_cards(maxi(0, 1 + buff_value(true, "draw")))
	_set_phase(Phase.PLAYER_PLAY, "Your turn - play cards, then End Turn")

func _on_end_turn_pressed() -> void:
	if run_director and run_director.modal.visible: return
	if phase != Phase.PLAYER_DRAW and phase != Phase.PLAYER_PLAY:
		return
	# Don't end the turn while a card is still in the air
	for c in get_hand_cards():
		if c.is_dragging: return

	if player_first:
		# Player went first -> now the Disaster plays its card
		await _enemy_turn()
		if phase == Phase.GAME_OVER: return
	await _combat()
	if phase == Phase.GAME_OVER: return

	turn += 1
	var bonus := buff_value(true, "energy")
	energy_cap = clampi(energy_cap + maxi(1, 1 + bonus), 1, maxi(1, ENERGY_MAX + bonus))
	player_first = not player_first
	_begin_round()

func _pick_smart_threat_slot(empty_slots: Array, card_data: Dictionary) -> Node3D:
	var elem: String = card_data.get("element", "")
	var best_slot: Node3D = null
	var best_score := -999.0

	for s in empty_slots:
		if encounter_kind in ["elite", "boss"]:
			var tactical := score_threat(card_data, s)
			if tactical > best_score:
				best_score = tactical
				best_slot = s
			continue
		var idx: int = _threat_slots().find(s)
		var score := 0.0
		var opp = _get_card_in_slot(_response_slots()[idx])
		if opp and opp.is_alive():
			var opp_elem: String = opp.card_data.get("element", "")
			var mult: float = TYPE_CHART.get(elem, {}).get(opp_elem, 1.0)
			if mult > 1.0:
				score += 15.0 # Counters opposing response card!
			elif mult == 1.0:
				score += 8.0  # Contests opposing card directly
			else:
				score += 2.0  # Ineffective matchup
		else:
			score += 4.0 # Open lane
		# Slight organic variance
		score += randf() * 2.0
		if score > best_score:
			best_score = score
			best_slot = s

	return best_slot if best_slot else empty_slots.pick_random()

# ------------------------------------------------------------------- enemy
func _enemy_turn() -> void:
	_set_phase(Phase.ENEMY, "Disaster's turn...")
	await _wait(0.5)

	# --- Disaster Draw Phase ---
	if not enemy_deck.is_empty() and enemy_hand.size() < 6:
		enemy_draw_cards(maxi(0, 1 + buff_value(false, "draw")))
		_set_phase(Phase.ENEMY, "Disaster draws a card...")
		await _wait(0.4)

	# --- Disaster Action Phase (Can play multiple cards in one turn!) ---
	var actions_taken := 0
	var max_actions := enemy_action_limit()
	var played_something := true

	while played_something and actions_taken < max_actions and tension > 0:
		played_something = false
		var spells := enemy_hand.filter(func(d): return d.get("utility", false) and not is_sealed(d) and int(d.get("tension_cost", 1)) <= tension)
		if not spells.is_empty():
			var spell: Dictionary = spells.pick_random()
			enemy_hand.erase(spell)
			enemy_utility(spell)
			tension -= int(spell.get("tension_cost", 1))
			_set_phase(Phase.ENEMY, "The Janitor casts %s" % spell.name)
			_refresh_bars()
			played_something = true
			actions_taken += 1
			await _wait(0.5)
			continue

		var active_threats: Array = []
		for s in _threat_slots():
			var c = _get_card_in_slot(s)
			if c and c.is_alive():
				active_threats.append(c)

		var empty_slots: Array = _threat_slots().filter(func(s): return _get_card_in_slot(s) == null)

		# 1. Evolution Attempt (Sacrificing existing cards for higher-tier disaster)
		var evo_candidates := enemy_evolution_deck.filter(func(d): return not is_sealed(d) and int(d.get("cost", 1)) <= active_threats.size())
		var plan: Dictionary = best_evolution_plan(active_threats, evo_candidates)
		# Filling a useful empty lane can outperform replacing an established formation.
		var affordable_bases := enemy_hand.filter(func(d): return int(d.get("cost", 0)) == 0 and not d.get("utility", false) and not is_sealed(d) and int(d.get("tension_cost", 1)) <= tension)
		if not plan.is_empty() and not empty_slots.is_empty() and not affordable_bases.is_empty():
			var base_gain := -INF
			for definition in affordable_bases:
				for slot in empty_slots: base_gain = maxf(base_gain, score_threat(definition, slot))
			if base_gain > float(plan.gain): plan = {}
		var should_evolve := not plan.is_empty()

		if should_evolve and not active_threats.is_empty():
			var evo_card_data: Dictionary = plan.card if not plan.is_empty() else evo_candidates.pick_random()
			enemy_evolution_deck.erase(evo_card_data)
			var sac_count: int = int(evo_card_data.get("cost", 1))

			# Sacrifice lowest health threats first
			active_threats.sort_custom(func(a, b): return a.card_data.health < b.card_data.health)
			var to_sacrifice: Array = plan.sacrifices if not plan.is_empty() else active_threats.slice(0, sac_count)
			var target_slot: Node3D = plan.slot if not plan.is_empty() else to_sacrifice[0].current_slot

			_set_phase(Phase.ENEMY, "Disaster sacrifices %d card(s) to evolve %s!" % [to_sacrifice.size(), evo_card_data.get("name", "Apex Threat")])
			shake_camera(0.08, 0.2)

			for sac_card in to_sacrifice:
				await sac_card.sacrifice_dissolve()

			await _wait(0.3)

			var evo_card = Card3DScene.instantiate()
			add_child(evo_card)
			evo_card.add_to_group("cards")
			evo_card.setup(evo_card_data)
			await evo_card.enter_from_above(target_slot)
			_on_enemy_card_played(evo_card)
			evo_card.spawn_popup("EVOLVED!", Color(1.0, 0.3, 0.1))
			shake_camera(0.12, 0.3)

			tension = maxi(0, tension - 1)
			_refresh_bars()
			played_something = true
			actions_taken += 1
			await _wait(0.5)
			continue

		# 2. Play Base Card Attempt (Into an empty threat slot)
		if not empty_slots.is_empty():
			var card_data_to_play: Dictionary
			var base_in_hand := enemy_hand.filter(func(d): return int(d.get("cost", 0)) == 0 and not d.get("utility", false) and not is_sealed(d) and int(d.get("tension_cost", 1)) <= tension)
			if not base_in_hand.is_empty():
				card_data_to_play = choose_base_threat(base_in_hand, empty_slots)
				enemy_hand.erase(card_data_to_play)
			else:
				break

			update_deck_label()

			var target_slot: Node3D = _pick_smart_threat_slot(empty_slots, card_data_to_play)
			_set_phase(Phase.ENEMY, "Disaster unleashes %s!" % card_data_to_play.get("name", "Threat"))

			var card = Card3DScene.instantiate()
			add_child(card)
			card.add_to_group("cards")
			card.setup(card_data_to_play)

			# Round 4-6 Janitor modifier chance on spawn
			if turn in [4, 5, 6] and randf() < 0.5:
				var mods = ["armored", "rampaging", "fierce", "regenerating"]
				card.add_modifier(mods.pick_random())

			await card.enter_from_above(target_slot)
			_on_enemy_card_played(card)
			shake_camera(0.06, 0.15)

			tension = maxi(0, tension - int(card_data_to_play.get("tension_cost", 1)))
			_refresh_bars()
			played_something = true
			actions_taken += 1
			await _wait(0.5)

	_set_phase(Phase.ENEMY, "Disaster concludes its turn.")
	await _wait(0.4)

func enemy_action_limit() -> int:
	return mini(tension, clampi(3 + buff_value(false, "energy"), 1, 5))

func _on_enemy_card_played(card: Node) -> void:
	if card.card_data.get("effect", "") == "draw": enemy_draw_cards(int(card.card_data.get("draw_count", 1)))
	if int(card.card_data.get("on_play_draw", 0)) > 0: enemy_draw_cards(int(card.card_data.on_play_draw))
	apply_formation_effect(card)
	if card.card_data.get("effect", "") == "move_ally": relocate_enemy_ally(card)

func choose_base_threat(candidates: Array, slots: Array) -> Dictionary:
	if encounter_kind == "battle": return candidates.pick_random()
	var best: Dictionary = candidates[0]
	var value := -INF
	for definition in candidates:
		for slot in slots:
			var score := score_threat(definition, slot)
			if score > value:
				value = score
				best = definition
	return best

func score_threat(definition: Dictionary, slot: Node3D, layout: Dictionary = {}) -> float:
	var lane := _threat_slots().find(slot)
	var opponent = _get_card_in_slot(_response_slots()[lane])
	var element: String = definition.get("element", "")
	var attack := maxi(0, int(definition.get("attack", 0)) + int(definition.get("strength", 0)) + buff_value(false, "strength"))
	var health := maxi(1, int(definition.get("health", 1)) + buff_value(false, "health"))
	if definition.has("evaluated_attack"): attack = int(definition.evaluated_attack)
	if definition.has("evaluated_health"): health = int(definition.evaluated_health)
	var slow: bool = definition_has_modifier(definition, "sluggish") or buff_value(false, "sluggish") > 0
	var pierce: bool = definition_has_modifier(definition, "piercing") or buff_value(false, "piercing") > 0
	var score := health * 0.45 + attack * (0.8 if slow else 1.3)
	var condition_target: Variant = opponent
	var condition_source: Variant = definition.get("evaluated_statuses", {"strength":int(definition.get("strength", 0))})
	if condition_met(definition.get("condition", {}), condition_source, condition_target): attack += int(definition.condition.get("bonus", 0))
	if opponent and status_stacks(opponent, "any") >= 3: attack += int(definition.get("status_bonus", 0))
	var strikes := 2 if condition_met(definition.get("condition", {}), condition_source, condition_target) and int(definition.condition.get("strikes", 1)) > 1 else 1
	var can_strike := true
	var hero_damage := attack + (2 if definition_has_modifier(definition, "fierce") else 0)
	if opponent and opponent.is_alive():
		var mult: float = TYPE_CHART.get(element, {}).get(opponent.card_data.element, 1.0)
		var dealt: int = opponent.adjusted_damage(maxi(1, int(attack * mult)))
		var incoming := maxi(1, int(opponent.effective_attack() * float(TYPE_CHART.get(opponent.card_data.element, {}).get(element, 1.0))))
		if definition_has_modifier(definition, "armored"): incoming = maxi(1, incoming - int(definition.get("armor_value", 1)))
		can_strike = not player_first or incoming < health
		score += minf(dealt, opponent.card_data.health) * (1.7 if can_strike else 0.2)
		if dealt >= opponent.card_data.health and can_strike: score += 8
		if not can_strike: score -= 12 # A dead blocker cannot counterattack.
		else: score += 3
		if enemy_hp <= opponent.effective_attack() + 2: score += 15 # Cover potentially lethal lanes.
		for status in definition.get("on_hit", {}): score += int(definition.on_hit[status]) * 0.5
	else:
		score += attack * 1.6
		if hero_damage * strikes >= player_hp: score += 50
	if pierce and can_strike:
		score += attack * 1.2
		if hero_damage * strikes >= player_hp: score += 70
	for neighbor in [lane - 1, lane + 1]:
		if neighbor < 0 or neighbor > 3: continue
		var neighbor_slot: Node3D = _threat_slots()[neighbor]
		var ally = _get_card_in_slot(neighbor_slot)
		var adjacent: Dictionary = layout.get(neighbor_slot, {}) if not layout.is_empty() else (ally.card_data if ally else {})
		if not adjacent.is_empty() and adjacent.element == element: score += 3 + buff_value(false, "synergy")
	if strikes > 1 and can_strike: score += attack * 2.0
	if int(definition.get("on_play_draw", 0)) > 0: score += 2 * int(definition.on_play_draw)
	if definition.get("effect", "") == "draw": score += 3
	if definition.get("effect", "") in ["heal_all", "rally_all"]: score += 2
	return score

func definition_has_modifier(definition: Dictionary, modifier: String) -> bool:
	return definition.get("modifier", "") == modifier or modifier in definition.get("modifiers", [])

func live_ai_definition(card: Node) -> Dictionary:
	var data: Dictionary = card.card_data.duplicate(true)
	data.evaluated_attack = card.effective_attack()
	data.evaluated_health = int(card.card_data.health)
	data.evaluated_statuses = card.statuses.duplicate()
	data.modifiers = card.modifiers.duplicate()
	return data

func board_score(layout: Dictionary) -> float:
	var value := 0.0
	for slot in _threat_slots():
		var definition: Dictionary = layout.get(slot, {})
		if not definition.is_empty(): value += score_threat(definition, slot, layout)
		else:
			var response = _get_card_in_slot(_response_slots()[_threat_slots().find(slot)])
			if response and response.is_alive() and response.can_attack(turn):
				var damage: int = response.effective_attack() + _synergy_bonus(response)
				value -= damage * (5.0 if enemy_hp <= damage else 1.8)
	return value

func best_evolution_plan(active: Array, candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_gain := 1.0
	var before: Dictionary = {}
	for card in active: before[card.current_slot] = live_ai_definition(card)
	var baseline := board_score(before)
	var opposition := _response_slots().filter(func(slot): return _get_card_in_slot(slot) != null).size()
	for definition in candidates:
		var cost := int(definition.cost)
		if cost < 1 or cost > active.size(): continue
		for mask in range(1, 1 << active.size()):
			var sacrifices: Array = []
			for i in active.size():
				if mask & (1 << i): sacrifices.append(active[i])
			if sacrifices.size() != cost: continue
			for target in sacrifices:
				var after: Dictionary = before.duplicate(true)
				for sacrificed in sacrifices: after.erase(sacrificed.current_slot)
				after[target.current_slot] = definition
				var gain := board_score(after) - baseline
				# Board presence buys blockers, future sacrifices and formation bonuses.
				# Charge more for losing a numerical advantage, unless a lethal attack wins now.
				var lost := cost - 1
				gain -= lost * (5.0 if active.size() > opposition else 2.0)
				if active.size() > opposition and after.size() <= opposition and lost > 0: gain -= 6
				if gain > best_gain:
					best_gain = gain
					best = {"card":definition, "slot":target.current_slot, "sacrifices":sacrifices, "gain":gain}
	return best

func relocate_enemy_ally(source: Node) -> void:
	var best_ally: Node
	var best_slot: Node3D
	var gain := 1.0
	var empty := _threat_slots().filter(func(s): return _get_card_in_slot(s) == null)
	for slot in _threat_slots():
		var ally = _get_card_in_slot(slot)
		if ally == null or ally == source: continue
		for destination in empty:
			var value := score_threat(ally.card_data, destination) - score_threat(ally.card_data, slot)
			if value > gain:
				gain = value
				best_ally = ally
				best_slot = destination
	if best_ally: best_ally.place_on_slot(best_slot)

func choose_ai_buff(options: Array) -> Dictionary:
	if encounter_kind == "battle": return options.pick_random()
	var best: Dictionary = options[0]
	var best_score := -INF
	var deck_view: Array = enemy_deck + enemy_hand + enemy_evolution_deck
	for slot in _threat_slots():
		var card = _get_card_in_slot(slot)
		if card: deck_view.append(card.card_data)
	for option in options:
		var bonus: Dictionary = preload("res://scripts/battle_rules.gd").totals({option.id:1}, {})
		var score := float(bonus.get("strength", 0)) * 3 + float(bonus.get("health", 0)) * 2 + float(bonus.get("energy", 0)) * 2 + float(bonus.get("draw", 0)) * 2
		for definition in deck_view:
			for status in ["burn", "poison", "bleed"]:
				if definition.get("on_hit", {}).has(status): score += float(bonus.get(status, 0)) * 1.5
		score += float(bonus.get("piercing", 0)) * 5 + float(bonus.get("regen", 0)) - float(bonus.get("self_bleed", 0)) * 3 - float(bonus.get("sluggish", 0)) * 3
		if score > best_score:
			best_score = score
			best = option
	return best

# ------------------------------------------------------------------- combat
const TYPE_CHART := {
	# Response attacking Disaster
	"evac": {"earthquake": 2.0, "flood": 0.5},
	"douse": {"fire": 2.0, "typhoon": 0.5},
	"clearance": {"flood": 2.0, "earthquake": 0.5},
	"brace": {"typhoon": 2.0, "fire": 0.5},
	# Disaster attacking Response
	"flood": {"evac": 2.0, "clearance": 0.5},
	"earthquake": {"clearance": 2.0, "evac": 0.5},
	"typhoon": {"douse": 2.0, "brace": 0.5},
	"fire": {"brace": 2.0, "douse": 0.5},
}

func _threat_slots() -> Array:
	return [$Slots/ThreatBoard_Slot1, $Slots/ThreatBoard_Slot2, $Slots/ThreatBoard_Slot3, $Slots/ThreatBoard_Slot4]

func _response_slots() -> Array:
	return [$Slots/ResponseBoard_Slot1, $Slots/ResponseBoard_Slot2, $Slots/ResponseBoard_Slot3, $Slots/ResponseBoard_Slot4]

func _get_card_in_slot(slot: Node3D) -> Node:
	for c in get_tree().get_nodes_in_group("cards"):
		if is_instance_valid(c) and c.current_slot == slot:
			return c
	return null

func _calc_damage(attacker: Node, defender: Node) -> Dictionary:
	var base: int = attacker.effective_attack() + conditional_attack_bonus(attacker, defender)
	var atk_elem: String = attacker.card_data.get("element", "")
	var def_elem: String = defender.card_data.get("element", "")
	var mult: float = TYPE_CHART.get(atk_elem, {}).get(def_elem, 1.0)
	var dmg: int = maxi(1, int(base * mult))
	dmg += _synergy_bonus(attacker)
	if attacker.has_modifier("rampaging") and ((attacker.card_data.type == "response") != player_first): dmg += 1
	return {"dmg": dmg, "mult": mult}

func _synergy_bonus(card: Node) -> int:
	var slots := _response_slots() if card.card_data.type == "response" else _threat_slots()
	var index: int = slots.find(card.current_slot)
	for neighbor in [index - 1, index + 1]:
		if neighbor >= 0 and neighbor < slots.size():
			var ally = _get_card_in_slot(slots[neighbor])
			if ally and ally.is_alive() and ally.card_data.element == card.card_data.element: return 1 + int(buffs_for(card.card_data).get("synergy", 0))
	return 0

func _combat() -> void:
	var prev_view: bool = in_board_view
	set_board_view(true)
	set_hand_tucked(true)
	_set_phase(Phase.COMBAT, "Combat Phase!")
	await _wait(0.65)

	# The side that played first this round attacks first
	if player_first:
		await _side_attacks(true)
		if phase != Phase.GAME_OVER:
			await _side_attacks(false)
	else:
		await _side_attacks(false)
		if phase != Phase.GAME_OVER:
			await _side_attacks(true)

	if phase != Phase.GAME_OVER:
		await _wait(0.5)
		set_board_view(prev_view)
		await _wait(0.6)

## response_side = true -> the player's row attacks the Disaster row.
func _side_attacks(response_side: bool) -> void:
	var mine := _response_slots() if response_side else _threat_slots()
	var theirs := _threat_slots() if response_side else _response_slots()
	for i in range(4):
		var atk = _get_card_in_slot(mine[i])
		if atk == null or not atk.is_alive() or atk.effective_attack() <= 0:
			continue
		if not atk.can_attack(turn):
			atk.spawn_popup("SLUGGISH · RESTING", Color("9cacb9"))
			continue

		var def = _get_card_in_slot(theirs[i])
		var target_pos: Vector3
		if def and def.is_alive():
			target_pos = def.global_position
		else:
			target_pos = mine[i].global_position + Vector3(0, 0, -2.4 if response_side else 2.4)

		# Dramatic wind-up and lunge strike
		await atk.attack_lunge(target_pos)

		resolve_attack(atk, def, response_side)
		if phase == Phase.GAME_OVER: return
		await _wait(0.4)

func status_stacks(subject: Variant, status: String) -> int:
	if subject == null: return 0
	var values: Dictionary = subject if subject is Dictionary else subject.statuses
	if status != "any": return int(values.get(status, 0))
	return int(values.get("burn", 0)) + int(values.get("poison", 0)) + int(values.get("bleed", 0))

func condition_met(condition: Dictionary, source: Variant, target: Variant) -> bool:
	if condition.is_empty(): return false
	var subject: Variant = source if condition.get("subject", "target") == "self" else target
	return subject != null and status_stacks(subject, str(condition.get("status", "any"))) >= int(condition.get("threshold", 3))

func conditional_attack_bonus(attacker: Node, defender: Node) -> int:
	var condition: Dictionary = attacker.card_data.get("condition", {})
	var amount := int(condition.get("bonus", 0)) if condition_met(condition, attacker, defender) else 0
	if defender != null and status_stacks(defender, "any") >= 3: amount += int(attacker.card_data.get("status_bonus", 0))
	return amount

func attack_strikes(attacker: Node, defender: Node) -> int:
	var condition: Dictionary = attacker.card_data.get("condition", {})
	return 2 if condition_met(condition, attacker, defender) and int(condition.get("strikes", 1)) > 1 else 1

func resolve_attack(atk: Node, defender: Node, response_side: bool) -> void:
	if not atk.can_attack(turn): return
	var strikes := attack_strikes(atk, defender)
	for strike in range(strikes):
		if not atk.is_alive() or phase == Phase.GAME_OVER: break
		if strike > 0: atk.spawn_popup("FOLLOW-UP STRIKE", Color("75d6c6"))
		resolve_single_strike(atk, defender, response_side)

func resolve_single_strike(atk: Node, defender: Node, response_side: bool) -> void:
	var blocked: bool = defender != null and defender.is_alive()
	if blocked:
		var info := _calc_damage(atk, defender)
		defender.take_damage(info.dmg, info.mult)
		# Effects land only on a surviving card. Normal damage never spills into HP.
		if defender.is_alive():
			var inflicted: Dictionary = atk.card_data.get("on_hit", {})
			var buffs := buffs_for(atk.card_data)
			for status in inflicted:
				var extra := int(buffs.get(status, 0)) * (2 if status == "burn" else 1)
				defender.add_status(status, int(inflicted[status]) + extra)
		shake_camera(0.08, 0.2)
	if not blocked or atk.has_modifier("piercing"):
		var direct: int = atk.effective_attack() + _synergy_bonus(atk) + conditional_attack_bonus(atk, defender if blocked else null)
		if atk.has_modifier("fierce"): direct += 2
		_damage_side(not response_side, direct)
	if int(atk.card_data.get("leech", 0)) > 0: atk.heal(int(atk.card_data.leech))
	if blocked and defender.is_alive():
		var thorns := int(buffs_for(defender.card_data).get("thorns", 0)) + int(defender.card_data.get("thorns", 0))
		if thorns > 0: atk.take_damage(thorns, 1.0, true)
	atk.after_attack(turn)
	_check_game_over()

func _check_game_over() -> bool:
	if player_hp <= 0:
		_set_phase(Phase.GAME_OVER, "The disaster overwhelms you... (Defeat)")
		run_director.battle_finished(false)
		return true
	if enemy_hp <= 0:
		_set_phase(Phase.GAME_OVER, "Disaster contained! (Victory)")
		run_director.battle_finished(true)
		return true
	return false
