extends Area3D
## A single playable card.
## While in hand it is parented to the Camera3D so it always faces the player
## (like a classic 2D card game hand). While dragged it floats over the table
## facing the camera. When dropped on an empty slot it lies flat on the board.
##
## The card face (frame, art, name, stats) is drawn by a 2D Control tree inside
## a SubViewport and shown on the Art sprite, so the whole face is ONE texture
## and always layers correctly.

const CARD_WIDTH := 1.1
const UPRIGHT := Basis(Vector3.RIGHT, PI / 2.0) # card face (+Y) -> camera (+Z)
const FACE_W := 264
const FACE_H := 360

const ELEMENT_COLORS := {
	"fire": Color(0.75, 0.25, 0.1),
	"flood": Color(0.15, 0.35, 0.75),
	"earthquake": Color(0.5, 0.35, 0.2),
	"typhoon": Color(0.3, 0.55, 0.55),
	"douse": Color(0.2, 0.6, 0.85),
	"clearance": Color(0.8, 0.65, 0.15),
	"brace": Color(0.5, 0.5, 0.55),
	"evac": Color(0.2, 0.65, 0.3),
}

## Intentionally blank until final artwork is supplied.
const ART := {}
static var back_texture: Texture2D
static var face_font: SystemFont

var card_data: Dictionary
var is_dragging := false
var is_hovered := false
var in_hand := true
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

@onready var art_sprite: Sprite3D = $Art
@onready var mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# ---------------------------------------------------------------- setup
func setup(data: Dictionary) -> void:
	card_data = data.duplicate(true)
	card_data = _manager().prepare_card_data(card_data)
	# JSON numbers load as floats -> normalise to ints
	for k in ["cost", "attack", "health"]:
		card_data[k] = int(card_data.get(k, 0))
	max_health = card_data.health
	modifiers.clear()
	statuses.clear()
	last_attack_turn = -1
	if int(card_data.get("strength", 0)) > 0: statuses.strength = int(card_data.strength)
	var self_bleed: int = int(_manager().buffs_for(card_data).get("self_bleed", 0))
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

	_set_overlay(true)

func _build_face() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(FACE_W, FACE_H)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)

	var elem: String = card_data.get("element", "")
	var accent: Color = ELEMENT_COLORS.get(elem, Color(0.4, 0.4, 0.4))
	var is_disaster: bool = card_data.get("type", "") == "disaster"

	if not face_font:
		face_font = SystemFont.new()
		face_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
		face_font.font_weight = 600
	var title_font := face_font

	# Frame
	var frame := Panel.new()
	frame.size = Vector2(FACE_W, FACE_H)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color("162936") if not is_disaster else Color("302029")
	fs.set_border_width_all(4)
	fs.border_color = accent.lightened(0.15)
	fs.set_corner_radius_all(14)
	frame.add_theme_stylebox_override("panel", fs)
	_vp.add_child(frame)

	var text_col := Color("e9e3d6")

	# Name
	var name_lbl := _face_label(title_font, 19, text_col)
	name_lbl.text = card_data.get("name", "?")
	name_lbl.position = Vector2(56, 12)
	name_lbl.size = Vector2(FACE_W - 68, 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	frame.add_child(name_lbl)

	# Art window
	var art_bg := ColorRect.new()
	art_bg.color = Color("0e1922")
	art_bg.position = Vector2(18, 46)
	art_bg.size = Vector2(FACE_W - 36, 170)
	frame.add_child(art_bg)
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
	var eb := StyleBoxFlat.new()
	eb.bg_color = accent
	eb.set_corner_radius_all(6)
	elem_lbl.add_theme_stylebox_override("normal", eb)
	frame.add_child(elem_lbl)

	# Cost badge (top-left): blue = energy, red = sacrifice
	var cost_col := Color(0.2, 0.45, 0.9) if card_data.get("cost_type", "energy") == "energy" else Color(0.75, 0.12, 0.12)
	var cost_badge := _badge(str(card_data.cost), cost_col, Vector2(-6, -6), title_font)
	_cost_label = cost_badge.get_child(0)
	frame.add_child(cost_badge)

	# Modifiers banner (below element)
	_mod_label = _face_label(title_font, 11, Color(1, 0.9, 0.3))
	_mod_label.position = Vector2(10, 251)
	_mod_label.size = Vector2(FACE_W - 20, 28)
	_mod_label.max_lines_visible = 2
	_mod_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(_mod_label)

	# Attack (bottom-left) / Health (bottom-right)
	var atk := _badge(str(card_data.attack), Color(0.85, 0.45, 0.1), Vector2(16, FACE_H - 80), title_font)
	_atk_label = atk.get_child(0)
	frame.add_child(atk)
	var hp := _badge(str(card_data.health), Color(0.2, 0.6, 0.25), Vector2(FACE_W - 76, FACE_H - 80), title_font)
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
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(30)
	s.set_border_width_all(4)
	s.border_color = Color(0.1, 0.08, 0.06)
	p.add_theme_stylebox_override("panel", s)
	var l := _face_label(font, 26, Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.text = txt
	l.size = p.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _refresh_face() -> void:
	if _cost_label: _cost_label.text = str(card_data.cost)
	if _hp_label:
		_hp_label.text = str(maxi(card_data.health, 0))
		_hp_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6) if card_data.health < max_health else Color.WHITE)
	if _atk_label:
		_atk_label.text = str(effective_attack())
	if _mod_label:
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
		for status in card_data.get("on_hit", {}): tokens.append("HIT %s %d" % [str(status).to_upper(), int(card_data.on_hit[status])])
		if not card_data.get("utility", false) and card_data.get("effect", "") == "draw": tokens.append("PLAY: DRAW %d" % int(card_data.get("draw_count", 1)))
		if card_data.get("effect", "") == "move_ally": tokens.append("PLAY: MOVE AN ALLY")
		if card_data.get("effect", "") == "heal_all": tokens.append("PLAY: HEAL ALLIES 2")
		if card_data.get("effect", "") == "rally_all": tokens.append("PLAY: ALLIES +1 STR")
		if int(card_data.get("leech", 0)) > 0: tokens.append("HEAL ON HIT %d" % int(card_data.leech))
		var special: String = preload("res://scripts/battle_rules.gd").special_text(card_data)
		if special != "": tokens.append(special.replace("\n", " · "))
		for passive in ["piercing", "sluggish"]:
			if has_modifier(passive) and passive not in modifiers: tokens.append(passive.to_upper())
		for status in statuses:
			if int(statuses[status]) > 0: tokens.append("%s %d" % [str(status).to_upper(), int(statuses[status])])
		if int(card_data.get("locked_until", 0)) > _manager().turn: tokens.append("SEALED")
		if has_modifier("sluggish") and not can_attack(_manager().turn): tokens.append("RESTING")
		if not tokens.is_empty():
			_mod_label.text += "\n" + " · ".join(tokens) if _mod_label.visible else " · ".join(tokens)
			_mod_label.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## Overlay mode: draw on top of the 3D world (hand / dragging).
func _set_overlay(on: bool) -> void:
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
	_tween.tween_property(self, "position", pos, dur)
	_tween.tween_property(self, "quaternion", b.get_rotation_quaternion(), dur)

const HOVER_LIFT := Vector3(0, 0.95, 0.3)

func _apply_hover() -> void:
	set_layer(100)
	var pos: Vector3 = get_meta("hand_pos", position)
	_tween_local(pos + HOVER_LIFT, UPRIGHT, 0.14)

func _on_mouse_entered() -> void:
	is_hovered = true
	if in_hand and not is_dragging:
		_apply_hover()

func _on_mouse_exited() -> void:
	is_hovered = false
	if in_hand and not is_dragging and has_meta("hand_pos"):
		set_layer(get_meta("hand_layer", 0))
		_tween_local(get_meta("hand_pos"), get_meta("hand_basis"), 0.15)

# ---------------------------------------------------------------- dragging
func _input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _n: Vector3, _idx: int) -> void:
	if in_hand and not is_dragging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and _manager().can_player_act():
		_start_drag()

func _input(event: InputEvent) -> void:
	if is_dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		is_dragging = false
		in_hand = true
		current_slot = null
		reparent(_manager().hand_parent(), true)
		_manager().arrange_hand_centered()
		return
	if is_dragging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		is_dragging = false
		_drop_card()

func _start_drag() -> void:
	is_dragging = true
	if _tween: _tween.kill()
	set_layer(100)
	reparent(_manager(), true)
	_manager().arrange_hand_centered()

func _process(delta: float) -> void:
	if not is_dragging:
		return
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, 1.6).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit != null:
		global_position = global_position.lerp(hit, 1.0 - exp(-20.0 * delta))
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
	_tween.chain().tween_property(self, "scale", Vector3.ONE * 1.08, 0.06)
	_tween.chain().tween_property(self, "scale", Vector3.ONE, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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
	_tween.chain().tween_property(self, "scale", Vector3.ONE * 1.1, 0.05)
	_tween.chain().tween_property(self, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
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
	return key in modifiers or (key in ["piercing", "sluggish"] and int(_manager().buffs_for(card_data).get(key, 0)) > 0)

func add_modifier(mod_name: String) -> void:
	if not has_modifier(mod_name):
		modifiers.append(mod_name.to_lower())
		_refresh_face()
		spawn_popup("+" + mod_name.to_upper(), Color(1.0, 0.85, 0.3))

func heal(amt: int) -> void:
	if card_data.health <= 0: return
	card_data.health = mini(max_health, card_data.health + amt)
	_refresh_face()
	spawn_popup("+%d HP" % amt, Color(0.3, 1.0, 0.4))

func sacrifice_dissolve() -> void:
	current_slot = null
	remove_from_group("cards")
	if _tween: _tween.kill()
	mesh.visible = false
	spawn_popup("SACRIFICED", Color(1.0, 0.25, 0.1))
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art_sprite, "modulate", Color(0.8, 0.1, 0.05, 0.0), 0.45)
	_tween.tween_property(self, "global_position", global_position + Vector3(0, 0.6, 0), 0.45).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.45).set_ease(Tween.EASE_IN)
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
	return amt

func take_damage(amt: int, mult: float = 1.0, bypass_armor: bool = false) -> void:
	if not bypass_armor: amt = adjusted_damage(amt)

	card_data.health = card_data.health - amt
	_refresh_face()

	var popup := "-%d" % amt
	var col := Color(1, 0.35, 0.3)
	if mult > 1.0:
		popup += "\nSUPER!"
		col = Color(1, 0.85, 0.2)
	elif mult < 1.0:
		popup += "\nresisted"
		col = Color(0.7, 0.7, 0.75)
	spawn_popup(popup, col)

	# Red flash + wobble
	var flash := create_tween()
	art_sprite.modulate = Color(1, 0.3, 0.3)
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
	current_slot = null   # frees the slot immediately
	remove_from_group("cards")
	if _tween: _tween.kill()
	mesh.visible = false
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(art_sprite, "modulate", Color(0.25, 0.05, 0.02, 1.0), 0.15)
	_tween.tween_property(self, "global_position", global_position + Vector3(0, 0.6, 0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "rotation", Vector3(0.4, 0.0, randf_range(-1.2, 1.2)), 0.5)
	_tween.chain().tween_property(self, "scale", Vector3.ONE * 0.05, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(art_sprite, "modulate:a", 0.0, 0.25)
	await _tween.finished
	queue_free()

## Floating text that rises and fades above this card.
func spawn_popup(text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 120
	l.outline_render_priority = 119
	_manager().add_child(l)
	l.global_position = global_position + Vector3(0, 0.4, 0)
	l.scale = Vector3.ONE * 0.4
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector3.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(l, "global_position", l.global_position + Vector3(0, 0.9, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.3)
	t.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.3)
	t.chain().tween_callback(l.queue_free)

func effective_attack() -> int:
	return maxi(0, int(card_data.get("attack", 0)) + int(statuses.get("strength", 0)) + _manager().attack_bonus(self))

func refresh_cost() -> void:
	_refresh_face()

func can_attack(round_number: int) -> bool:
	return is_alive() and (not has_modifier("sluggish") or last_attack_turn < 0 or round_number - last_attack_turn >= 2)

func add_status(status: String, amount: int) -> void:
	if not is_alive() or amount <= 0: return
	statuses[status] = int(statuses.get(status, 0)) + amount
	_refresh_face()
	spawn_popup("%s +%d" % [status.to_upper(), amount], Color("da857c") if status != "strength" else Color("75d6c6"))

func status_upkeep() -> void:
	for status in ["burn", "poison"]:
		var stacks := int(statuses.get(status, 0))
		if stacks > 0 and is_alive():
			statuses[status] = floori(stacks / 2.0) if status == "burn" else stacks - 1
			take_damage(stacks, 1.0, true)
	var regen: int = int(_manager().buffs_for(card_data).get("regen", 0)) + (1 if has_modifier("regenerating") else 0)
	if is_alive() and regen > 0: heal(regen)
	_refresh_face()

func after_attack(round_number: int) -> void:
	last_attack_turn = round_number
	var stacks := int(statuses.get("bleed", 0))
	if stacks > 0 and is_alive():
		statuses.bleed = stacks - 1
		take_damage(stacks, 1.0, true)
	_refresh_face()

func cleanse() -> void:
	for status in ["burn", "poison", "bleed"]: statuses.erase(status)
	heal(3)
	_refresh_face()

static func _card_back() -> Texture2D:
	if back_texture: return back_texture
	var img := Image.create(132, 180, false, Image.FORMAT_RGB8)
	img.fill(Color("0c1925"))
	var gold := Color("c9aa70")
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
