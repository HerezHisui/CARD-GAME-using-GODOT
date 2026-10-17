@tool
extends Area3D
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

const ELEMENT_COLORS := UI.AFFINITIES

## Intentionally blank until final artwork is supplied.
const ART := {}
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
var _hp_label: Label
var _atk_label: Label
var _mod_label: Label
var _cost_label: Label
var _status_row: VBoxContainer
var _cost_caption: Label
var face_signature := 0
const FACE_CHECK_INTERVAL := 0.1
var face_check_elapsed := 0.0
var popup_stack := 0
var last_popup_msec := -1000

@onready var art_sprite: Sprite3D = $Art
@onready var mesh: MeshInstance3D = $Mesh

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
	if not preview_only: card_data = _manager().prepare_card_data(card_data)
	# JSON numbers load as floats -> normalise to ints
	for k in ["cost", "attack", "health"]:
		card_data[k] = int(card_data.get(k, 0))
	max_health = card_data.health
	modifiers.clear()
	statuses.clear()
	last_attack_turn = -1
	graveyard_recorded = false
	if int(card_data.get("strength", 0)) > 0: statuses.strength = int(card_data.strength)
	var self_bleed: int = 0 if preview_only else int(_manager().buffs_for(card_data).get("self_bleed", 0))
	if self_bleed > 0: statuses.bleed = self_bleed
	if card_data.has("modifier") and str(card_data.modifier) != "":
		modifiers.append(str(card_data.modifier).to_lower())

	for card_modifier in card_data.get("modifiers", []):
		if str(card_modifier).to_lower() not in modifiers: modifiers.append(str(card_modifier).to_lower())

	_build_face()
	art_sprite.texture = _vp.get_texture()
	art_sprite.pixel_size = CARD_WIDTH / FACE_W
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
	_vp.size = Vector2i(FACE_W, FACE_H)
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
	_status_row = VBoxContainer.new()
	_status_row.position = Vector2(22, 264)
	_status_row.size = Vector2(FACE_W - 44, 14)
	_status_row.add_theme_constant_override("separation", 2)
	frame.add_child(_status_row)
	var art_path: String = ART.get(card_data.get("name", ""), "")
	if art_path != "":
		var tr := TextureRect.new()
		tr.texture = load(art_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = art_bg.size
		tr.clip_contents = true
		art_bg.clip_contents = true
		art_bg.add_child(tr)

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

	# Modifiers banner (below element)
	_mod_label = _face_label(title_font, 11, UI.GOLD)
	_mod_label.position = Vector2(10, 250)
	_mod_label.size = Vector2(FACE_W - 20, 13)
	_mod_label.max_lines_visible = 1
	_mod_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(_mod_label)

	# Attack (bottom-left) / Health (bottom-right)
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

	if _hp_label:
		_hp_label.text = str(maxi(card_data.health, 0))
		_hp_label.add_theme_color_override("font_color", UI.DANGER if card_data.health < max_health else UI.TEXT)
	if _atk_label:
		_atk_label.text = str(effective_attack())
	if _status_row:
		for child in _status_row.get_children():
			_status_row.remove_child(child)
			child.queue_free()
		var active: Array = statuses.keys().filter(func(key): return int(statuses[key]) > 0)
		var row: HBoxContainer
		for i in mini(active.size(), 3):
			if i % 3 == 0:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 3)
				_status_row.add_child(row)
			var tag := _face_label(UI.font(true), 10, UI.TEXT)
			var status := str(active[i])
			var names := {"strength":"Str", "healing_reduced":"Heal cut"}
			tag.text = "%s %d" % [names.get(status, status.replace("_", " ").capitalize()), int(statuses[status])]
			if i == 2 and active.size() > 3: tag.text = "%d more" % (active.size() - 2)
			tag.custom_minimum_size.x = 68
			tag.clip_text = true
			tag.add_theme_stylebox_override("normal", UI.panel(UI.INSET, UI.AMBER, 1))
			row.add_child(tag)
	if _mod_label:
		_mod_label.text = ""
		if card_data.get("utility", false):
			var effect: String = card_data.get("effect", "")
			_mod_label.text = "UTILITY · " + str(preload("res://scripts/battle_rules.gd").EFFECT_LABELS.get(effect, effect)).to_upper()
			_mod_label.visible = true
		elif modifiers.size() > 0:
			_mod_label.text = "[" + " · ".join(modifiers).to_upper() + "]"
			_mod_label.visible = true
		else:
			_mod_label.visible = false
		var tokens: PackedStringArray = []
		if planned_guard > 0: tokens.append("PLAN: BRACE")
		if plan_attack_bonus > 0: tokens.append("PLAN: +%d ATK" % plan_attack_bonus)
		if plan_ignore_taunt or card_data.get("ignore_taunt", false): tokens.append("IGNORE TAUNT")
		if card_data.get("curse", false): tokens.append("CURSE: PAY 1 HP")
		for status in card_data.get("on_hit", {}): tokens.append("HIT %s %d" % [str(status).to_upper(), int(card_data.on_hit[status])])
		if not card_data.get("utility", false) and card_data.get("effect", "") == "draw": tokens.append("PLAY: DRAW %d" % int(card_data.get("draw_count", 1)))
		if card_data.get("effect", "") == "move_ally": tokens.append("PLAY: MOVE AN ALLY")
		if card_data.get("effect", "") == "heal_all": tokens.append("PLAY: HEAL ALLIES 2")
		if card_data.get("effect", "") == "rally_all": tokens.append("PLAY: ALLIES +1 STR")
		if card_data.get("effect", "") == "grave_guard": tokens.append("PLAY: GRAVEYARD BARRIER (MAX 2)")
		if int(card_data.get("leech", 0)) > 0: tokens.append("HEAL ON HIT %d" % int(card_data.leech))
		if int(card_data.get("on_play_draw", 0)) > 0: tokens.append("PLAY DRAW +%d" % int(card_data.on_play_draw))
		if int(card_data.get("thorns", 0)) > 0: tokens.append("RETALIATE %d" % int(card_data.thorns))
		if int(card_data.get("status_bonus", 0)) > 0: tokens.append("TARGET STATUS 3+: +%d ATK" % int(card_data.status_bonus))
		if int(card_data.get("armor_value", 1)) > 1: tokens.append("ARMOR %d" % int(card_data.armor_value))
		if int(card_data.get("utility_power", 0)) > 0: tokens.append("ENHANCED +%d" % int(card_data.utility_power))
		if int(card_data.get("refund_energy", 0)) > 0: tokens.append("REFUND %d ENERGY" % int(card_data.refund_energy))
		if card_data.has("condition"):
			var condition: Dictionary = card_data.condition
			var subject := "SELF" if condition.get("subject", "target") == "self" else "TARGET"
			var status := "STATUS" if condition.get("status", "any") == "any" else str(condition.status).to_upper()
			var bonus := "2 STRIKES" if int(condition.get("strikes", 1)) > 1 else "+%d ATK" % int(condition.get("bonus", 0))
			tokens.append("%s %s %d+: %s" % [subject, status, int(condition.get("threshold", 3)), bonus])
		for passive in ["piercing", "sluggish"]:
			if has_modifier(passive) and passive not in modifiers: tokens.append(passive.to_upper())
		if not preview_only and int(card_data.get("locked_until", 0)) > _manager().turn: tokens.append("SEALED")
		if has_modifier("sluggish") and not can_attack(_manager().turn): tokens.append("RESTING")
		if not tokens.is_empty():
			_mod_label.text = (_mod_label.text + "\n" if _mod_label.visible else "") + " · ".join(tokens)
			_mod_label.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## Overlay mode: draw on top of the 3D world (hand / dragging).
func _set_overlay(on: bool) -> void:
	scale = Vector3.ONE * (_manager().HAND_SCALE if on else _manager().BOARD_SCALE)
	art_sprite.no_depth_test = on
	mesh.visible = not on
	art_sprite.position.y = 0.012 if not on else 0.0

func set_layer(priority: int) -> void:
	art_sprite.render_priority = clampi(priority, -100, 100)

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
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.DOWN * 5.0)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res and res.collider:
		var p = res.collider.get_parent()
		if p is MeshInstance3D and "Slot" in p.name:
			return p
	return null

func _slot_occupied(slot: Node3D) -> bool:
	for c in get_tree().get_nodes_in_group("cards"):
		if c != self and c.current_slot == slot:
			return true
	return false

func _manager() -> Node:
	return get_tree().current_scene

# ---------------------------------------------------------------- combat
func is_alive() -> bool:
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

func has_modifier(mod_name: String) -> bool:
	var key := mod_name.to_lower()
	return key in modifiers or (not preview_only and key in ["piercing", "sluggish"] and int(_manager().buffs_for(card_data).get(key, 0)) > 0)

func add_modifier(mod_name: String) -> void:
	if not has_modifier(mod_name):
		modifiers.append(mod_name.to_lower())
		_refresh_face()
		spawn_popup("+" + mod_name.to_upper(), UI.GOLD)

func heal(amt: int) -> void:
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
func adjusted_damage(amt: int) -> int:
	# Armored: takes 1 less damage from all attacks
	if has_modifier("armored"):
		amt = maxi(1, amt - int(card_data.get("armor_value", 1)))
	# Fragile: takes 1 extra damage from all attacks
	if has_modifier("fragile"):
		amt += 1
	return _manager().incoming_damage(card_data.type == "response", amt)

func take_damage(amt: int, mult: float = 1.0, bypass_armor: bool = false) -> void:
	last_evaded_hit = false
	if not bypass_armor: amt = adjusted_damage(amt)
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
	if preview_only and card_data.has("preview_attack"): return int(card_data.preview_attack)
	return maxi(0, int(card_data.get("attack", 0)) + int(statuses.get("strength", 0)) + plan_attack_bonus + (0 if preview_only else _manager().attack_bonus(self)))

func refresh_cost() -> void:
	_refresh_face()

func can_attack(round_number: int) -> bool:
	return is_alive() and (not has_modifier("sluggish") or last_attack_turn < 0 or round_number - last_attack_turn >= 2)

func add_status(status: String, amount: int) -> void:
	_manager().log_event("%s gains %d %s." % [card_data.name, amount, status.capitalize()])
	if not is_alive() or amount <= 0: return
	statuses[status] = mini(3, int(statuses.get(status, 0)) + amount) if status == "barrier" else int(statuses.get(status, 0)) + amount
	_refresh_face()
	spawn_popup("%s +%d" % [status.to_upper(), amount], UI.DANGER if status != "strength" else UI.RESPONSE)

func status_upkeep() -> void:
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
			if abs(x) < (9 - y) / 3 and y > -8: img.set_pixel(22 + x, 24 + y, ELEMENT_COLORS.fire)
			if absf(y - sin(x * 0.5) * 3) < 1.5 or absf(y - sin(x * 0.5) * 3 - 5) < 1: img.set_pixel(109 + x, 24 + y, ELEMENT_COLORS.flood)
			if abs(x - (3 if y < 0 else -3)) <= 1: img.set_pixel(22 + x, 155 + y, ELEMENT_COLORS.earthquake)
			var radius := Vector2(x, y).length()
			if absf(radius - 7) < 1 or radius < 2: img.set_pixel(109 + x, 155 + y, ELEMENT_COLORS.typhoon)
	back_texture = ImageTexture.create_from_image(img)
	return back_texture
