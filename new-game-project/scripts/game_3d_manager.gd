extends Node3D
const BattleEngine = preload("res://scripts/battle_engine.gd")
const BattleQueries = preload("res://scripts/battle_query_adapter.gd")
const UI = preload("res://scripts/ui_theme.gd")
## Main game manager: builds the creepy classroom, the pixel-art board,
## the gothic HUD, and controls the deck + fanned card hand.

const Card3DScene = preload("res://scenes/card_3d.tscn")

const HAND_SIZE_MAX := 8
const HAND_DIST := 3.0        # Smaller hand leaves space for the board and HUD.
const HAND_Y := -0.86
const DRAG_BOUNDS := Rect2(-2.45, -1.8, 4.9, 3.6)
const UPRIGHT := Basis(Vector3.RIGHT, PI / 2.0)

# Palette
const BONE := UI.TEXT
const GOLD := UI.GOLD
const INK := UI.INSET

var deck: Array[Dictionary] = []
var enemy_deck: Array[Dictionary] = []
var enemy_evolution_deck: Array[Dictionary] = []
var enemy_hand: Array[Dictionary] = []
var hand: Array = []
var player_graveyard: Array[Dictionary] = []
var graveyard_serial := 0
var hovered_hand_card: Node
var dragged_hand_card: Node
var turn := 1
var presentation: Node
var coin_result := -1
var coin_pick := -1
var encounter_serial := 0
enum View { WIDE, DESK, BOARD }
var view_mode: View = View.DESK
var in_board_view := false
const BOARD_SCALE := 0.7
const HAND_SCALE := 0.62
var run_director: CanvasLayer
var enemy_max_hp := ENEMY_MAX_HP
var camera_tween: Tween
var player_buffs: Dictionary = {}
var enemy_buffs: Dictionary = {}
var player_run_buffs: Dictionary = {}
var enemy_run_buffs: Dictionary = {}
var encounter_kind := "battle"
var final_boss: Node
var player_barrier := 0
var plans: Node
var battle_log: Array[String] = []
var moving_source: Node
var board_input: Node
var opponent_hand: Node3D
var plan_hero_barrier := 0
var moving_ally: Node
var adapted_round := 0
var pending_utility: Node
var pending_effect := ""

# ---- Turn system -------------------------------------------------------
enum Phase { SETUP, PLAYER_DRAW, PLAYER_PLAY, ENEMY, COMBAT, GAME_OVER }
const STARTING_HAND := 3
const ENERGY_START := 3
const ENERGY_MAX := 7
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
const DESK_VIEW := {"pos": Vector3(0, 0.3, -0.4), "rot": Vector3(-38, 0, 0), "dist": 5.3, "fov":60.0}
const WIDE_VIEW := {"pos": Vector3(-0.8, 2.4, -1.0), "rot": Vector3(-12, -12, 0), "dist":10.0, "fov":68.0}
const BOARD_VIEW := {"pos": Vector3(0, 1.0, 0.0), "rot": Vector3(-90, 0, 0), "dist": 3.8, "fov":56.0}

# HUD references
@onready var _deck_count: Label = $HUD/Root/DeckDrawButton/DeckCountLabel
@onready var _turn_label: Label = $HUD/Root/TurnPlaque/TurnLabel
@onready var _hint_w: Label = $HUD/Root/HintW
@onready var _hint_s: Label = $HUD/Root/HintS
@onready var _phase_label: Label = $HUD/Root/PhaseLabel
@onready var _end_turn_btn: Button = $HUD/Root/EndTurnButton

@onready var _player_hp_ui: Control = $HUD/Root/PlayerHealth
@onready var _enemy_hp_ui: Control = $HUD/Root/EnemyHealth

var hand_container: Node3D
var is_hand_tucked := false
var hand_tuck_tween: Tween

@onready var camera: Camera3D = $CameraPivot/Camera3D

func _ready() -> void:
	presentation = preload("res://scripts/game_presentation.gd").new()
	add_child(presentation)
	presentation.setup(self)
	# Enable temporal smoothing only on the renderer that supports it.
	get_viewport().use_taa = RenderingServer.get_current_rendering_method() == "forward_plus"
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().scaling_3d_scale = 1.0
	_build_visual_finish()
	plans = preload("res://scripts/contingency_rules.gd").new()
	add_child(plans)
	plans.setup(self)
	hand_container = Node3D.new()
	camera.add_child(hand_container)
	_apply_view(DESK_VIEW)

	var vp := get_viewport()
	vp.physics_object_picking = true
	vp.physics_object_picking_sort = true
	vp.physics_object_picking_first_only = true

	_build_environment()
	_build_board()
	board_input = preload("res://scripts/board_actions.gd").new()
	add_child(board_input)
	board_input.setup(self)
	opponent_hand = preload("res://scripts/enemy_hand_display.gd").new()
	add_child(opponent_hand)
	opponent_hand.setup(self)
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
	encounter_serial += 1
	if is_instance_valid(presentation): presentation.cancel_coin()
	if is_instance_valid(board_input): board_input.clear()
	if is_instance_valid(plans): plans.reset()
	if not preserve_result: battle_log.clear()
	moving_source = null
	if is_instance_valid(final_boss): final_boss.queue_free()
	final_boss = null
	player_barrier = 0
	clear_hand_hover()
	dragged_hand_card = null
	if not preserve_result:
		player_graveyard.clear()
		graveyard_serial = 0
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

func log_event(message: String) -> void:
	battle_log.append("Round %d | %s" % [turn, message])
	if battle_log.size() > 300: battle_log.pop_front()

func overclock_stacks(response_side: bool) -> int:
	return BattleEngine.overclock_stacks(BattleQueries.context(self), response_side)

func resource_growth(response_side: bool) -> int:
	return BattleEngine.resource_growth(BattleQueries.context(self), response_side)

func hero_max_hp() -> int:
	return PLAYER_MAX_HP

func incoming_damage(response_side: bool, amount: int) -> int:
	return BattleEngine.incoming_damage(BattleQueries.context(self), response_side, amount)

func start_encounter(collection: Array[Dictionary], kind: String, floor_level: int, specialty: int) -> void:
	clear_battle()
	encounter_kind = kind
	run_director.intel_revealed = false
	turn = 1
	log_event("Encounter begins: %s, floor %d." % [kind.capitalize(), floor_level])
	energy_cap = maxi(1, ENERGY_START + buff_value(true, "energy"))
	preparedness = energy_cap
	plans.tokens = mini(2, maxi(0, buff_value(true, "plan_start")))
	tension_cap = maxi(1, TENSION_START + buff_value(false, "energy"))
	tension = tension_cap
	enemy_max_hp = 18 + (floor_level - 1) * 2 if kind == "battle" else 20 + (floor_level - 1) * 3 + (4 if kind == "elite" else 8)
	enemy_hp = enemy_max_hp
	for definition in collection: deck.append(definition.duplicate(true))
	var threats: Array[Dictionary] = []
	load_deck_from_json("res://data/disaster_deck.json", threats)
	load_deck_from_json("res://data/disaster_expansion.json", threats)
	var favored: String = ["fire", "earthquake", "flood", "typhoon"][specialty]
	_enemy_hp_ui.get_node("Caption").text = "JANITOR / %s / %s" % [kind.to_upper(), favored.to_upper()]
	_enemy_hp_ui.get_node("Caption").add_theme_font_size_override("font_size", 14)
	for definition in threats:
		if kind == "elite" and definition.element != favored: continue
		var c: Dictionary = definition.duplicate(true)
		var cheap: bool = int(c.cost) == 1 or (int(c.cost) == 0 and int(c.get("tension_cost", 1)) <= 1)
		if not c.get("utility", false) and not cheap:
			c.attack = int(c.attack) + (floor_level - 1) + (1 if kind == "boss" else 0)
			c.health = int(c.health) + (1 if kind in ["elite", "boss"] else 0)
		if int(c.cost) > 0:
			if kind != "battle" or int(c.cost) <= 2: enemy_evolution_deck.append(c)
		else:
			enemy_deck.append(c)
			if c.element == favored: enemy_deck.append(c.duplicate(true))
	# Keep the reserves small so fights don't drag on.
	var base_limit := 18 if kind == "battle" else (21 if kind == "elite" else 22)
	var evolution_limit := 8 if kind == "battle" else (13 if kind == "elite" else 14)
	if kind == "elite":
		fill_elite_reserve(enemy_deck, base_limit)
		fill_elite_reserve(enemy_evolution_deck, evolution_limit)
	enemy_deck.shuffle()
	enemy_deck.sort_custom(func(a, b): return a.element == favored and b.element != favored)
	enemy_deck.resize(mini(base_limit, enemy_deck.size()))
	if kind == "battle" and floor_level <= 2: limit_early_specials(floor_level)
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
	if kind == "boss" and floor_level == 3:
		final_boss = preload("res://scripts/final_boss.gd").new()
		add_child(final_boss)
		final_boss.setup(self)
		_enemy_hp_ui.get_node("Caption").text = "MIDNIGHT WARDEN / FINAL BOSS"
	_start_match()

func fill_elite_reserve(reserve: Array[Dictionary], limit: int) -> void:
	var theme := reserve.duplicate(true)
	if theme.is_empty(): return
	var index := 0
	while reserve.size() < limit:
		reserve.append(theme[index % theme.size()].duplicate(true))
		index += 1

func has_special_effect(definition: Dictionary) -> bool:
	for key in ["utility", "effect", "modifier", "modifiers", "on_hit", "on_sacrifice", "condition", "strength", "leech", "on_play_draw", "ignore_taunt"]:
		if definition.get(key): return true
	return false

func limit_early_specials(floor_level: int) -> void:
	var basic := enemy_deck.filter(func(card): return not has_special_effect(card))
	if basic.is_empty(): return
	var limit := 2 if floor_level == 1 else 4
	var selected: Array[Dictionary] = []
	var specials := 0
	for card in enemy_deck:
		if has_special_effect(card):
			if specials >= limit: continue
			specials += 1
		selected.append(card)
	while selected.size() < enemy_deck.size(): selected.append(basic.pick_random().duplicate(true))
	enemy_deck.assign(selected)

func _load_tex(path: String) -> Texture2D:
	var tex = load(path)
	if tex: return tex
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(img)
	return null

# =================================================================== ENVIRONMENT
func _build_environment() -> void:
	var school := preload("res://scripts/supplied_classroom.gd").new()
	add_child(school)

# =================================================================== BOARD
## The framed slate aligns with the existing slot colliders.
func _build_board() -> void:
	for slot in $Slots.get_children():
		slot.position.x *= BOARD_SCALE
		slot.position.z *= BOARD_SCALE
		slot.scale = Vector3(BOARD_SCALE, 1, BOARD_SCALE)
	add_child(preload("res://scripts/card_playmat.gd").new())

# =================================================================== LIGHTING
func _build_lighting() -> void:
	var env_node = get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("9fa8af")
		env.ambient_light_energy = 0.24
		# Preserve the supplied metallic lockers' colour with soft environment
		# reflections, while the visible background and diffuse room stay dark.
		var reflection_sky := Sky.new()
		var reflection_material := ProceduralSkyMaterial.new()
		reflection_material.sky_top_color = Color(.55, .59, .64)
		reflection_material.sky_horizon_color = Color(.61, .63, .65)
		reflection_material.ground_horizon_color = Color(.36, .38, .39)
		reflection_material.ground_bottom_color = Color(.27, .28, .29)
		reflection_sky.sky_material = reflection_material
		env.sky = reflection_sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.04
		env.adjustment_saturation = 0.82
		var enhanced := RenderingServer.get_current_rendering_method() == "forward_plus"
		env.ssao_enabled = enhanced
		env.ssao_radius = 0.65
		env.ssao_intensity = 1.3
		env.ssao_power = 1.15
		env.ssao_detail = 0.8
		env.ssil_enabled = enhanced
		env.ssil_radius = 3.0
		env.ssil_intensity = 0.65
		env.volumetric_fog_enabled = enhanced
		env.volumetric_fog_density = 0.002
		env.volumetric_fog_albedo = Color("b4b4a3")
		env.volumetric_fog_anisotropy = 0.55
		env.glow_enabled = enhanced
		env.glow_intensity = 0.65
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.2
		env.glow_hdr_scale = 1.4
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level in 7: env.set_glow_level(level, [0.8, 0.65, 0.4, 0.2, 0.1, 0.0, 0.0][level])

func _build_visual_finish() -> void:
	# Only color-grade the 3D world, not the HUD.
	var layer := CanvasLayer.new()
	layer.name = "ClassroomFinish"
	layer.layer = 0
	add_child(layer)
	var effect := ColorRect.new()
	effect.name = "ClarityAndSharpness"
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/classroom_finish.gdshader")
	effect.material = material
	layer.add_child(effect)

func _refresh_bars() -> void:
	_set_health(_player_hp_ui, player_hp, hero_max_hp(), false)
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
func _damage_side(player_side: bool, amt: int, bypass_barrier: bool = false) -> void:
	if not bypass_barrier: amt = incoming_damage(player_side, amt)
	if player_side and plan_hero_barrier > 0 and not bypass_barrier:
		var protected := mini(plan_hero_barrier, amt)
		plan_hero_barrier -= protected
		amt -= protected
		log_event("Emergency Shelter blocks %d hero damage." % protected)
	if player_side and player_barrier > 0 and not bypass_barrier:
		var absorbed := mini(player_barrier, amt)
		player_barrier -= absorbed
		amt -= absorbed
	if not player_side and is_instance_valid(final_boss): amt = final_boss.accept_damage(amt)
	if amt <= 0: return
	var ui := _player_hp_ui if player_side else _enemy_hp_ui
	if player_side:
		player_hp = maxi(0, player_hp - amt)
		log_event("Response loses %d health (%d/%d)." % [amt, player_hp, hero_max_hp()])
		_set_health(ui, player_hp, hero_max_hp(), true)
	else:
		enemy_hp = maxi(0, enemy_hp - amt)
		log_event("Disaster loses %d health (%d/%d)." % [amt, enemy_hp, enemy_max_hp])
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
	l.add_theme_color_override("font_color", UI.DANGER)
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

func enemy_draw_cards(count: int) -> void:
	for i in range(count):
		if enemy_hand.size() >= 6: break
		var available := enemy_deck.filter(func(c): return not is_sealed(c))
		if available.is_empty(): break
		var picked: Dictionary = available.back()
		enemy_deck.erase(picked)
		enemy_hand.append(picked)
		log_event("Disaster draws a card.")
	update_deck_label()

func enemy_draw_evolutions(count: int) -> void:
	for i in range(count):
		if enemy_hand.size() >= 5 or enemy_evolution_deck.is_empty() or enemy_hand.filter(func(card): return int(card.get("cost", 0)) > 0).size() >= 2: break
		enemy_hand.append(enemy_evolution_deck.pop_back())
		log_event("Disaster draws an evolution into its hand.")

func _refresh_view_hints() -> void:
	if _hint_w:
		_hint_w.text = "W · " + ("Table view" if view_mode == View.WIDE else "Overhead view")
		_hint_w.modulate.a = 0.35 if view_mode == View.BOARD else 0.9
	if _hint_s:
		_hint_s.text = "S · " + ("Table view" if view_mode == View.BOARD else "Wide view")
		_hint_s.modulate.a = 0.35 if view_mode == View.WIDE else 0.9

# W and S move one step through Room <-> Table <-> Overhead.
func _unhandled_key_input(event: InputEvent) -> void:
	if presentation.blocking: return
	if run_director and (run_director.modal.visible or not run_director.battle_active): return
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	if event.keycode == KEY_SPACE:
		_on_end_turn_pressed()
		return
	if phase == Phase.COMBAT or is_instance_valid(dragged_hand_card) or not board_input.action.is_empty(): return
	if event.keycode == KEY_W: step_view(1)
	elif event.keycode == KEY_S: step_view(-1)

func view_settings(mode: int) -> Dictionary:
	return [WIDE_VIEW, DESK_VIEW, BOARD_VIEW][clampi(mode, View.WIDE, View.BOARD)]

func step_view(direction: int) -> void:
	set_view(clampi(int(view_mode) + direction, View.WIDE, View.BOARD))

func set_view(mode: int) -> void:
	view_mode = clampi(mode, View.WIDE, View.BOARD) as View
	in_board_view = view_mode == View.BOARD
	clear_hand_hover()
	_shift_camera(view_settings(view_mode))
	_refresh_view_hints()

func set_board_view(on: bool) -> void:
	set_view(View.BOARD if on else View.DESK)

func _apply_view(v: Dictionary) -> void:
	$CameraPivot.position = v.pos
	$CameraPivot.rotation_degrees = v.rot
	camera.position = Vector3(0, 0, v.dist)
	camera.rotation = Vector3.ZERO
	camera.fov = float(v.get("fov", 55.0))

func _shift_camera(v: Dictionary, dur: float = 0.55) -> void:
	var pivot = $CameraPivot
	if camera_tween: camera_tween.kill()
	var tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	camera_tween = tween
	tween.tween_property(pivot, "position", v.pos, dur)
	tween.tween_property(pivot, "rotation_degrees", v.rot, dur)
	tween.tween_property(camera, "position", Vector3(0, 0, v.dist), dur)
	tween.tween_property(camera, "rotation", Vector3.ZERO, dur)
	tween.tween_property(camera, "fov", float(v.get("fov", 55.0)), dur)

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
				preload("res://scripts/battle_rules.gd").remove_utility_stats(card)
				target_deck.append(card)

func hand_parent() -> Node3D:
	return hand_container

func clamp_drag_position(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, DRAG_BOUNDS.position.x, DRAG_BOUNDS.end.x), 1.6, clampf(point.z, DRAG_BOUNDS.position.y, DRAG_BOUNDS.end.y))

func _process(_delta: float) -> void:
	if is_instance_valid(opponent_hand): opponent_hand.refresh()
	update_hand_hover(get_viewport().get_mouse_position())
	if phase == Phase.COMBAT:
		if not is_hand_tucked:
			set_hand_tucked(true)
		return

	if view_mode == View.WIDE:
		if not is_hand_tucked: set_hand_tucked(true)
		return
	if in_board_view:
		if not is_hand_tucked: set_hand_tucked(true)
	else:
		if is_hand_tucked:
			set_hand_tucked(false)

func set_hand_tucked(tucked: bool) -> void:
	is_hand_tucked = tucked
	if hand_tuck_tween: hand_tuck_tween.kill()
	hand_tuck_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Move the container down 1.6 to hide it off-screen
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
	log_event("Response receives %s." % definition.get("name", "a card"))
	var card = Card3DScene.instantiate()
	hand_container.add_child(card)
	card.add_to_group("cards")
	card.setup(definition)
	card.position = Vector3(2.6, -0.6, -HAND_DIST)
	card.transform.basis = UPRIGHT.scaled(Vector3.ONE * HAND_SCALE)
	hand.append(card)
	arrange_hand_centered()
	update_deck_label()

func is_sealed(definition: Dictionary) -> bool:
	return BattleEngine.is_sealed(definition, turn)

func buffs_for(definition: Dictionary) -> Dictionary:
	return BattleEngine.buffs_for(BattleQueries.context(self), definition)

func buff_value(response: bool, id: String) -> int:
	return BattleEngine.buff_value(BattleQueries.context(self), response, id)

func attack_bonus(card: Node) -> int:
	return BattleEngine.attack_bonus(BattleQueries.context(self), BattleQueries.card(self, card))

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
		if health_delta < 0 and card.current_slot != null:
			var excluded: Dictionary = card.card_data.get("excluded_buffs", {}).duplicate()
			excluded[id] = int(excluded.get(id, 0)) + 1
			card.card_data.excluded_buffs = excluded
			card._refresh_face()
			continue
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

func hand_position_below_slots(card: Node, pos: Vector3, card_basis: Basis) -> Vector3:
	if view_mode != View.DESK: return pos
	var bottom := 0.0
	for slot in _response_slots() + _threat_slots():
		var bounds: AABB = slot.get_aabb()
		for x in [bounds.position.x, bounds.end.x]:
			for z in [bounds.position.z, bounds.end.z]:
				bottom = maxf(bottom, camera.unproject_position(slot.to_global(Vector3(x, 0, z))).y)
	var card_transform := hand_container.global_transform * Transform3D(card_basis.scaled(Vector3.ONE * HAND_SCALE), pos)
	var top := INF
	for x in [-0.55, 0.55]:
		for z in [-card.card_height / 2, card.card_height / 2]:
			top = minf(top, camera.unproject_position(card_transform * Vector3(x, 0, z)).y)
	if top < bottom + 10:
		var origin := hand_container.to_global(pos)
		var lower := hand_container.to_global(pos + Vector3.DOWN)
		var pixels_per_unit := camera.unproject_position(lower).y - camera.unproject_position(origin).y
		if pixels_per_unit > 0: pos.y -= (bottom + 10 - top) / pixels_per_unit
	return pos

func hand_card_polygon(card: Node, resting: bool) -> PackedVector2Array:
	var card_transform: Transform3D = card.global_transform
	if resting:
		var card_basis: Basis = card.get_meta("hand_basis")
		card_transform = hand_container.global_transform * Transform3D(
			card_basis.scaled(Vector3.ONE * HAND_SCALE), card.get_meta("hand_pos"))
	var polygon := PackedVector2Array()
	for corner in [Vector3(-0.55, 0, -card.card_height / 2), Vector3(0.55, 0, -card.card_height / 2), Vector3(0.55, 0, card.card_height / 2), Vector3(-0.55, 0, card.card_height / 2)]:
		polygon.append(camera.unproject_position(card_transform * corner))
	return polygon

func card_at_hand_position(mouse: Vector2) -> Node:
	# Keep the raised card clickable wherever its visible face is drawn.
	if is_instance_valid(hovered_hand_card) and hovered_hand_card.in_hand and not hovered_hand_card.is_dragging:
		if Geometry2D.is_point_in_polygon(mouse, hand_card_polygon(hovered_hand_card, false)): return hovered_hand_card
	# Resting footprints prevent the lift itself from removing the hover target.
	var cards := get_hand_cards()
	cards.reverse()
	for card in cards:
		if card.is_dragging or not card.has_meta("hand_pos"): continue
		if Geometry2D.is_point_in_polygon(mouse, hand_card_polygon(card, true)): return card
	return null

func clear_hand_hover() -> void:
	hovered_hand_card = null
	for card in get_hand_cards(): card.set_hand_hover(false)

func update_hand_hover(mouse: Vector2) -> void:
	if view_mode != View.DESK:
		clear_hand_hover()
		return
	if not board_input.action.is_empty() or is_instance_valid(dragged_hand_card) or phase not in [Phase.PLAYER_DRAW, Phase.PLAYER_PLAY] or (run_director and run_director.modal.visible):
		clear_hand_hover()
		return
	var picked := card_at_hand_position(mouse)
	if picked == hovered_hand_card: return
	clear_hand_hover()
	hovered_hand_card = picked
	if picked: picked.set_hand_hover(true)

func begin_hand_drag(card: Node) -> bool:
	if not board_input.action.is_empty() or not can_player_act() or is_instance_valid(dragged_hand_card): return false
	dragged_hand_card = card
	clear_hand_hover()
	return true

func end_hand_drag(card: Node) -> void:
	if dragged_hand_card == card: dragged_hand_card = null
	clear_hand_hover()

func slot_at_screen_position(mouse: Vector2) -> Node3D:
	var camera := get_viewport().get_camera_3d()
	for slot in _response_slots():
		var plane := Plane(Vector3.UP, slot.global_position.y)
		var hit: Variant = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit == null: continue
		var local: Vector3 = slot.to_local(hit)
		var bounds: AABB = slot.get_aabb()
		if local.x >= bounds.position.x and local.x <= bounds.end.x \
				and local.z >= bounds.position.z and local.z <= bounds.end.z:
			return slot
	return null

func _unhandled_input(event: InputEvent) -> void:
	if run_director.modal.visible or presentation.blocking or not run_director.battle_active: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var board_card := card_at_board_position(event.position)
		if board_card != null:
			if not board_input.click_card(board_card): run_director.begin_inspect_hold(board_card)
			get_viewport().set_input_as_handled()
			return
		if not board_input.action.is_empty() or not can_player_act(): return
		update_hand_hover(event.position)
		if is_instance_valid(hovered_hand_card):
			var picked := hovered_hand_card
			picked._start_drag()
			run_director.begin_inspect_hold(picked, true)
			get_viewport().set_input_as_handled()

func card_at_board_position(mouse: Vector2) -> Node:
	for slot in _response_slots() + _threat_slots():
		var card := _get_card_in_slot(slot)
		if card == null or not card.is_alive(): continue
		if Geometry2D.is_point_in_polygon(mouse, hand_card_polygon(card, false)): return card
	return null

func record_graveyard(card: Node, reason: String) -> void:
	if card.graveyard_recorded: return
	card.graveyard_recorded = true
	log_event("%s: %s." % [reason, card.card_data.name])
	if reason == "Destroyed" and is_instance_valid(final_boss): final_boss.on_card_destroyed(card)
	if card.card_data.get("type", "response") != "response": return
	var entry: Dictionary = card.card_data.duplicate(true)
	if not card.card_data.get("utility", false): entry.health = card.max_health
	entry.graveyard_reason = reason
	entry.graveyard_round = turn
	entry.statuses = card.statuses.duplicate(true)
	entry.modifiers = card.modifiers.duplicate()
	graveyard_serial += 1
	entry.graveyard_id = graveyard_serial
	entry.recovery = card.base_definition.duplicate(true)
	player_graveyard.append(entry)

func destroyed_response_units() -> Array:
	return player_graveyard.filter(func(entry): return entry.get("graveyard_reason", "") == "Destroyed" and not entry.get("utility", false))

func recoverable_units() -> Array:
	return destroyed_response_units().filter(func(entry): return not entry.get("recovery", entry).get("recovered", false))

func recovered_definition(entry: Dictionary) -> Dictionary:
	var result: Dictionary = entry.get("recovery", entry).duplicate(true)
	# Old saves have no pre-buff data, so use the saved HP as the max.
	if not entry.has("recovery"):
		result.health = maxi(1, int(entry.health) - int(buffs_for(entry).get("health", 0)))
		for definition in run_director.collection:
			var same_copy: bool = entry.has("acquired") and definition.get("acquired", -1) == entry.acquired
			var same_upgrade: bool = definition.get("id", "") == entry.get("id", "") and int(definition.get("upgrades", 0)) == int(entry.get("upgrades", 0))
			if same_copy or (not entry.has("acquired") and same_upgrade):
				result = definition.duplicate(true)
				break
	if result.has("tax_original"): result[str(result.get("tax_key", "cost"))] = int(result.tax_original)
	for key in ["statuses", "locked_until", "tax_original", "tax_key", "tax_until", "graveyard_id", "graveyard_reason", "graveyard_round", "recovery"]: result.erase(key)
	result.recovered = true
	return result

func record_enemy_spell(definition: Dictionary) -> void:
	log_event("Janitor casts %s." % definition.get("name", "a utility"))

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
		active[i].move_in_hand(hand_position_below_slots(active[i], pos, b), b, i)

# =================================================================== TURN SYSTEM
## Round flow:
##   coin flip (once) -> [first side: draw + play] -> [second side: draw + play]
##   -> combat (first side attacks first, then the other side) -> next round,
##   and the side that goes first swaps every round.
func can_player_act() -> bool:
	return phase == Phase.PLAYER_PLAY and board_input.action.is_empty() and (not run_director or not run_director.modal.visible)

func try_play_card(card: Node) -> bool:
	return can_player_act() and not is_sealed(card.card_data) and preparedness >= int(card.card_data.get("cost", 0))

func on_card_played(card: Node) -> void:
	log_event("Response plays %s." % card.card_data.name)
	hand.erase(card)
	preparedness = maxi(0, preparedness - int(card.card_data.get("cost", 0)))
	_refresh_bars()
	arrange_hand_centered()
	if not card.card_data.get("utility", false) and card.card_data.get("effect", "") == "draw": draw_cards(int(card.card_data.get("draw_count", 1)))
	if not card.card_data.get("utility", false):
		if int(card.card_data.get("on_play_draw", 0)) > 0: draw_cards(int(card.card_data.on_play_draw))
		apply_formation_effect(card)
		if card.card_data.get("effect", "") == "grave_guard": card.add_status("barrier", mini(2, destroyed_response_units().size()))
		if card.card_data.get("effect", "") == "move_ally": begin_move_effect(card)

func apply_formation_effect(source: Node) -> void:
	var effect: String = source.card_data.get("effect", "")
	if effect in ["heal_all", "rally_all"]: set_board_view(true)
	var slots := _response_slots() if source.card_data.type == "response" else _threat_slots()
	for slot in slots:
		var ally = _get_card_in_slot(slot)
		if ally == null or ally == source: continue
		if effect == "heal_all": ally.heal(2)
		elif effect == "rally_all": ally.add_status("strength", 1)

func begin_move_effect(source: Node) -> void:
	if _response_slots().all(func(slot): return _get_card_in_slot(slot) != null): return
	var allies := _response_slots().map(func(slot): return _get_card_in_slot(slot)).filter(func(card): return card != null and card != source)
	if allies.is_empty(): return
	moving_source = source
	board_input.relocation(source)

func select_moving_ally(card: Node) -> void:
	if not plans.eligible(card) or card == moving_source or board_input.action.get("kind", "") != "relocate": return
	moving_ally = card
	clear_hand_hover()
	dragged_hand_card = card
	card.is_dragging = true
	card.is_relocating = true
	if card._tween: card._tween.kill()
	card.set_layer(100)
	card._set_overlay(true)

func complete_move_effect(slot: Node3D) -> void:
	if is_instance_valid(moving_ally) and slot in _response_slots() and _get_card_in_slot(slot) == null:
		moving_ally.is_dragging = false
		moving_ally.is_relocating = false
		end_hand_drag(moving_ally)
		moving_ally.place_on_slot(slot)
		log_event("Relocated %s." % moving_ally.card_data.name)
		if is_instance_valid(moving_source) and int(moving_source.card_data.get("move_heal", 0)) > 0: moving_ally.heal(int(moving_source.card_data.move_heal))
		if is_instance_valid(moving_source) and moving_source.card_data.get("utility", false): consume_utility(moving_source)
	cancel_move_effect()

func cancel_move_effect() -> void:
	if is_instance_valid(moving_ally) and moving_ally.is_dragging:
		moving_ally.is_dragging = false
		moving_ally.is_relocating = false
		end_hand_drag(moving_ally)
		moving_ally.place_on_slot(moving_ally.current_slot)
	moving_source = null
	moving_ally = null
	pending_utility = null
	pending_effect = ""
	board_input.clear()
	run_director.action_cancel = Callable()
	run_director.close_modal()
	arrange_hand_centered()

func try_utility(card: Node, slot: Node3D) -> bool:
	if not try_play_card(card): return false
	if slot not in _response_slots() or _get_card_in_slot(slot) != null: return false
	var effect: String = card.card_data.get("effect", "")
	if effect == "move":
		var allies := _response_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c != card and c.is_alive())
		if allies.is_empty(): return false
		pending_utility = card
		pending_effect = effect
		if card.get_parent() != hand_container: card.reparent(hand_container, true)
		arrange_hand_centered()
		begin_move_effect(card)
		return true
	elif effect in ["tutor", "seal", "tax", "rally", "cleanse", "recover"]:
		var choices: Array = []
		match effect:
			"tutor": choices = deck.filter(func(c): return not is_sealed(c))
			"recover": choices = recoverable_units()
			"seal": choices = enemy_hand.filter(func(c): return not is_sealed(c))
			"tax": choices = enemy_hand
			"rally", "cleanse": choices = _response_slots().map(func(s): return _get_card_in_slot(s)).filter(func(c): return c != null and c.is_alive())
		if choices.is_empty(): return false
		pending_utility = card
		pending_effect = effect
		if card.get_parent() != hand_container: card.reparent(hand_container, true)
		arrange_hand_centered()
		if effect in ["rally", "cleanse"]:
			board_input.pick("Click a friendly deployed card for " + str(card.card_data.name) + ". Esc cancels without spending.", choices, complete_utility_choice, cancel_utility_choice)
		elif effect in ["seal", "tax"]: run_director.choose_enemy_hand(choices, complete_utility_choice, cancel_utility_choice)
		else: run_director.choose_card("CHOOSE A TARGET · " + str(card.card_data.name).to_upper(), choices, complete_utility_choice, cancel_utility_choice)
		return true
	if effect in ["blast", "barrier", "herb", "tablet"]: set_board_view(true)
	consume_utility(card)
	if effect == "draw": draw_cards(int(card.card_data.get("draw_count", 2)) + int(card.card_data.get("utility_power", 0)))
	elif effect == "scout": run_director.show_intel()
	elif effect == "blast":
		for target in _threat_slots().map(func(s): return _get_card_in_slot(s)):
			if target: target.take_damage(2 + int(card.card_data.get("utility_power", 0)))
	elif effect == "barrier":
		player_barrier = mini(3, player_barrier + 2 + int(card.card_data.get("utility_power", 0)))
		for target in _response_slots().map(func(s): return _get_card_in_slot(s)):
			if target: target.add_status("barrier", 2 + int(card.card_data.get("utility_power", 0)))
	elif effect == "herb":
		for target in _response_slots().map(func(s): return _get_card_in_slot(s)):
			if target:
				target.statuses.erase("bleed")
				target.heal(1 + int(card.card_data.get("utility_power", 0)))
	elif effect == "tablet":
		for target in _response_slots().map(func(s): return _get_card_in_slot(s)):
			if target:
				target.statuses.erase("healing_reduced")
				target.heal(2 + int(card.card_data.get("utility_power", 0)))
	_check_game_over()
	return true

func consume_utility(card: Node) -> void:
	if card.card_data.get("curse", false): _damage_side(true, 1, true)
	record_graveyard(card, "Cast")
	on_card_played(card)
	preparedness = mini(energy_cap, preparedness + int(card.card_data.get("refund_energy", 0)))
	_refresh_bars()
	card.in_hand = false
	card.remove_from_group("cards")
	card.discard_to_pile()

func complete_utility_choice(target: Variant) -> void:
	board_input.clear()
	if not is_instance_valid(pending_utility): return
	if pending_effect == "recover" and (not recoverable_units().has(target) or get_hand_cards().size() > HAND_SIZE_MAX):
		cancel_utility_choice()
		return
	if pending_effect in ["seal", "tax"] and target not in enemy_hand:
		cancel_utility_choice()
		return
	var power := int(pending_utility.card_data.get("utility_power", 0))
	match pending_effect:
		"tutor":
			deck.erase(target)
		"recover": player_graveyard.erase(target)
		"seal": target.locked_until = turn + 2 + power
		"tax":
			for i in range(1 + power): increase_cost(target)
		"rally": target.add_status("strength", 2 + power)
		"cleanse":
			target.cleanse()
			if power > 0: target.heal(2 * power)
	var tutoring := pending_effect in ["tutor", "recover"]
	var received: Dictionary = recovered_definition(target) if pending_effect == "recover" else (target if pending_effect == "tutor" else {})
	consume_utility(pending_utility)
	pending_utility = null
	pending_effect = ""
	run_director.action_cancel = Callable()
	run_director.close_modal()
	if tutoring: add_card_to_hand(received)
	_refresh_bars()

func cancel_utility_choice() -> void:
	board_input.clear()
	pending_utility = null
	pending_effect = ""
	run_director.action_cancel = Callable()
	run_director.close_modal()
	arrange_hand_centered()

func increase_cost(definition: Dictionary) -> void:
	var key := "cost" if definition.get("type", "response") == "response" or int(definition.get("cost", 0)) > 0 else "tension_cost"
	if not definition.has("tax_original"):
		definition.tax_original = int(definition.get(key, 1))
		definition.tax_key = key
	# A tax adds at most 2 cost. Casting it again refreshes it instead of stacking.
	definition[key] = mini(int(definition.tax_original) + 2, int(definition.get(key, 1)) + 1)
	definition.tax_until = turn + 2

func expire_tax(definition: Dictionary) -> void:
	if definition.has("tax_original") and int(definition.get("tax_until", 0)) <= turn:
		definition[str(definition.tax_key)] = int(definition.tax_original)
		for key in ["tax_original", "tax_key", "tax_until"]: definition.erase(key)

func enemy_utility(definition: Dictionary) -> void:
	record_enemy_spell(definition)
	var effect: String = definition.get("effect", "")
	if effect == "seal":
		var choices := get_hand_cards().filter(func(c): return not is_sealed(c.card_data))
		if not choices.is_empty():
			var target = choices.pick_random()
			if encounter_kind in ["elite", "boss"]: target = best_disruption_target(choices, false)
			target.card_data.locked_until = turn + 2
			target._refresh_face()
			target.spawn_popup("SEALED · 2 ROUNDS", UI.DANGER)
	elif effect == "tax":
		var choices := get_hand_cards()
		if not choices.is_empty():
			var target = choices.pick_random()
			if encounter_kind in ["elite", "boss"]: target = best_disruption_target(choices, true)
			increase_cost(target.card_data)
			target.refresh_cost()
			target.spawn_popup("COST +1", UI.DANGER)

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
	var previous := phase
	phase = p
	if is_instance_valid(presentation) and run_director and run_director.battle_active and not presentation.blocking:
		if p in [Phase.PLAYER_DRAW, Phase.PLAYER_PLAY] and previous not in [Phase.PLAYER_DRAW, Phase.PLAYER_PLAY]: presentation.banner("YOUR TURN", "Round %d" % turn, UI.RESPONSE)
		elif p == Phase.ENEMY and previous != Phase.ENEMY: presentation.banner("JANITOR'S TURN", "Watch the opposing formation")
		elif p == Phase.COMBAT and previous != Phase.COMBAT: presentation.banner("CLASH", "The first side attacks first")
	$HUD/Root/DeckDrawButton.disabled = p != Phase.PLAYER_DRAW
	if is_instance_valid(presentation): presentation.remind_to_draw(p == Phase.PLAYER_DRAW)
	if text != "" and _phase_label:
		_phase_label.text = "Pick a card to draw" if p == Phase.PLAYER_DRAW else text
	if _end_turn_btn:
		_end_turn_btn.disabled = not (p == Phase.PLAYER_DRAW or p == Phase.PLAYER_PLAY)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func is_opening_blocker(definition: Dictionary) -> bool:
	return definition.get("id", "") in ["quick_dash", "debris_clearance"] and int(definition.get("cost", 0)) == 1 and not definition.get("utility", false) and not is_sealed(definition)

func smooth_opening_hand() -> void:
	if encounter_kind != "battle" or run_director.floor_number != 1: return
	# Match draw_cards: it picks the last available card and erases the first equal copy.
	var pending := deck.duplicate(true)
	for i in STARTING_HAND:
		var available := pending.filter(func(card): return not is_sealed(card))
		if available.is_empty(): break
		var picked: Dictionary = available.back()
		if is_opening_blocker(picked): return
		pending.erase(picked)
	for i in deck.size():
		if is_opening_blocker(deck[i]):
			deck.append(deck.pop_at(i))
			return

func _start_match() -> void:
	_set_phase(Phase.SETUP, "Call Heads or Tails")
	var serial := encounter_serial
	presentation.blocking = true
	_apply_view(WIDE_VIEW)
	_shift_camera(DESK_VIEW, 1.0)
	presentation.banner("DISASTER ENCOUNTER", encounter_kind.capitalize() + " · Prepare your formation", UI.GOLD, true)
	await _wait(1.1)
	if serial != encounter_serial: return
	presentation.blocking = false
	smooth_opening_hand()
	draw_cards(STARTING_HAND)
	enemy_draw_cards(STARTING_HAND)
	enemy_draw_evolutions(1)
	coin_result = randi_range(0, 1)
	coin_pick = -1
	resume_coin()

func resume_coin() -> void:
	var serial := encounter_serial
	run_director.screen = "coin"
	var pick: int = await presentation.choose_coin(coin_result, coin_pick)
	if pick < 0 or serial != encounter_serial: return
	coin_pick = pick
	player_first = coin_pick == coin_result
	log_event("Coin: called %s, landed %s. %s takes the first turn." % ["Heads" if coin_pick == 0 else "Tails", "Heads" if coin_result == 0 else "Tails", "Response" if player_first else "The Janitor"])
	run_director.screen = ""
	_set_phase(Phase.SETUP, "You take the first turn" if player_first else "The Janitor takes the first turn")
	_begin_round()

func _begin_round() -> void:
	# A depleted draw pile is still playable while hand or board cards remain.
	if deck.is_empty() and get_hand_cards().is_empty() and _response_slots().all(func(s): return _get_card_in_slot(s) == null):
		_set_phase(Phase.GAME_OVER, "No Response cards remain")
		run_director.battle_finished(false)
		return
	if not is_instance_valid(final_boss) and not (enemy_deck + enemy_hand).any(func(card): return int(card.get("cost", 0)) == 0 and not card.get("utility", false)) and _threat_slots().all(func(s): return _get_card_in_slot(s) == null):
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
	for definition in deck + enemy_deck + enemy_hand + enemy_evolution_deck: expire_tax(definition)
	for card in get_tree().get_nodes_in_group("cards"): expire_tax(card.card_data)
	if _turn_label: _turn_label.text = "Turn %d" % turn
	# Response energy refills to the cap (cap grows by 1 each round)
	preparedness = energy_cap
	# Disaster tension refills to the cap (cap grows by 1 each round, starts at 3)
	var bonus := buff_value(false, "energy")
	tension_cap = clampi(TENSION_START + (turn - 1) * (1 + overclock_stacks(false)) + bonus, 1, maxi(1, TENSION_MAX + bonus))
	tension = tension_cap
	_refresh_bars()
	player_hp = mini(hero_max_hp(), player_hp + buff_value(true, "hero_regen"))
	enemy_hp = mini(enemy_max_hp, enemy_hp + buff_value(false, "hero_regen"))
	_refresh_bars()

	# Upkeep phase: Regenerating cards heal 1 HP
	for c in get_tree().get_nodes_in_group("cards"):
		if not c.in_hand: c.status_upkeep()
		else: c._refresh_face()

	# Disaster modifier escalation based on round count (from GDD)
	_apply_round_modifiers()

	if is_instance_valid(final_boss):
		final_boss.prepare_round()
		if _check_game_over(): return
		_begin_player_turn()
	elif player_first:
		_begin_player_turn()
	else:
		await _enemy_turn()
		if phase != Phase.GAME_OVER:
			_begin_player_turn()

func _apply_round_modifiers() -> void:
	if encounter_kind == "battle" or is_instance_valid(final_boss): return
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
	if phase != Phase.PLAYER_DRAW or preparedness < 1 or get_hand_cards().size() >= HAND_SIZE_MAX: return
	var choices := deck.filter(func(card): return not is_sealed(card))
	if choices.is_empty(): return
	run_director.choose_card("Pick a card to draw", choices, complete_draw_choice, run_director.close_modal, "")

func complete_draw_choice(definition: Dictionary) -> void:
	if phase != Phase.PLAYER_DRAW or preparedness < 1 or definition not in deck or is_sealed(definition): return
	if get_hand_cards().size() >= HAND_SIZE_MAX: return
	preparedness -= 1
	deck.erase(definition)
	run_director.action_cancel = Callable()
	run_director.close_modal()
	add_card_to_hand(definition)
	draw_cards(maxi(0, buff_value(true, "draw")))
	_set_phase(Phase.PLAYER_PLAY, "Your turn - play cards, then End Turn")
	_refresh_bars()

func _on_end_turn_pressed() -> void:
	if not board_input.action.is_empty(): return
	if run_director and run_director.modal.visible: return
	if phase != Phase.PLAYER_DRAW and phase != Phase.PLAYER_PLAY:
		return
	# Don't end the turn while a card is still in the air
	for c in get_hand_cards():
		if c.is_dragging: return

	plans.bank_unused_energy()
	if player_first:
		# Player went first -> now the Disaster plays its card
		await _enemy_turn()
		if phase == Phase.GAME_OVER: return
	await _combat()
	if phase == Phase.GAME_OVER: return

	turn += 1
	var bonus := buff_value(true, "energy")
	energy_cap = clampi(energy_cap + resource_growth(true), 1, maxi(1, ENERGY_MAX + bonus))
	player_first = not player_first
	_begin_round()

func _pick_smart_threat_slot(empty_slots: Array, card_data: Dictionary) -> Node3D:
	var elem: String = card_data.get("element", "")
	if encounter_kind == "battle" and randf() < 0.5: return empty_slots.pick_random()
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
				score += 3.0 # Regular encounters use only a mild matchup preference.
			elif mult == 1.0:
				score += 2.0
			else:
				score += 1.0
		else:
			score += 2.0 # Open lane
		# Slight organic variance
		score += randf() * 3.0
		if score > best_score:
			best_score = score
			best_slot = s

	return best_slot if best_slot else empty_slots.pick_random()

# ------------------------------------------------------------------- enemy
func _enemy_turn() -> void:
	if is_instance_valid(final_boss):
		_set_phase(Phase.ENEMY, "The Warden prepares its announced pattern")
		await _wait(0.4)
		return
	_set_phase(Phase.ENEMY, "Disaster's turn...")
	await _wait(0.5)

	# --- Disaster Draw Phase ---
	if not enemy_deck.is_empty() and enemy_hand.size() < 6:
		enemy_draw_cards(maxi(0, 1 + buff_value(false, "draw")))
		_set_phase(Phase.ENEMY, "Disaster draws a card...")
		await _wait(0.4)

	if turn % 2 == 0: enemy_draw_evolutions(1)

	# --- Disaster Action Phase (Can play multiple cards in one turn!) ---
	var actions_taken := 0
	var max_actions := enemy_action_limit()
	var played_something := true

	while played_something and actions_taken < max_actions and tension > 0:
		played_something = false
		var spells := enemy_hand.filter(func(d): return d.get("utility", false) and not is_sealed(d) and int(d.get("tension_cost", 1)) <= tension and (d.get("effect", "") != "seal" or get_hand_cards().any(func(c): return not is_sealed(c.card_data))) and (d.get("effect", "") != "tax" or not get_hand_cards().is_empty()))
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
		var evo_candidates := enemy_hand.filter(func(d): return int(d.get("cost", 0)) > 0 and not d.get("utility", false) and not is_sealed(d) and int(d.get("cost", 1)) <= active_threats.size())
		var plan: Dictionary = {}
		if encounter_kind != "battle" or (empty_slots.is_empty() and turn >= 3):
			plan = best_evolution_plan(active_threats, evo_candidates)
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
			enemy_hand.erase(evo_card_data)
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
			major_evolution_entry(evo_card, sac_count)
			evo_card.spawn_popup("EVOLVED!", UI.AMBER)
			shake_camera(0.12, 0.3)

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
			if encounter_kind != "battle" and turn in [4, 5, 6] and randf() < 0.5:
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
	if encounter_kind == "battle" and run_director.floor_number == 1:
		return mini(tension, 1 if turn <= 3 else 2)
	var base_actions := 2 if encounter_kind == "battle" else 3
	var maximum := 4 if encounter_kind == "battle" else 5
	return mini(tension, clampi(base_actions + buff_value(false, "energy"), 1, maximum))

func _on_enemy_card_played(card: Node) -> void:
	log_event("Disaster plays %s." % card.card_data.name)
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
		var dealt: int = opponent.adjusted_damage(maxi(1, int(attack * mult)), pierce)
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
	if pierce and can_strike and (opponent == null or not opponent.has_modifier("armored")):
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
	return BattleEngine.definition_has_modifier(definition, modifier)

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
				if cost >= 3: gain += 3.0
				for sacrificed in sacrifices:
					if sacrificed.card_data.get("on_sacrifice", "") == "draw" and not enemy_deck.is_empty(): gain += 2.0
					if sacrificed.card_data.get("on_sacrifice", "") == "burn": gain += 1.0
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
		score += float(bonus.get("piercing", 0)) * 5 + float(bonus.get("regen", 0)) - float(bonus.get("self_bleed", 0)) * 3 - float(bonus.get("sluggish", 0)) * 3 - float(bonus.get("damage_taken", 0)) * 5
		if score > best_score:
			best_score = score
			best = option
	return best

# ------------------------------------------------------------------- combat
const TYPE_CHART = BattleEngine.TYPE_CHART

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
	return BattleEngine.calc_damage(BattleQueries.context(self),
		BattleQueries.card(self, attacker), BattleQueries.card(null, defender))

func _synergy_bonus(card: Node) -> int:
	return BattleEngine.synergy_bonus(BattleQueries.context(self), BattleQueries.card(self, card))

func _combat() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		card.set_meta("combat_kill", false)
	var prev_view: View = view_mode
	set_board_view(true)
	set_hand_tucked(true)
	log_event("Combat begins.")
	plans.apply_combat()
	_set_phase(Phase.COMBAT, "Combat Phase!")
	await _wait(0.65)

	# The side that played first this round attacks first
	if is_instance_valid(final_boss):
		await _side_attacks(true)
		if phase != Phase.GAME_OVER and is_instance_valid(final_boss):
			final_boss.resolve_intent()
			if phase != Phase.GAME_OVER: await _side_attacks(false)
	elif player_first:
		await _side_attacks(true)
		if phase != Phase.GAME_OVER:
			await _side_attacks(false)
	else:
		await _side_attacks(false)
		if phase != Phase.GAME_OVER:
			await _side_attacks(true)

	if phase != Phase.GAME_OVER: resolve_blood_pact()
	plans.finish_combat()
	if phase != Phase.GAME_OVER:
		await _wait(0.5)
		set_view(prev_view)
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
			atk.spawn_popup("SLUGGISH · RESTING", UI.MUTED)
			continue

		var def = _get_card_in_slot(theirs[i])
		if response_side and is_instance_valid(final_boss): def = final_boss.redirect_target(atk, def)
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
	return BattleEngine.status_stacks(BattleQueries.statuses(subject), status)

func condition_met(condition: Dictionary, source: Variant, target: Variant) -> bool:
	return BattleEngine.condition_met(condition, BattleQueries.statuses(source), BattleQueries.statuses(target))

func conditional_attack_bonus(attacker: Node, defender: Node) -> int:
	var target: Variant = null if defender == null else BattleQueries.card(null, defender)
	return BattleEngine.conditional_attack_bonus(BattleQueries.card(null, attacker), target)

func attack_strikes(attacker: Node, defender: Node) -> int:
	var target: Variant = null if defender == null else BattleQueries.card(null, defender)
	return BattleEngine.attack_strikes(BattleQueries.card(null, attacker), target)

func resolve_attack(atk: Node, defender: Node, response_side: bool) -> void:
	if not atk.can_attack(turn): return
	var strikes := attack_strikes(atk, defender)
	for strike in range(strikes):
		if not atk.is_alive() or phase == Phase.GAME_OVER: break
		if strike > 0:
			# Keep a surviving redirected blocker; a killed or extracted target leaves the lane open.
			if not is_instance_valid(defender) or not defender.is_alive():
				var lane: int = (_response_slots() if response_side else _threat_slots()).find(atk.current_slot)
				defender = null
				if lane >= 0:
					defender = _get_card_in_slot((_threat_slots() if response_side else _response_slots())[lane])
			atk.spawn_popup("FOLLOW-UP STRIKE", UI.RESPONSE)
		resolve_single_strike(atk, defender, response_side)

func resolve_single_strike(atk: Node, defender: Node, response_side: bool) -> void:
	if defender != null and defender.card_data.type == atk.card_data.type: return
	var blocked: bool = defender != null and defender.is_alive()
	var piercing: bool = atk.has_modifier("piercing")
	var armored_block: bool = blocked and defender.has_modifier("armored")
	log_event("%s attacks %s." % [atk.card_data.name, defender.card_data.name if blocked else ("Disaster health" if response_side else "Response health")])
	if blocked:
		var info := _calc_damage(atk, defender)
		defender.take_damage(info.dmg, info.mult, false, piercing)
		if not defender.is_alive(): atk.set_meta("combat_kill", true)
		# Effects land only on a surviving card. Normal damage never spills into HP.
		if defender.is_alive() and not defender.last_evaded_hit:
			var inflicted: Dictionary = atk.card_data.get("on_hit", {})
			var buffs := buffs_for(atk.card_data)
			for status in inflicted:
				var extra := int(buffs.get(status, 0)) * (2 if status == "burn" else 1)
				defender.add_status(status, int(inflicted[status]) + extra)
		shake_camera(0.08, 0.2)
	if not blocked or (piercing and not armored_block):
		var direct: int = atk.effective_attack() + _synergy_bonus(atk) + conditional_attack_bonus(atk, defender if blocked else null)
		if atk.has_modifier("fierce"): direct += 2
		_damage_side(not response_side, direct)
	if int(atk.card_data.get("leech", 0)) > 0: atk.heal(int(atk.card_data.leech))
	if blocked and defender.is_alive() and not defender.last_evaded_hit:
		var thorns := int(buffs_for(defender.card_data).get("thorns", 0)) + int(defender.card_data.get("thorns", 0))
		if thorns > 0:
			var was_alive: bool = atk.is_alive()
			atk.take_damage(thorns, 1.0, true)
			if was_alive and not atk.is_alive(): defender.set_meta("combat_kill", true)
	atk.after_attack(turn)
	_check_game_over()

func resolve_blood_pact() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if card.in_hand or card.current_slot == null or not card.is_alive(): continue
		if int(buffs_for(card.card_data).get("kill_or_die", 0)) <= 0: continue
		if card.get_meta("combat_kill", false): continue
		log_event("Blood Pact destroys %s: no kill this combat." % card.card_data.name)
		card.card_data.health = 0
		card._die()
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


func sacrifice_reward(card: Node) -> void:
	var effect: String = card.card_data.get("on_sacrifice", "")
	if effect == "draw":
		enemy_draw_cards(1)
		log_event("Sacrificing %s draws a disaster card." % card.card_data.name)
	elif effect == "burn":
		var lane: int = _threat_slots().find(card.current_slot)
		if lane >= 0:
			var target = _get_card_in_slot(_response_slots()[lane])
			if target: target.add_status("burn", 2)
		log_event("Sacrificing %s releases 2 Burn in its opposing lane." % card.card_data.name)


func major_evolution_entry(card: Node, sacrifices: int) -> void:
	if sacrifices < 3: return
	card.add_status("barrier", 3 if sacrifices >= 4 else 2)
	enemy_draw_cards(1)
	if sacrifices >= 4:
		for lane in _response_slots():
			var target = _get_card_in_slot(lane)
			if target: target.take_damage(1, 1.0, true)
	log_event("Major evolution gains entry protection and draws 1; four sacrifices also shock the formation.")
