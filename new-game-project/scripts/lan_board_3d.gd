extends Node
## LAN client board: the same 3D table the host plays on, drawn from the views the host sends.
## The client keeps no rules. It shows the view, reads the mouse and presses the signals of the 2D panel
## (hand_pressed, lane_pressed, tactic_pressed, end_turn_pressed). lan_session.gd turns those into actions.
## The 2D panel stays mounted but hidden, so it still gets every view. Cards here are preview-only Card3D nodes
## outside the "cards" group, so no host rule and no game script can touch them.

const UI = preload("res://scripts/ui_theme.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
const VersusHud = preload("res://scripts/versus_hud.gd")
const Janitor = preload("res://scripts/janitor_character.gd")
const Card3DScene = preload("res://scenes/card_3d.tscn")

# DESK_VIEW seen from the far side of the table, the Disaster seat.
const SEAT_VIEW := {"pos": Vector3(0, 1.0, 0.4), "rot": Vector3(-30, 180, 0), "dist": 5.3, "fov": 60.0}
const SEAT_HAND_DROP := 0.26
const DRAG_START_PIXELS := 8.0
const NOTE_SECONDS := 2.6
const HAND_SCALE_HOVER := 1.3
const FOE_HAND_MAX := 10
const BACK_CARD := {"name": "Card", "type": "response", "element": "evac", "cost": 0, "attack": 0, "health": 1}
const REASONS := {"busy": "Wait, the host is still playing."}

var game: Node
var director: Node
var session: Node
var panel: Control
var cover: Control
var side := "disaster"
var flipped := false
var shown := false
var over := false
var view: Dictionary = {}
var hand_root: Node3D
var foe_root: Node3D
var hand_cards: Array[Node3D] = []
var foe_cards: Array[Node3D] = []
var lane_cards := {"response": [null, null, null, null], "disaster": [null, null, null, null]}
var hovered := -1
var held := -1
var dragging := false
var selected := -1
var selected_tactic := ""
var chosen: Array = []
var press_pos := Vector2.ZERO
var mouse := Vector2.ZERO
var lane_material: StandardMaterial3D
var saved := {"hud": true, "slots": [], "hand": true, "game": false}

var disaster_plans: Button
var disaster_grave: Button
var grave_note: PanelContainer
var janitor: Node3D
var foe_resource: PanelContainer
var foe_resource_label: Label
var foe_pips: Control
var hud: Control
var foe_plate: Dictionary
var me_plate: Dictionary
var turn_plate: PanelContainer
var round_label: Label
var turn_label: Label
var lane_inspection: PanelContainer
var inspected_lane: Node3D
var resource_plate: PanelContainer
var resource_label: Label
var pips: Control
var pips_cap := 0
var pips_value := 0
var end_button: Button
var draw_button: Button
var tactic_box: VBoxContainer
var note: PanelContainer
var note_head: Label
var note_body: Label
var note_tween: Tween
var over_box: PanelContainer
var over_label: Label


func setup(manager: Node, owner_director: Node, lan_session: Node, lan_panel: Control, seat: String,
		cover_rect: Control = null) -> void:
	game = manager
	director = owner_director
	session = lan_session
	panel = lan_panel
	cover = cover_rect
	side = seat
	flipped = seat == "disaster"
	hand_root = Node3D.new()
	game.camera.add_child(hand_root)
	foe_root = Node3D.new()
	game.camera.add_child(foe_root)
	_build_hud()
	session.view_received.connect(_on_view)
	session.event_received.connect(_on_event)
	session.match_over.connect(_on_match_over)
	if not session.last_view.is_empty():
		_on_view(session.last_view)


func _exit_tree() -> void:
	if is_instance_valid(janitor): janitor.queue_free()
	if is_instance_valid(hand_root):
		hand_root.queue_free()
	if is_instance_valid(foe_root):
		foe_root.queue_free()
	if not shown or not is_instance_valid(game):
		return
	var slots: Array = game._threat_slots() + game._response_slots()
	for index in slots.size():
		slots[index].visible = saved.slots[index]
		slots[index].material_override = null
	for lane_side in lane_cards:
		for card in lane_cards[lane_side]:
			if is_instance_valid(card):
				card.queue_free()
	game._apply_view(game.view_settings(game.view_mode))
	game.visible = saved.game
	var hud_layer: Node = game.get_node_or_null("HUD")
	if hud_layer:
		hud_layer.visible = saved.hud
	game.opponent_hand.visible = saved.hand


# ------------------------------------------------------------------- views
func _on_view(new_view: Dictionary) -> void:
	view = new_view
	_cancel_pick(false)
	if not shown:
		_reveal()
	_sync_lanes()
	_sync_hand()
	_sync_foe()
	_refresh_hud()


## The first view turns the table on: the 2D cover and panel go, the camera takes the seat.
func _reveal() -> void:
	shown = true
	panel.visible = false
	saved.game = game.visible
	game.visible = true
	if is_instance_valid(cover):
		cover.visible = false
	var hud_layer: Node = game.get_node_or_null("HUD")
	if hud_layer:
		saved.hud = hud_layer.visible
		hud_layer.visible = false
	saved.hand = game.opponent_hand.visible
	game.opponent_hand.visible = false
	for slot: Node3D in game._threat_slots() + game._response_slots():
		saved.slots.append(slot.visible)
	if game.camera_tween:
		game.camera_tween.kill()
	var camera_view: Dictionary = SEAT_VIEW if flipped else game.view_settings(game.view_mode)
	if VersusMatch.SIDE_BY_SIDE_CAMERA: camera_view = VersusMatch.seat_camera(flipped)
	game._apply_view(camera_view)
	hud.visible = true
	if VersusMatch.SIDE_BY_SIDE_HUD:
		janitor = Janitor.new()
		game.add_child(janitor)
		janitor.transform = game.opponent_hand.character.global_transform
		janitor.set_fixed_pose(true)
		janitor.set_encounter(true)


func _on_event(kind: String, data: Dictionary) -> void:
	if kind != "reject":
		return
	var reason := str(data.get("reason", ""))
	show_note("Refused", REASONS.get(reason, reason.replace("_", " ").capitalize()))


func _on_match_over(winner: String) -> void:
	over = true
	held = -1
	dragging = false
	_cancel_pick(false)
	var won := winner == side
	over_label.text = "VICTORY" if won else "DEFEAT"
	over_label.add_theme_color_override("font_color", UI.GOLD if won else UI.DANGER)
	over_box.visible = true
	end_button.disabled = true


func _own_side() -> String:
	return "response" if side == "preparedness" else "disaster"


func _my_turn() -> bool:
	return not over and bool(view.get("is_prep_turn" if side == "preparedness" else "is_disaster_turn", false))


func _slots(lane_side: String) -> Array:
	return game._response_slots() if lane_side == "response" else game._threat_slots()


# ------------------------------------------------------------------- cards
func _make_card(definition: Dictionary, parent: Node) -> Node3D:
	var card: Node3D = Card3DScene.instantiate()
	card.preview_only = true
	parent.add_child(card)
	card.input_ray_pickable = false
	card.setup(definition)
	return card


func _apply_runtime(card: Node3D, entry: Dictionary) -> void:
	var runtime: Dictionary = entry.get("runtime", {})
	card.card_data = entry.definition.duplicate(true)
	card.max_health = int(runtime.get("max_health", card.max_health))
	card.statuses = runtime.get("statuses", {}).duplicate()
	card.modifiers.assign(runtime.get("modifiers", []))
	card.planned_guard = int(runtime.get("planned_guard", 0))
	card.plan_attack_bonus = int(runtime.get("plan_attack_bonus", 0))
	card.plan_ignore_taunt = bool(runtime.get("plan_ignore_taunt", false))
	card._refresh_face()


func _sync_lanes() -> void:
	for lane_side: String in ["response", "disaster"]:
		var slots: Array = _slots(lane_side)
		for lane in 4:
			var id: String = view.lanes[lane_side][lane]
			var current: Node3D = lane_cards[lane_side][lane]
			if id == "":
				if current != null:
					_remove_lane_card(lane_side, lane)
				continue
			var entry: Dictionary = view.cards[id]
			if current != null and current.card_data.get("name") == entry.definition.get("name"):
				_apply_runtime(current, entry)
				continue
			if current != null:
				_remove_lane_card(lane_side, lane)
			var card := _make_card(entry.definition, game)
			_apply_runtime(card, entry)
			lane_cards[lane_side][lane] = card
			_land(card, slots[lane])


## A card drops onto its lane. From the far seat it lies turned half a circle, so it reads upright.
func _land(card: Node3D, slot: Node3D) -> void:
	card.in_hand = false
	card.current_slot = slot
	card._set_overlay(false)
	card.set_layer(0)
	var rest := slot.global_position + Vector3(0, 0.008, 0)
	card.scale = Vector3.ONE * game.BOARD_SCALE
	var yaw := PI if flipped else 0.0
	if VersusMatch.SIDE_BY_SIDE_CAMERA: yaw = VersusMatch.lane_yaw(flipped)
	card.rotation = Vector3(0, yaw, 0)
	card.global_position = rest + Vector3(0, 1.0, 0)
	var tween := card.create_tween()
	tween.tween_property(card, "global_position", rest, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(card, "scale", Vector3.ONE * game.BOARD_SCALE * 1.08, 0.06)
	tween.tween_property(card, "scale", Vector3.ONE * game.BOARD_SCALE, 0.14).set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_BACK)


func _remove_lane_card(lane_side: String, lane: int) -> void:
	var card: Node3D = lane_cards[lane_side][lane]
	lane_cards[lane_side][lane] = null
	var tween := card.create_tween()
	tween.tween_property(card, "scale", Vector3.ONE * 0.01, 0.18)
	tween.tween_callback(card.queue_free)


## One Card3D per hand card, in hand order. A card that is still in the hand keeps its node.
func _sync_hand() -> void:
	var ids: Array = view.get("prep_hand" if side == "preparedness" else "disaster_hand", [])
	var pool: Array[Node3D] = hand_cards.duplicate()
	var next: Array[Node3D] = []
	for id: String in ids:
		var definition: Dictionary = view.cards[id].definition
		var found: Node3D = null
		for card in pool:
			if card.get_meta("def") == definition:
				found = card
				break
		if found != null:
			pool.erase(found)
		else:
			found = _make_card(definition, hand_root)
			found.set_meta("def", definition)
			found.position = Vector3(2.6, -0.6, -game.HAND_DIST)
			found.transform.basis = game.UPRIGHT.scaled(Vector3.ONE * game.HAND_SCALE)
		next.append(found)
	for card in pool:
		card.queue_free()
	hand_cards = next
	hovered = -1
	held = -1
	dragging = false
	_arrange_hand()


## Tight, overlapping, upright fan along the bottom of the screen, like the host's hand.
func _arrange_hand() -> void:
	var count := hand_cards.size()
	var spacing := minf(0.6, 3.4 / maxf(1.0, count))
	var drop := SEAT_HAND_DROP if flipped else 0.0
	for i in count:
		var n := i - (count - 1) / 2.0
		var pos := Vector3(n * spacing, game.HAND_Y - drop - n * n * 0.012, -game.HAND_DIST + i * 0.002)
		var card_basis: Basis = Basis(Vector3.BACK, deg_to_rad(-n * 2.5)) * game.UPRIGHT
		var card := hand_cards[i]
		card.set_meta("hand_slot_pos", pos)
		card.set_meta("hand_slot_basis", card_basis)
		var usable := _usable(i)
		card.art_sprite.modulate = Color.WHITE if usable or not _my_turn() else Color(0.55, 0.55, 0.6)
		if i == held and dragging:
			continue
		var smooth: bool = VersusMatch.SIDE_BY_SIDE_HUD and side == "disaster"
		if i == hovered or i == selected:
			card.move_in_hand(pos + card.HOVER_LIFT, game.UPRIGHT, 100, 0.14 if smooth else 0.25)
		else:
			card.move_in_hand(pos, card_basis, i, 0.15 if smooth else 0.25)


## Opponent cards stay private; the enemy plate shows hand and deck counts instead.
func _sync_foe() -> void:
	for card in foe_cards: card.queue_free()
	foe_cards.clear()


# ------------------------------------------------------------------- hints
func _hint(index: int) -> Dictionary:
	var hints: Array = view.get("hints", [])
	return hints[index] if index >= 0 and index < hints.size() else {}


func _usable(index: int) -> bool:
	if not _my_turn():
		return false
	return bool(_hint(index).get("can_play" if side == "preparedness" else "can_use", false))


func _is_spell(index: int) -> bool:
	return side == "disaster" and index >= 0 and index < hand_cards.size() \
		and bool(hand_cards[index].card_data.get("utility", false))


## The lanes of the player's own row a picked card or tactic may go to.
func _open_lanes_for(index: int) -> Array:
	if not _my_turn():
		return []
	var lanes: Array = []
	if side == "preparedness":
		if selected_tactic != "":
			for tactic: Dictionary in view.get("tactics", []):
				if tactic.id == selected_tactic:
					lanes = tactic.lanes.duplicate()
		elif index >= 0:
			lanes = _hint(index).get("lanes", []).duplicate()
	elif index >= 0 and not _is_spell(index):
		var hint := _hint(index)
		var sacrifices: Array = hint.get("sacrifices", [])
		lanes = (sacrifices if not sacrifices.is_empty() else hint.get("lanes", [])).duplicate()
	return lanes.filter(func(lane: int) -> bool: return lane not in chosen)


func _open_lanes() -> Array:
	return _open_lanes_for(held if dragging else selected)


# ------------------------------------------------------------------- mouse
func _input(event: InputEvent) -> void:
	if not shown or over:
		return
	# W and S would move the idle game's camera.
	if event is InputEventKey and event.keycode in [KEY_W, KEY_S]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		mouse = event.position
		if held >= 0 and not dragging and mouse.distance_to(press_pos) > DRAG_START_PIXELS:
			dragging = true
			hand_cards[held].set_layer(100)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_on_release(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_pick(true)
		held = -1
		dragging = false
		_arrange_hand()


func _unhandled_input(event: InputEvent) -> void:
	if not shown or over:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_press(event.position)


func _on_press(point: Vector2) -> void:
	mouse = point
	var index := _hand_at(point)
	if index >= 0:
		if not _usable(index):
			_explain(index)
			return
		held = index
		dragging = false
		press_pos = point
		return
	var lane := _lane_at(point)
	if lane >= 0:
		click_lane(lane)


func _on_release(point: Vector2) -> void:
	if held < 0:
		return
	var index := held
	var was_drag := dragging
	held = -1
	dragging = false
	if not was_drag:
		click_hand(index)
		return
	if _is_spell(index):
		if point.y < get_viewport().get_visible_rect().size.y * 0.72:
			click_hand(index)
			return
	else:
		var lane := _lane_at(point)
		if lane >= 0 and lane in _open_lanes_for(index):
			click_hand(index)
			click_lane(lane)
			return
	_arrange_hand()


func _process(delta: float) -> void:
	if not shown:
		return
	# The director hides the game every frame outside a battle. This runs after it, because it is a child.
	game.visible = true
	_layout_hud()
	if dragging and held >= 0 and held < hand_cards.size():
		_follow_mouse(hand_cards[held], delta)
	else:
		mouse = get_viewport().get_mouse_position()
		_update_hover()
	for i in hand_cards.size():
		var grow := HAND_SCALE_HOVER if i == hovered or i == selected else 1.0
		var target: Vector3 = Vector3.ONE * game.HAND_SCALE * grow
		hand_cards[i].scale = hand_cards[i].scale.lerp(target, 1.0 - exp(-16.0 * delta))
	_update_lanes()
	_update_lane_inspection()


func _update_hover() -> void:
	var index := _hand_at(mouse) if not over else -1
	if index == hovered:
		return
	hovered = index
	_arrange_hand()


func _update_lane_inspection() -> void:
	var foe := "response" if side == "disaster" else "disaster"
	var lane := _lane_at(mouse, foe) if not dragging and hovered < 0 and not over else -1
	var card: Node3D = lane_cards[foe][lane] if lane >= 0 else null
	if card == inspected_lane: return
	inspected_lane = card
	if is_instance_valid(lane_inspection): lane_inspection.queue_free()
	if not is_instance_valid(card): return
	lane_inspection = PanelContainer.new()
	lane_inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane_inspection.add_theme_stylebox_override("panel", _plate_style(UI.GOLD))
	hud.add_child(lane_inspection)
	var face := TextureRect.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.texture = card._vp.get_texture()
	face.custom_minimum_size = Vector2(220, 310)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lane_inspection.add_child(face)
	lane_inspection.position = Vector2(hud.size.x - 250, 220)


func _follow_mouse(card: Node3D, delta: float) -> void:
	var origin: Vector3 = game.camera.project_ray_origin(mouse)
	var hit: Variant = Plane(Vector3.UP, 1.6).intersects_ray(origin, game.camera.project_ray_normal(mouse))
	if hit != null:
		card.global_position = card.global_position.lerp(game.clamp_drag_position(hit), 1.0 - exp(-20.0 * delta))
	card.global_position = game.clamp_drag_position(card.global_position)


## The screen outline of a hand card. A raised card uses where it is now, the others where they rest.
func _polygon(index: int, raised: bool) -> PackedVector2Array:
	var card := hand_cards[index]
	var card_transform: Transform3D = card.global_transform
	if not raised:
		card_transform = hand_root.global_transform * Transform3D(
			card.get_meta("hand_slot_basis").scaled(Vector3.ONE * game.HAND_SCALE), card.get_meta("hand_slot_pos"))
	var polygon := PackedVector2Array()
	for corner in [Vector2(-0.55, -1), Vector2(0.55, -1), Vector2(0.55, 1), Vector2(-0.55, 1)]:
		var point := Vector3(corner.x, 0, corner.y * card.card_height / 2)
		polygon.append(game.camera.unproject_position(card_transform * point))
	return polygon


func _hand_at(point: Vector2) -> int:
	for index in [hovered, selected]:
		if index >= 0 and index < hand_cards.size() and Geometry2D.is_point_in_polygon(point, _polygon(index, true)):
			return index
	for index in range(hand_cards.size() - 1, -1, -1):
		if index == held and dragging:
			continue
		if hand_cards[index].has_meta("hand_slot_pos") and Geometry2D.is_point_in_polygon(point, _polygon(index, false)):
			return index
	return -1


## The lane of the player's own row under a screen point. Same ray and plane test the host uses.
func _lane_at(point: Vector2, lane_side: String = "") -> int:
	var slots := _slots(_own_side() if lane_side.is_empty() else lane_side)
	for lane in slots.size():
		var slot: Node3D = slots[lane]
		var plane := Plane(Vector3.UP, slot.global_position.y)
		var hit: Variant = plane.intersects_ray(game.camera.project_ray_origin(point),
			game.camera.project_ray_normal(point))
		if hit == null:
			continue
		var local: Vector3 = slot.to_local(hit)
		var bounds: AABB = slot.get_aabb()
		if local.x >= bounds.position.x and local.x <= bounds.end.x \
				and local.z >= bounds.position.z and local.z <= bounds.end.z:
			return lane
	return -1


func _update_lanes() -> void:
	var open := _open_lanes()
	var slots := _slots(_own_side())
	for lane in slots.size():
		var lit := lane in open
		if slots[lane].visible == lit:
			continue
		slots[lane].visible = lit
		slots[lane].material_override = _lane_look() if lit else null


func _lane_look() -> StandardMaterial3D:
	if lane_material == null:
		lane_material = StandardMaterial3D.new()
		lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lane_material.albedo_color = Color(UI.GOLD, 0.35)
		game.blink_tween(self, lane_material, "albedo_color", Color(UI.GOLD, 0.6), Color(UI.GOLD, 0.15))
	return lane_material


# ------------------------------------------------------------------- actions
## Pick a hand card. A spell casts at once, a unit waits for a lane. Picking it again lets it go.
func click_hand(index: int) -> void:
	if over or index < 0 or index >= hand_cards.size():
		return
	if not _usable(index):
		_explain(index)
		return
	if selected == index and not _is_spell(index):
		_cancel_pick(true)
		return
	selected = index
	selected_tactic = ""
	chosen.clear()
	_arrange_hand()
	panel.hand_pressed.emit(index)


func click_lane(lane: int) -> void:
	if over or (selected < 0 and selected_tactic == ""):
		return
	if lane not in _open_lanes_for(selected):
		show_note("Pick a lit lane", "")
		return
	chosen.append(lane)
	panel.lane_pressed.emit(lane)


func click_tactic(id: String) -> void:
	if over or not _my_turn():
		return
	selected = -1
	selected_tactic = id
	chosen.clear()
	_arrange_hand()
	panel.tactic_pressed.emit(id)


func click_end() -> void:
	if over or not _my_turn():
		return
	_cancel_pick(false)
	panel.end_turn_pressed.emit()


func _cancel_pick(tell_session: bool) -> void:
	var had := selected >= 0 or selected_tactic != ""
	selected = -1
	selected_tactic = ""
	chosen.clear()
	if had and tell_session:
		panel.hand_pressed.emit(-1)
	if had:
		_arrange_hand()


func _explain(index: int) -> void:
	if not _my_turn():
		show_note("Not your turn", "")
		return
	var problem := str(_hint(index).get("problem", ""))
	show_note("Can't play that", problem if problem != "" else "Not now.")


# ------------------------------------------------------------------- HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.name = "LanBoardHud"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = director.root.theme
	hud.visible = false
	add_child(hud)
	if VersusMatch.SIDE_BY_SIDE_HUD:
		var top := Panel.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		top.offset_bottom = 52.0
		top.add_theme_stylebox_override("panel", game.get_node("HUD/TopBar").get_theme_stylebox("panel"))
		hud.add_child(top)
	foe_plate = _hp_plate(UI.CRIMSON)
	me_plate = _hp_plate(UI.ACTION)
	_place(foe_plate.box, Control.PRESET_TOP_LEFT, Vector2(16, 12))
	_place(me_plate.box, Control.PRESET_BOTTOM_LEFT, Vector2(16, -92))
	# Round and turn, top centre.
	turn_plate = PanelContainer.new()
	turn_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_plate.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
	turn_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_plate.offset_top = 8
	hud.add_child(turn_plate)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	turn_plate.add_child(row)
	round_label = _label(row, 18, UI.MUTED)
	turn_label = _label(row, 20, UI.GOLD)
	# Energy or Tension under the player's own HP.
	resource_plate = PanelContainer.new()
	resource_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_plate.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
	hud.add_child(resource_plate)
	_place(resource_plate, Control.PRESET_BOTTOM_LEFT, Vector2(16, -52))
	var resource_row := HBoxContainer.new()
	resource_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_row.add_theme_constant_override("separation", 10)
	resource_plate.add_child(resource_row)
	resource_label = _label(resource_row, 18, UI.TEXT)
	pips = Control.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.custom_minimum_size = Vector2(150, 24)
	pips.draw.connect(_draw_pips)
	resource_row.add_child(pips)
	if VersusMatch.SIDE_BY_SIDE_HUD:
		foe_resource = PanelContainer.new()
		foe_resource.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foe_resource.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
		hud.add_child(foe_resource)
		var row_foe := HBoxContainer.new()
		row_foe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_foe.add_theme_constant_override("separation", 10)
		foe_resource.add_child(row_foe)
		foe_resource_label = _label(row_foe, 18, UI.TEXT)
		foe_pips = Control.new()
		foe_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foe_pips.custom_minimum_size = Vector2(150, 24)
		foe_pips.draw.connect(_draw_foe_pips)
		row_foe.add_child(foe_pips)
	# End turn, bottom right. The tactic list sits above it for a Preparedness player.
	end_button = director.button("END TURN", click_end, hud)
	end_button.name = "EndTurnButton"
	end_button.add_theme_font_size_override("font_size", 22)
	end_button.custom_minimum_size = Vector2(190, 58)
	_place(end_button, Control.PRESET_BOTTOM_RIGHT, Vector2(-206, -76))
	draw_button = director.button("DRAW", _draw_pressed, hud)
	draw_button.name = "ClientDrawButton"
	draw_button.custom_minimum_size = Vector2(190, 58)
	_place(draw_button, Control.PRESET_BOTTOM_RIGHT, Vector2(-206, -146))
	tactic_box = VBoxContainer.new()
	tactic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tactic_box)
	_place(tactic_box, Control.PRESET_CENTER_RIGHT, Vector2(-206, -60))
	_build_note()
	_build_over()
	_build_disaster_controls()


func _place(control: Control, preset: int, offset: Vector2) -> void:
	control.set_anchors_preset(preset)
	control.grow_horizontal = Control.GROW_DIRECTION_END if offset.x >= 0 else Control.GROW_DIRECTION_BEGIN
	control.grow_vertical = Control.GROW_DIRECTION_END if offset.y >= 0 else Control.GROW_DIRECTION_BEGIN
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x
	control.offset_bottom = offset.y


func _plate_style(border: Color, width: int = 1, margin: int = 8) -> StyleBoxFlat:
	var frame := UI.panel(UI.PANEL, border, 0)
	frame.set_corner_radius_all(3)
	frame.set_border_width_all(width)
	frame.content_margin_left = margin + 2
	frame.content_margin_right = margin + 2
	frame.content_margin_top = maxi(margin - 4, 2)
	frame.content_margin_bottom = maxi(margin - 4, 2)
	return frame


func _label(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI.font(size >= 22))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


## A plate with a name, an HP bar and one line of small print.
func _hp_plate(fill_color: Color) -> Dictionary:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
	plate.custom_minimum_size = Vector2(300, 0)
	hud.add_child(plate)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	plate.add_child(box)
	var title := _label(box, 18, UI.GOLD)
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 24)
	box.add_child(bar)
	var back := ColorRect.new()
	back.color = UI.INSET
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(back)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(fill)
	var value := _label(bar, 18, UI.TEXT)
	value.set_anchors_preset(Control.PRESET_FULL_RECT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var small := _label(box, 15, UI.MUTED)
	return {"box": plate, "title": title, "fill": fill, "value": value, "small": small}


func _build_note() -> void:
	note = PanelContainer.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_stylebox_override("panel", _plate_style(UI.ACTION, 2, 14))
	note.set_anchors_preset(Control.PRESET_CENTER_TOP)
	note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note.offset_top = 70
	note.custom_minimum_size = Vector2(340, 0)
	note.modulate.a = 0.0
	note.visible = false
	hud.add_child(note)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(box)
	note_head = _label(box, 30, UI.DANGER)
	note_body = _label(box, 18, UI.TEXT)
	note_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_over() -> void:
	over_box = PanelContainer.new()
	over_box.add_theme_stylebox_override("panel", _plate_style(UI.GOLD, 3, 24))
	over_box.set_anchors_preset(Control.PRESET_CENTER)
	over_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	over_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	over_box.custom_minimum_size = Vector2(420, 0)
	over_box.visible = false
	hud.add_child(over_box)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	over_box.add_child(box)
	over_label = _label(box, 64, UI.GOLD)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var back: Button = director.button("Back to title", func() -> void: panel.back_pressed.emit(), box)
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(200, 52)


func show_note(head: String, body: String) -> void:
	note_head.text = head
	note_body.text = body
	note_body.visible = body != ""
	note.visible = true
	note.modulate.a = 1.0
	if note_tween:
		note_tween.kill()
	note_tween = create_tween()
	note_tween.tween_interval(NOTE_SECONDS)
	note_tween.tween_property(note, "modulate:a", 0.0, 0.4)
	note_tween.tween_callback(func() -> void: note.visible = false)


func _draw_pressed() -> void:
	if side != "preparedness" or view.get("turn_side", "") != side or view.get("phase", "") != "draw": return
	session.request_action({"kind": "draw"})


func _refresh_hud() -> void:
	var sides: Dictionary = view.sides
	var mine := _own_side()
	var foe := "disaster" if mine == "response" else "response"
	var counts: Dictionary = view.get("counts", {})
	_set_plate(me_plate, sides[mine], "YOU - " + side.to_upper())
	_set_plate(foe_plate, sides[foe], ("DISASTER" if foe == "disaster" else "PREPAREDNESS"))
	var foe_hand := int(counts.get("disaster_hand" if side == "preparedness" else "response_hand", 0))
	var foe_deck := int(counts.get("disaster_draw" if side == "preparedness" else "response_draw", 0))
	foe_plate.small.text = "Hand %d   Deck %d" % [foe_hand, foe_deck]
	var barrier := int(sides[mine].get("barrier", 0))
	me_plate.small.text = ("Barrier %d" % barrier) if barrier > 0 else ""
	me_plate.small.visible = barrier > 0
	round_label.text = "ROUND %d" % int(view.get("round", 1))
	var phase := str(view.get("phase", "play" if _my_turn() else "end")).to_upper()
	var own_turn: bool = view.get("turn_side", side if _my_turn() else "") == side
	turn_label.text = ("YOUR TURN" if own_turn else "OPPONENT'S TURN") + " · " + phase
	turn_label.add_theme_color_override("font_color", UI.GOLD if own_turn else UI.MUTED)
	end_button.disabled = not _my_turn()
	draw_button.visible = side == "preparedness"
	draw_button.disabled = not own_turn or phase != "DRAW"
	if side == "preparedness":
		resource_label.text = "ENERGY"
		pips_value = int(view.get("energy", 0))
		pips_cap = int(view.get("energy_cap", 0))
	else:
		resource_label.text = "TENSION"
		pips_value = int(sides.disaster.resource)
		pips_cap = int(sides.disaster.resource_cap)
	pips.queue_redraw()
	if VersusMatch.SIDE_BY_SIDE_HUD:
		foe_resource_label.text = "TENSION" if side == "preparedness" else "ENERGY"
		foe_pips.queue_redraw()
		foe_plate.title.add_theme_font_size_override("font_size", 14)
		foe_plate.title.text += "   Hand %d   Deck %d" % [foe_hand, foe_deck]
		foe_plate.box.tooltip_text = foe_plate.small.text
		me_plate.box.tooltip_text = me_plate.small.text
		me_plate.small.visible = false
		foe_plate.small.visible = false
		_layout_hud()
	if is_instance_valid(disaster_grave):
		disaster_grave.get_node("CountLabel").text = str(counts.get("disaster_graveyard", 0))
	_fill_tactics()


func _set_plate(plate: Dictionary, data: Dictionary, title: String) -> void:
	var hp := maxi(int(data.hp), 0)
	var max_hp := maxi(int(data.max_hp), 1)
	plate.title.text = title
	plate.fill.anchor_right = clampf(float(hp) / max_hp, 0.0, 1.0)
	plate.value.text = "%d / %d" % [hp, max_hp]


func _fill_tactics() -> void:
	for child in tactic_box.get_children():
		tactic_box.remove_child(child)
		child.queue_free()
	if side != "preparedness":
		return
	for tactic: Dictionary in view.get("tactics", []):
		var tactic_button: Button = director.button("%s (%d)" % [tactic.name, tactic.cost],
			click_tactic.bind(str(tactic.id)), tactic_box)
		tactic_button.name = "Tactic_" + str(tactic.id)
		tactic_button.disabled = not bool(tactic.available) or not _my_turn()


## One pip per point of the cap. Full = crimson with a gold rim, spent = dark. Energy pips are squares,
## Tension pips are diamonds.
func _draw_pips() -> void:
	_draw_resource(pips, pips_cap, pips_value, side == "preparedness")

func _draw_foe_pips() -> void:
	if view.is_empty(): return
	var foe: Dictionary = view.sides.disaster if side == "preparedness" else view.sides.response
	_draw_resource(foe_pips, int(foe.resource_cap), int(foe.resource), side != "preparedness")

func _draw_resource(target: Control, cap: int, value: int, energy: bool) -> void:
	if cap <= 0:
		return
	var gap := 6.0
	var size := clampf((target.size.x - gap * (cap - 1)) / cap, 10.0, 22.0)
	var top := (target.size.y - size) / 2.0
	for index in cap:
		var spot := Vector2(index * (size + gap), top)
		var lit := index < value
		var fill: Color = UI.ACTION if lit else UI.INSET
		var rim: Color = UI.GOLD if lit else UI.MUTED.darkened(0.35)
		if energy:
			var box := StyleBoxFlat.new()
			box.bg_color = fill
			box.border_color = rim
			box.set_border_width_all(2)
			target.draw_style_box(box, Rect2(spot, Vector2(size, size)))
		else:
			var middle := spot + Vector2(size, size) / 2.0
			var half := size / 2.0 + 2.0
			var shape := PackedVector2Array([middle + Vector2(0, -half), middle + Vector2(half, 0),
				middle + Vector2(0, half), middle + Vector2(-half, 0)])
			target.draw_colored_polygon(shape, fill)
			shape.append(shape[0])
			target.draw_polyline(shape, rim, 2.0)


func _layout_hud() -> void:
	if not VersusMatch.SIDE_BY_SIDE_HUD or not is_instance_valid(foe_resource): return
	var width := get_viewport().get_visible_rect().size.x
	for mine: bool in [true, false]:
		var plate: Control = me_plate.box if mine else foe_plate.box
		var resource: Control = resource_plate if mine else foe_resource
		var rect := VersusHud.health_rect(width, mine)
		plate.set_anchors_preset(Control.PRESET_TOP_LEFT)
		plate.custom_minimum_size = rect.size
		plate.size = rect.size
		plate.position = rect.position
		resource.set_anchors_preset(Control.PRESET_TOP_LEFT)
		resource.custom_minimum_size = Vector2(rect.size.x, 32)
		resource.size = resource.custom_minimum_size
		resource.position = rect.position + Vector2(0, rect.size.y + 6)


func _build_disaster_controls() -> void:
	if not VersusMatch.SIDE_BY_SIDE_HUD or side != "disaster": return
	disaster_plans = director.plans_button.duplicate(0)
	disaster_plans.name = "DisasterPlansButton"
	disaster_plans.icon = null
	var icon: TextureRect = disaster_plans.get_node("HubIcon")
	icon.texture = load("res://assets/ui/contingency_disaster.svg")
	icon.modulate = UI.GOLD
	disaster_plans.text = ""
	disaster_plans.get_node("CountLabel").text = ""
	disaster_plans.disabled = false
	disaster_plans.visible = true
	hud.add_child(disaster_plans)
	disaster_plans.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	disaster_plans.position = Vector2(hud.size.x - 116, hud.size.y - 72)
	disaster_plans.size = Vector2(100, 56)
	disaster_plans.pressed.connect(show_note.bind("Coming later", "Disaster plans are coming later."))
	disaster_grave = director.graveyard_button.duplicate(0)
	disaster_grave.name = "DisasterGraveyardButton"
	disaster_grave.visible = true
	disaster_grave.disabled = false
	hud.add_child(disaster_grave)
	disaster_grave.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	disaster_grave.position = Vector2(16, hud.size.y - 72)
	disaster_grave.size = Vector2(100, 56)
	disaster_grave.pressed.connect(show_disaster_graveyard)
	end_button.custom_minimum_size = Vector2(120, 56)
	end_button.size = Vector2(120, 56)
	end_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	end_button.offset_left = -244
	end_button.offset_right = -124
	end_button.offset_top = -72
	end_button.offset_bottom = -16

func show_disaster_graveyard() -> void:
	if is_instance_valid(grave_note): grave_note.queue_free()
	grave_note = PanelContainer.new()
	grave_note.name = "DisasterGraveyardNotice"
	grave_note.add_theme_stylebox_override("panel", _plate_style(UI.GOLD, 2, 16))
	hud.add_child(grave_note)
	var box := VBoxContainer.new()
	grave_note.add_child(box)
	_label(box, 26, UI.GOLD).text = "DISASTER GRAVEYARD"
	var count := int(view.get("counts", {}).get("disaster_graveyard", 0))
	_label(box, 20, UI.TEXT).text = "%d cards. Card list is unavailable on this client." % count
	director.button("Close", func() -> void: grave_note.queue_free(), box)
	grave_note.reset_size()
	grave_note.position = (hud.size - grave_note.size) * 0.5
