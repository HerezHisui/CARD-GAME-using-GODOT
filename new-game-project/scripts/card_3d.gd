@tool
extends Area3D
const BattleEngine = preload("res://scripts/battle_engine.gd")
const BattleQueries = preload("res://scripts/battle_query_adapter.gd")
## A single playable card.
## While in hand it is parented to the Camera3D so it always faces the player
## (like a classic 2D card game hand). While dragged it floats over the table
## facing the camera. When dropped on an empty slot it lies flat on the board.
##
## The card face (frame, art, name, stats) is drawn by a 2D Control tree inside
## a SubViewport and shown on the Art sprite, so the whole face is ONE texture
## and always layers correctly.

const UI = preload("res://scripts/ui_theme.gd")
const CARD_WIDTH := 1.1
const UPRIGHT := Basis(Vector3.RIGHT, PI / 2.0) # card face (+Y) -> camera (+Z)
const FACE_W := 264
const FACE_H := 360
const FACE_RENDER_SCALE := 2


## Intentionally blank until final artwork is supplied.
## Art is now supplied: card name -> art file path.
const ART: Dictionary = {
	"Aftershock Choir": "res://assets/card_art/aftershock_choir.png",
	"Alarm Sweep": "res://assets/card_art/alarm_sweep.png",
	"Ash Predator": "res://assets/card_art/ash_predator.png",
	"Barrier Generator": "res://assets/card_art/barrier_generator.png",
	"Black Squall": "res://assets/card_art/black_squall.png",
	"Blocked Exit": "res://assets/card_art/blocked_exit.png",
	"Cinder Cloud": "res://assets/card_art/cinder_cloud.png",
	"Containment Lance": "res://assets/card_art/containment_lance.png",
	"Containment Order": "res://assets/card_art/containment_order.png",
	"Crosswind": "res://assets/card_art/crosswind.png",
	"Cutting Crew": "res://assets/card_art/cutting_crew.png",
	"Debris Clearance": "res://assets/card_art/debris_clearance.png",
	"Decontaminate": "res://assets/card_art/decontaminate.png",
	"Drain Vortex": "res://assets/card_art/drain_vortex.png",
	"Drill Captain": "res://assets/card_art/drill_captain.png",
	"Drill Leader": "res://assets/card_art/drill_leader.png",
	"Ember": "res://assets/card_art/ember.png",
	"Evacuation Route": "res://assets/card_art/evacuation_route.png",
	"Field Medic": "res://assets/card_art/field_medic.png",
	"Fire Drill": "res://assets/card_art/fire_drill.png",
	"Fire Hose": "res://assets/card_art/fire_hose.png",
	"First Aid Herb": "res://assets/card_art/first_aid_herb.png",
	"Fissure": "res://assets/card_art/fissure.png",
	"Flash Flood": "res://assets/card_art/flash_flood.png",
	"Fracture Hunter": "res://assets/card_art/fracture_hunter.png",
	"Gale Force": "res://assets/card_art/gale_force.png",
	"Glass Quake": "res://assets/card_art/glass_quake.png",
	"Gust": "res://assets/card_art/gust.png",
	"Hazard Forecast": "res://assets/card_art/hazard_forecast.png",
	"Hazmat Team": "res://assets/card_art/hazmat_team.png",
	"Heat Seeker": "res://assets/card_art/heat_seeker.png",
	"Heavy Loader": "res://assets/card_art/heavy_loader.png",
	"Inferno": "res://assets/card_art/inferno.png",
	"Lane Marshal": "res://assets/card_art/lane_marshal.png",
	"Last Responder": "res://assets/card_art/last_responder.png",
	"Momentum Team": "res://assets/card_art/momentum_team.png",
	"Needle Gale": "res://assets/card_art/needle_gale.png",
	"Needle Team": "res://assets/card_art/needle_team.png",
	"Pressure Break": "res://assets/card_art/pressure_break.png",
	"Pressure Front": "res://assets/card_art/pressure_front.png",
	"Quick Dash": "res://assets/card_art/quick_dash.png",
	"Rally the Team": "res://assets/card_art/rally_the_team.png",
	"Recovery Detail": "res://assets/card_art/recovery_detail.png",
	"Recovery Team": "res://assets/card_art/recovery_team.png",
	"Red Tape": "res://assets/card_art/red_tape.png",
	"Relief Crew": "res://assets/card_art/relief_crew.png",
	"Rescue Crane": "res://assets/card_art/rescue_crane.png",
	"Restoration Tablet": "res://assets/card_art/restoration_tablet.png",
	"Rising Tide": "res://assets/card_art/rising_tide.png",
	"Safety Lock": "res://assets/card_art/safety_lock.png",
	"Search and Rescue": "res://assets/card_art/search_and_rescue.png",
	"Shard Barrier": "res://assets/card_art/shard_barrier.png",
	"Shelter Brace": "res://assets/card_art/shelter_brace.png",
	"Silent Runner": "res://assets/card_art/silent_runner.png",
	"Sleeping Fault": "res://assets/card_art/sleeping_fault.png",
	"Steam Team": "res://assets/card_art/steam_team.png",
	"Supply Runner": "res://assets/card_art/supply_runner.png",
	"Toxic Runoff": "res://assets/card_art/toxic_runoff.png",
	"Toxin Hunter": "res://assets/card_art/toxin_hunter.png",
	"Tremor": "res://assets/card_art/tremor.png",
	"Tsunami": "res://assets/card_art/tsunami.png",
	"Venom Surge": "res://assets/card_art/venom_surge.png",
	"Warm Front": "res://assets/card_art/warm_front.png",
	"Wildfire": "res://assets/card_art/wildfire.png",
	"Worldbreaker": "res://assets/card_art/worldbreaker.png",
}
static var back_texture: Texture2D
static var face_font: SystemFont

var card_data: Dictionary
var base_definition: Dictionary = {}
var is_dragging := false
var is_hovered := false
var graveyard_recorded := false
var planned_guard := 0
var plan_attack_bonus := 0
var plan_ignore_taunt := false
var last_evaded_hit := false
var is_relocating := false
var in_hand := true
var preview_only := false
var current_slot: Node3D = null
var card_height := CARD_WIDTH * FACE_H / FACE_W
var max_health := 0
var modifiers: Array[String] = []
var statuses: Dictionary = {}
var last_attack_turn := -1

var _tween: Tween
var _vp: SubViewport
var _pulse_tween: Tween
var _hp_label: Label
var _atk_label: Label
var _cost_label: Label
var _status_row: GridContainer
var _cost_caption: Label
var _keyword_label: Label
var face_signature := 0
const FACE_CHECK_INTERVAL := 0.1
var face_check_elapsed := 0.0
var popup_stack := 0
var last_popup_msec := -1000

@onready var art_sprite: Sprite3D = $Art
@onready var mesh: MeshInstance3D = $Mesh

func _notification(what: int) -> void:
	if not is_instance_valid(art_sprite): return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		# The generated viewport is not saved with the scene.
		art_sprite.texture = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE and is_instance_valid(_vp):
		art_sprite.texture = _vp.get_texture()

func _ready() -> void:
	if Engine.is_editor_hint():
		preview_only = true
		in_hand = false
		setup({"name":"Quick Dash", "type":"response", "element":"evac", "cost":1, "attack":2, "health":1})
		set_process(false)
		return
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# ---------------------------------------------------------------- setup
func setup(data: Dictionary) -> void:
	base_definition = data.duplicate(true)
	card_data = data.duplicate(true)
	preload("res://scripts/battle_rules.gd").remove_utility_stats(base_definition)
	preload("res://scripts/battle_rules.gd").remove_utility_stats(card_data)
	if not preview_only: card_data = _manager().prepare_card_data(card_data)
	# JSON numbers load as floats -> normalise to ints
	for k in (["cost"] if card_data.get("utility", false) else ["cost", "attack", "health"]):
		card_data[k] = int(card_data.get(k, 0))
	max_health = int(card_data.get("health", 0))
	modifiers.clear()
	statuses.clear()
	last_attack_turn = -1
	graveyard_recorded = false
	if int(card_data.get("strength", 0)) > 0: statuses.strength = int(card_data.strength)
	var self_bleed: int = 0 if preview_only else int(_manager().buffs_for(card_data).get("self_bleed", 0))
	if self_bleed > 0: statuses.bleed = self_bleed
	if card_data.has("modifier") and str(card_data.modifier) != "":
		for ability in str(card_data.modifier).split(","):
			var normalized := ability.strip_edges().to_lower()
			if not normalized.is_empty() and normalized not in modifiers: modifiers.append(normalized)

	for card_modifier in card_data.get("modifiers", []):
		var normalized := str(card_modifier).strip_edges().to_lower()
		if not normalized.is_empty() and normalized not in modifiers: modifiers.append(normalized)

	_build_face()
	art_sprite.texture = _vp.get_texture()
	art_sprite.pixel_size = CARD_WIDTH / (FACE_W * FACE_RENDER_SCALE)
	art_sprite.scale = Vector3.ONE
	art_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	art_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD

	var box := BoxMesh.new()
	box.size = Vector3(CARD_WIDTH, 0.02, card_height)
	mesh.mesh = box
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color.WHITE
	back_mat.albedo_texture = _card_back()
	back_mat.roughness = 0.85
	mesh.material_override = back_mat

	var shape := BoxShape3D.new()
	shape.size = Vector3(CARD_WIDTH, 0.04, card_height)
	$CollisionShape3D.shape = shape

	if Engine.is_editor_hint():
		art_sprite.position.y = 0.026
	else:
		_set_overlay(true)

func _build_face() -> void:
	_vp = SubViewport.new()
	# Keep layout coordinates while rasterizing sharper text for 3D and UI previews.
	_vp.size = Vector2i(FACE_W, FACE_H) * FACE_RENDER_SCALE
	_vp.size_2d_override = Vector2i(FACE_W, FACE_H)
	_vp.size_2d_override_stretch = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)

	var elem: String = card_data.get("element", "")
	var accent: Color = UI.affinity_color(elem)
	var is_disaster: bool = card_data.get("type", "") == "disaster"

	if not face_font: face_font = UI.font(true)
	var title_font := face_font

	# Frame
	var frame := Panel.new()
	frame.size = Vector2(FACE_W, FACE_H)
	frame.add_theme_stylebox_override("panel", UI.card_frame(is_disaster))
	_vp.add_child(frame)
	UI.decorate(frame)

	var text_col := UI.TEXT

	# Name
	var name_lbl := _face_label(title_font, 19, text_col)
	name_lbl.name = "CardName"
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 17 if str(card_data.get("name", "")).length() > 17 else 19)
	name_lbl.text = card_data.get("name", "?")
	name_lbl.position = Vector2(70, 10)
	name_lbl.size = Vector2(FACE_W - 80, 48)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.outline(name_lbl)
	frame.add_child(name_lbl)

	# Art window
	var art_bg := ColorRect.new()
	art_bg.color = UI.INSET
	art_bg.position = Vector2(18, 72)
	art_bg.size = Vector2(FACE_W - 36, 144)
	frame.add_child(art_bg)
	var affinity_line := ColorRect.new()
	affinity_line.color = accent
	affinity_line.position = Vector2(18, 63)
	affinity_line.size = Vector2(FACE_W - 36, 3)
	frame.add_child(affinity_line)
	_status_row = GridContainer.new()
	_status_row.columns = 10
	_status_row.position = Vector2(22, 240)
	_status_row.size = Vector2(FACE_W - 44, 14)
	_status_row.add_theme_constant_override("h_separation", 3)
	_status_row.add_theme_constant_override("v_separation", 2)
	frame.add_child(_status_row)
	var art_path: String = ART.get(card_data.get("name", ""), "")
	# No art or missing file: keep the plain art window.
	if art_path != "" and ResourceLoader.exists(art_path):
		var art_image := TextureRect.new()
		art_image.texture = load(art_path)
		art_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_image.size = art_bg.size
		art_image.clip_contents = true
		art_bg.clip_contents = true
		art_bg.add_child(art_image)

	# Element banner
	var elem_lbl := _face_label(title_font, 18, Color.WHITE)
	elem_lbl.text = elem.to_upper()
	elem_lbl.position = Vector2(18, 222)
	elem_lbl.size = Vector2(FACE_W - 36, 26)
	elem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elem_lbl.add_theme_stylebox_override("normal", UI.affinity_band(elem))
	frame.add_child(elem_lbl)

	# Sacrifice costs use the same crimson action color as the interface.
	var cost_col := UI.RAISED if card_data.get("cost_type", "energy") == "energy" else UI.CRIMSON
	var cost_badge := _badge(str(card_data.cost), cost_col, Vector2(6, 6), title_font)
	_cost_label = cost_badge.get_child(0)
	frame.add_child(cost_badge)
	_cost_caption = _face_label(title_font, 10, UI.TEXT)
	_cost_caption.text = ""
	_cost_caption.position = Vector2(0, 41)
	_cost_caption.size = Vector2(60, 14)
	_cost_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_badge.add_child(_cost_caption)

	_atk_label = null
	_hp_label = null
	_keyword_label = null
	if not card_data.get("utility", false):
		var atk := _badge(str(card_data.attack), UI.RAISED, Vector2(16, FACE_H - 80), title_font)
		_atk_label = atk.get_child(0)
		frame.add_child(atk)
		var hp := _badge(str(card_data.health), UI.RAISED, Vector2(FACE_W - 76, FACE_H - 80), title_font)
		_hp_label = hp.get_child(0)
		frame.add_child(hp)
		var atk_cap := _face_label(title_font, 14, text_col)
		atk_cap.text = "ATK            HP"
		atk_cap.position = Vector2(0, FACE_H - 24)
		atk_cap.size = Vector2(FACE_W, 20)
		atk_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		frame.add_child(atk_cap)
		# First keyword, in the gap between the ATK and HP badges.
		_keyword_label = _face_label(title_font, 14, text_col)
		_keyword_label.name = "Keyword"
		_keyword_label.position = Vector2(76, 284)
		_keyword_label.size = Vector2(FACE_W - 152, 22)
		_keyword_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_keyword_label.clip_text = true
		UI.outline(_keyword_label)
		frame.add_child(_keyword_label)
	_refresh_face()

func _face_label(font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _badge(txt: String, col: Color, pos: Vector2, font: Font) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = Vector2(60, 60)
	p.add_theme_stylebox_override("panel", UI.badge_style(col))
	var l := _face_label(font, 26, UI.TEXT)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	l.text = txt
	l.size = p.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _refresh_face() -> void:
	face_signature = current_face_signature()
	var trim := _vp.get_child(0).get_node("IndustrialTrim")
	trim.hazard = not preview_only and _manager().is_sealed(card_data)
	trim.queue_redraw()
	var disaster: bool = card_data.get("type", "response") == "disaster"
	var sacrifice: bool = disaster and not card_data.get("utility", false) and int(card_data.get("cost", 0)) > 0
	var cost: int = int(card_data.get("tension_cost", 1)) if disaster and not sacrifice else int(card_data.get("cost", 0))
	if _cost_label: _cost_label.text = str(cost)
	if _cost_caption: _cost_caption.text = "SAC" if sacrifice else ""
	if card_data.has("boss_role"):
		_cost_label.text = "-"
		_cost_caption.text = "BOSS"

	if _hp_label:
		_hp_label.text = str(maxi(card_data.health, 0))
		_hp_label.add_theme_color_override("font_color", UI.DANGER if card_data.health < max_health else UI.TEXT)
	if _atk_label:
		_atk_label.text = str(effective_attack())
	# Only the first keyword fits; the rest stay in the icon row and inspect box.
	if _keyword_label:
		_keyword_label.text = _face_keyword().to_upper()
	if _status_row:
		for child in _status_row.get_children():
			_status_row.remove_child(child)
			child.queue_free()
		for status in statuses:
			if int(statuses[status]) > 0: _add_effect_icon(str(status), int(statuses[status]))
		for modifier in modifiers: _add_effect_icon(str(modifier))
		for passive in ["piercing", "sluggish"]:
			if has_modifier(passive) and passive not in modifiers: _add_effect_icon(passive)
		var effect: String = card_data.get("effect", "")
		if not effect.is_empty(): _add_effect_icon(effect)
		for status in card_data.get("on_hit", {}): _add_effect_icon(str(status))
		for key in ["leech", "on_play_draw", "thorns", "status_bonus", "utility_power", "refund_energy"]:
			if int(card_data.get(key, 0)) > 0: _add_effect_icon(key)
		if card_data.has("condition"): _add_effect_icon("condition")
		if planned_guard > 0: _add_effect_icon("barrier")
		if plan_attack_bonus > 0: _add_effect_icon("strength")
		if plan_ignore_taunt or card_data.get("ignore_taunt", false): _add_effect_icon("piercing")
		if card_data.get("curse", false): _add_effect_icon("bleed")
		if not preview_only and _manager().is_sealed(card_data): _add_effect_icon("sealed")
		if has_modifier("sluggish") and not can_attack(_manager().turn): _add_effect_icon("resting")
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## The one keyword on the face: printed first, then buff-granted Piercing/Sluggish, then boss Taunt.
func _face_keyword() -> String:
	if not modifiers.is_empty(): return modifiers[0]
	for passive in ["piercing", "sluggish"]:
		if has_modifier(passive): return passive
	if card_data.get("boss_role", "") == "taunt": return "taunt"
	return ""

func _add_effect_icon(kind: String, stacks: int = 0) -> void:
	if _status_row.get_child_count() >= 19:
		var overflow := _status_row.get_node_or_null("More")
		if overflow:
			var count := overflow.get_child(0) as Label
			count.text = str(int(count.text) + 1)
			return
		kind = "more"
		stacks = 1
	var badge := TextureRect.new()
	badge.name = kind.capitalize().replace(" ", "")
	badge.texture = UI.icon(kind)
	badge.custom_minimum_size = Vector2(18, 18)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_status_row.add_child(badge)
	if stacks > 0:
		var count := _face_label(UI.font(true), 10, UI.TEXT)
		count.text = str(stacks)
		count.position = Vector2(10, 8)
		UI.outline(count)
		badge.add_child(count)

## Overlay mode: draw on top of the 3D world (hand / dragging).
func _set_overlay(on: bool) -> void:
	scale = Vector3.ONE * (_manager().HAND_SCALE if on else _manager().BOARD_SCALE)
	art_sprite.no_depth_test = on
	mesh.visible = not on
	art_sprite.position.y = 0.012 if not on else 0.0

func set_layer(layer: int) -> void:
	art_sprite.render_priority = clampi(layer, -100, 100)

# ---------------------------------------------------------------- hand motion
## Called by the manager to place the card in the fanned hand (camera-local).
func move_in_hand(pos: Vector3, basis_target: Basis, layer: int) -> void:
	set_meta("hand_pos", pos)
	set_meta("hand_basis", basis_target)
	set_meta("hand_layer", layer)
	if is_hovered:
		_apply_hover()
	else:
		set_layer(layer)
		_tween_local(pos, basis_target, 0.25)

func _tween_local(pos: Vector3, b: Basis, dur: float) -> void:
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var origin := position
	_tween.tween_method(func(t: float): position = origin.lerp(pos, t), 0.0, 1.0, dur)
	_tween.tween_property(self, "quaternion", b.get_rotation_quaternion(), dur)

const HOVER_LIFT := Vector3(0, 0.20, 0.02)

func _apply_hover() -> void:
	set_layer(100)
	var pos: Vector3 = get_meta("hand_pos", position)
	_tween_local(_manager().hand_position_below_slots(self, pos + HOVER_LIFT, UPRIGHT), UPRIGHT, 0.14)

func set_hand_hover(hovered: bool) -> void:
	if is_hovered == hovered: return
	is_hovered = hovered
	if not in_hand or is_dragging: return
	if hovered: _apply_hover()
	elif has_meta("hand_pos"):
		set_layer(get_meta("hand_layer", 0))
		_tween_local(get_meta("hand_pos"), get_meta("hand_basis"), 0.15)

func _on_mouse_entered() -> void:
	# The manager handles hand hover using stable footprints and visual stacking order.
	pass

func _on_mouse_exited() -> void:
	pass

# ---------------------------------------------------------------- dragging
func _input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _n: Vector3, _idx: int) -> void:
	if not Engine.is_editor_hint() and not in_hand and is_alive() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _manager().board_input.click_card(self): _manager().run_director.begin_inspect_hold(self)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if is_relocating and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_manager().board_input.cancel()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_manager().complete_move_effect(_slot_under_card())
			return
	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_hand_drag()
		return
	if is_dragging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		_manager().end_hand_drag(self)
		_drop_card()

func cancel_hand_drag() -> void:
	is_dragging = false
	_manager().end_hand_drag(self)
	in_hand = true
	current_slot = null
	reparent(_manager().hand_parent(), true)
	_manager().arrange_hand_centered()

func _start_drag() -> void:
	if not _manager().begin_hand_drag(self): return
	is_dragging = true
	if _tween: _tween.kill()
	set_layer(100)
	reparent(_manager(), true)
	global_position = _manager().clamp_drag_position(global_position)
	_manager().arrange_hand_centered()

func current_face_signature() -> int:
	if preview_only: return hash([card_data, statuses, modifiers])
	return hash([card_data, statuses, modifiers, effective_attack(), planned_guard, plan_ignore_taunt, can_attack(_manager().turn), _manager().is_sealed(card_data)])

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	# Direct damage/status methods refresh immediately. This bounded fallback
	# catches external buffs/turn changes without hashing every card every frame.
	face_check_elapsed += delta
	if face_check_elapsed >= FACE_CHECK_INTERVAL:
		face_check_elapsed = fmod(face_check_elapsed, FACE_CHECK_INTERVAL)
		if not card_data.is_empty() and current_face_signature() != face_signature: _refresh_face()
	if not is_dragging:
		return
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 1.6).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit != null:
		global_position = global_position.lerp(_manager().clamp_drag_position(hit), 1.0 - exp(-20.0 * delta))
	global_position = _manager().clamp_drag_position(global_position)
	# Always face the player while held
	var target_q := (cam.global_basis * UPRIGHT).get_rotation_quaternion()
	quaternion = quaternion.slerp(target_q, 1.0 - exp(-15.0 * delta))

func _drop_card() -> void:
	var slot := _slot_under_card()
	# Player may only use their own (Response) row, an empty slot, with enough energy
	if slot and "Response" in slot.name and not _slot_occupied(slot) and _manager().try_play_card(self):
		if card_data.get("utility", false):
			if _manager().try_utility(self, slot): return
			in_hand = true
			reparent(_manager().hand_parent(), true)
			_manager().arrange_hand_centered()
			return
		place_on_slot(slot)
		_manager().on_card_played(self)
	else:
		# Return to hand
		in_hand = true
		current_slot = null
		reparent(_manager().hand_parent(), true)
		_manager().arrange_hand_centered()

## Puts the card face-up on a board slot with a small arc + landing squash.
func place_on_slot(slot: Node3D) -> void:
	in_hand = false
	current_slot = slot
	_set_overlay(false)
	set_layer(0)
	_refresh_face()
	if _tween: _tween.kill()
	var land := slot.global_position + Vector3(0, 0.02, 0)
	var mid := global_position.lerp(land, 0.5) + Vector3(0, 0.5, 0)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "global_position", mid, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "quaternion", Quaternion.IDENTITY, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.chain().tween_property(self, "global_position", land, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * _manager().BOARD_SCALE * 1.08, 0.06)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * _manager().BOARD_SCALE, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

## Disaster cards: flip in face-down from above the slot and slam down.
func enter_from_above(slot: Node3D) -> void:
	in_hand = false
	current_slot = slot
	_set_overlay(false)
	set_layer(0)
	var land := slot.global_position + Vector3(0, 0.02, 0)
	global_position = land + Vector3(0, 1.8, -0.6)
	rotation = Vector3(0, 0, PI)          # face down
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "global_position", land, 0.42).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "rotation", Vector3.ZERO, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * _manager().BOARD_SCALE * 1.1, 0.05)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * _manager().BOARD_SCALE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await _tween.finished

func _slot_under_card() -> Node3D:
	return _manager().slot_at_screen_position(get_viewport().get_mouse_position())

func _slot_occupied(slot: Node3D) -> bool:
	for c in get_tree().get_nodes_in_group("cards"):
		if c != self and c.current_slot == slot:
			return true
	return false

func _manager() -> Node:
	return get_tree().current_scene

# ---------------------------------------------------------------- combat
func is_alive() -> bool:
	if card_data.get("utility", false): return in_hand and not graveyard_recorded
	return card_data.get("health", 0) > 0

## Wind-up, then lunge at `target`. Returns at the moment of impact
## (await it), the recoil back home keeps playing on its own.
func attack_lunge(target: Vector3) -> void:
	if _tween: _tween.kill()
	var home := current_slot.global_position + Vector3(0, 0.02, 0) if current_slot else global_position
	var dir := target - home
	dir.y = 0.0
	var fwd := dir.normalized()
	var tilt := 0.35 * signf(dir.z)
	_tween = create_tween()
	# Wind-up: rise, pull back, lean in
	_tween.set_parallel(true)
	_tween.tween_property(self, "global_position", home + Vector3(0, 0.45, 0) - fwd * 0.3, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "rotation:x", -tilt, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	# Strike
	_tween.chain().tween_property(self, "global_position", home + dir * 0.6 + Vector3(0, 0.08, 0), 0.09).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "rotation:x", tilt * 0.6, 0.09)
	await _tween.finished
	# Recoil home
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "global_position", home, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "rotation:x", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _battle_context() -> Dictionary:
	return {} if preview_only else BattleQueries.context(_manager())

func has_modifier(mod_name: String) -> bool:
	return BattleEngine.has_modifier(_battle_context(), BattleQueries.card(null, self), mod_name)

func add_modifier(mod_name: String) -> void:
	if not has_modifier(mod_name):
		modifiers.append(mod_name.to_lower())
		_refresh_face()
		spawn_popup("+" + mod_name.to_upper(), UI.GOLD)

func heal(amt: int) -> void:
	if card_data.get("utility", false): return
	if card_data.health <= 0: return
	if int(statuses.get("healing_reduced", 0)) > 0: amt = maxi(1, floori(amt / 2.0))
	var before: int = card_data.health
	card_data.health = mini(max_health, card_data.health + amt)
	if card_data.health > before: _manager().log_event("%s heals %d HP." % [card_data.name, card_data.health - before])
	_refresh_face()
	spawn_popup("+%d HP" % amt, UI.RESPONSE)

func sacrifice_dissolve() -> void:
	_manager().sacrifice_reward(self)
	_manager().record_graveyard(self, "Sacrificed")
	current_slot = null
	remove_from_group("cards")
	if _tween: _tween.kill()
	set_target_pulse(false)
	mesh.visible = false
	spawn_popup("SACRIFICED", UI.DANGER)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art_sprite, "modulate", Color(UI.CRIMSON, 0.0), 0.45)
	_tween.tween_property(self, "global_position", global_position + Vector3(0, 0.6, 0), 0.45).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.45).set_ease(Tween.EASE_IN)
	await _tween.finished
	queue_free()

func discard_to_pile() -> void:
	in_hand = false
	input_ray_pickable = false
	collision_layer = 0
	if _tween: _tween.kill()
	reparent(_manager().hand_parent(), true)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "position", Vector3(-2.6, -0.9, -3.0), 0.32)
	_tween.tween_property(self, "scale", Vector3.ONE * 0.08, 0.32)
	_tween.tween_property(art_sprite, "modulate:a", 0.0, 0.32)
	await _tween.finished
	queue_free()

## mult = type-effectiveness multiplier (for the popup text).
func adjusted_damage(amt: int, ignore_armor: bool = false) -> int:
	return BattleEngine.adjusted_damage(
		BattleQueries.context(_manager()), BattleQueries.card(null, self), amt, ignore_armor)

func take_damage(amt: int, mult: float = 1.0, bypass_armor: bool = false, ignore_armor: bool = false) -> void:
	if card_data.get("utility", false): return
	last_evaded_hit = false
	if not bypass_armor: amt = adjusted_damage(amt, ignore_armor)
	else: amt = _manager().incoming_damage(card_data.type == "response", amt)
	if not bypass_armor and planned_guard > 0:
		var prevented := mini(planned_guard, amt)
		amt -= prevented
		planned_guard = 0
		_manager().log_event("Brace prevents %d damage to %s." % [prevented, card_data.name])
	if not bypass_armor and int(statuses.get("barrier", 0)) > 0:
		var absorbed := mini(int(statuses.barrier), amt)
		statuses.barrier = int(statuses.barrier) - absorbed
		amt -= absorbed
	if amt <= 0:
		spawn_popup("BARRIER", UI.RESPONSE)
		_refresh_face()
		return

	if not bypass_armor and _manager().plans.try_extract(self, amt): return
	card_data.health = card_data.health - amt
	_manager().log_event("%s takes %d damage (%d/%d HP)." % [card_data.name, amt, maxi(0, card_data.health), max_health])
	_refresh_face()

	var popup := "-%d" % amt
	var col := UI.DANGER
	if mult > 1.0:
		popup += "\nSUPER!"
		col = UI.AMBER
	elif mult < 1.0:
		popup += "\nresisted"
		col = UI.MUTED
	spawn_popup(popup, col)

	# Red flash + wobble
	var flash := create_tween()
	art_sprite.modulate = UI.DANGER
	flash.tween_property(art_sprite, "modulate", Color.WHITE, 0.35)

	if card_data.health <= 0:
		_die()
		return
	var home := current_slot.global_position + Vector3(0, 0.02, 0) if current_slot else global_position
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation:z", 0.18, 0.04)
	_tween.tween_property(self, "rotation:z", -0.14, 0.07)
	_tween.tween_property(self, "rotation:z", 0.07, 0.06)
	_tween.tween_property(self, "rotation:z", 0.0, 0.06)
	_tween.parallel().tween_property(self, "global_position", home, 0.2)

func _die() -> void:
	_manager().record_graveyard(self, "Destroyed")
	current_slot = null   # frees the slot immediately
	remove_from_group("cards")
	if _tween: _tween.kill()
	set_target_pulse(false)
	mesh.visible = false
	var dissolve := ShaderMaterial.new()
	dissolve.shader = preload("res://assets/card_dissolve.gdshader")
	dissolve.set_shader_parameter("card_face", _vp.get_texture())
	art_sprite.material_override = dissolve
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art_sprite, "modulate", UI.CRIMSON.darkened(0.5), 0.15)
	_tween.tween_property(self, "global_position", global_position + Vector3(0, 0.6, 0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "rotation", Vector3(0.4, 0.0, randf_range(-1.2, 1.2)), 0.5)
	_tween.tween_method(func(amount: float): dissolve.set_shader_parameter("progress", amount), 0.0, 1.0, 0.65)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(art_sprite, "modulate:a", 0.0, 0.25)
	await _tween.finished
	queue_free()

## Floating text that rises and fades above this card.
func spawn_popup(text: String, col: Color) -> void:
	var now := Time.get_ticks_msec()
	popup_stack = (popup_stack + 1) % 4 if now - last_popup_msec < 250 else 0
	last_popup_msec = now
	var l := Label3D.new()
	l.font = UI.font(true)
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0025
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(UI.BACKGROUND, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 120
	l.outline_render_priority = 119
	_manager().add_child(l)
	l.global_position = global_position + Vector3(0, 0.3 + popup_stack * 0.22, 0)
	l.scale = Vector3.ONE * 0.4
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector3.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(l, "global_position", l.global_position + Vector3(0, 0.9, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.3)
	t.chain().tween_callback(l.queue_free)

func effective_attack() -> int:
	var game: Node = null if preview_only else _manager()
	return BattleEngine.effective_attack(_battle_context(), BattleQueries.card(game, self))

func refresh_cost() -> void:
	_refresh_face()

## Gold blink while this card is a valid board pick target (Coordinated Response, Brace, Rally...).
## Safe to call every frame.
func set_target_pulse(on: bool) -> void:
	if on == (_pulse_tween != null): return
	if on:
		# Bound to this card, so the tween ends when the card is freed.
		_pulse_tween = _manager().blink_tween(self, art_sprite, "modulate", UI.GOLD, Color.WHITE)
	else:
		_pulse_tween.kill()
		_pulse_tween = null
		art_sprite.modulate = Color.WHITE

func set_plan_attack_bonus(amount: int) -> void:
	plan_attack_bonus = amount
	_refresh_face()

func can_attack(round_number: int) -> bool:
	return BattleEngine.can_attack(_battle_context(), BattleQueries.card(null, self), round_number)

func add_status(status: String, amount: int) -> void:
	_manager().log_event("%s gains %d %s." % [card_data.name, amount, status.capitalize()])
	if not is_alive() or amount <= 0: return
	statuses[status] = mini(3, int(statuses.get(status, 0)) + amount) if status == "barrier" else int(statuses.get(status, 0)) + amount
	_refresh_face()
	spawn_popup("%s +%d" % [status.to_upper(), amount], UI.DANGER if status != "strength" else UI.RESPONSE)

func status_upkeep() -> void:
	if card_data.get("utility", false): return
	for status in ["burn", "poison"]:
		var stacks := int(statuses.get(status, 0))
		if stacks > 0 and is_alive():
			statuses[status] = floori(stacks / 2.0) if status == "burn" else stacks - 1
			take_damage(stacks, 1.0, true)
	var regen: int = int(_manager().buffs_for(card_data).get("regen", 0)) + (1 if has_modifier("regenerating") else 0)
	if is_alive() and regen > 0: heal(regen)
	if int(statuses.get("healing_reduced", 0)) > 0: statuses.healing_reduced = int(statuses.healing_reduced) - 1
	_refresh_face()

func after_attack(round_number: int) -> void:
	last_attack_turn = round_number
	var stacks := int(statuses.get("bleed", 0))
	if stacks > 0 and is_alive():
		statuses.bleed = stacks - 1
		take_damage(stacks, 1.0, true)
	_refresh_face()

func cleanse() -> void:
	for status in ["burn", "poison", "bleed", "healing_reduced"]: statuses.erase(status)
	heal(3)
	_refresh_face()

static func _card_back() -> Texture2D:
	if back_texture: return back_texture
	var img := Image.create(132, 180, false, Image.FORMAT_RGB8)
	img.fill(UI.INSET)
	var gold := UI.GOLD
	for x in range(6, 126):
		img.set_pixel(x, 6, gold)
		img.set_pixel(x, 173, gold)
	for y in range(6, 174):
		img.set_pixel(6, y, gold)
		img.set_pixel(125, y, gold)
	for y in range(180):
		for x in range(132):
			var distance := Vector2(x - 66, y - 90).length()
			if absf(distance - 31) < 1.2 or absf(distance - 26) < 0.7:
				img.set_pixel(x, y, gold)
	# Corner marks: flame, wave, fault, and spiral; no front illustration.
	for y in range(-9, 10):
		for x in range(-9, 10):
			if abs(x) < floori((9 - y) / 3.0) and y > -8: img.set_pixel(22 + x, 24 + y, UI.AFFINITIES.fire)
			if absf(y - sin(x * 0.5) * 3) < 1.5 or absf(y - sin(x * 0.5) * 3 - 5) < 1: img.set_pixel(109 + x, 24 + y, UI.AFFINITIES.flood)
			if abs(x - (3 if y < 0 else -3)) <= 1: img.set_pixel(22 + x, 155 + y, UI.AFFINITIES.earthquake)
			var radius := Vector2(x, y).length()
			if absf(radius - 7) < 1 or radius < 2: img.set_pixel(109 + x, 155 + y, UI.AFFINITIES.typhoon)
	back_texture = ImageTexture.create_from_image(img)
	return back_texture
