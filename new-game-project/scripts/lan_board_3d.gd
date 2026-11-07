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
const Sfx = preload("res://scripts/sfx_call.gd")

# DESK_VIEW seen from the far side of the table, the Disaster seat.
const SEAT_VIEW := {"pos": Vector3(0, 1.0, 0.4), "rot": Vector3(-30, 180, 0), "dist": 5.3, "fov": 60.0}
const SEAT_HAND_DROP := 0.26
const DRAG_START_PIXELS := 8.0
const NOTE_SECONDS := 2.6
const HAND_SCALE_HOVER := 1.3
const REASONS := {"busy": "Wait, the host is still playing.", "not_supported": "Not available in LAN",
	"choice_pending": "Finish or cancel the open choice first.", "draw_first": "DRAW A CARD FIRST"}
# Flag on: the lane stages of an open utility choice. The other stages pick from a list.
const LANE_STAGES := ["ally", "field", "destination"]

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
var relocation_box: PanelContainer
var choice_box: PanelContainer
var forecast_box: PanelContainer
var foe_lit := false
var selected := -1
var selected_held := ""
var held_preview: Node3D
var evolution_play_sent := false
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
var foe_meter: Dictionary
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
var resource_meter: Dictionary
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
	if panel.has_method("setup_evolutions"):
		panel.setup_evolutions(director)
		panel.held_pressed.connect(_on_held_pressed)
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
	session.evolution_reset.connect(_reset_evolutions)
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
	if new_view.has("match_id") and new_view.match_id != view.get("match_id"):
		over = false
		over_box.hide()
	view = new_view
	_cancel_pick(false)
	if not shown:
		_reveal()
	_sync_lanes()
	_sync_hand()
	_sync_foe()
	_refresh_hud()
	_refresh_relocation()
	_refresh_choice()
	_refresh_forecast()


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
	_refresh_relocation()
	held = -1
	dragging = false
	_cancel_pick(false)
	_refresh_choice()
	var won := winner == side
	over_label.text = "VICTORY" if won else "DEFEAT"
	over_label.add_theme_color_override("font_color", UI.GOLD if won else UI.DANGER)
	over_box.visible = true
	end_button.disabled = true


func _own_side() -> String:
	return "response" if side == "preparedness" else "disaster"


func _my_turn() -> bool:
	return not over and not view.get("evolution_waiting", false) \
		and bool(view.get("is_prep_turn" if side == "preparedness" else "is_disaster_turn", false))


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


func _apply_runtime(card: Node3D, entry: Dictionary, own_side: bool = true) -> void:
	card.preview_seal_round = int(view.get("round", 1)) if own_side else -1
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
				_apply_runtime(current, entry, lane_side == _own_side())
				continue
			if current != null:
				_remove_lane_card(lane_side, lane)
			var card := _make_card(entry.definition, game)
			_apply_runtime(card, entry, lane_side == _own_side())
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
	# Own hand cards show the seal banner for the host's round, like the local seat.
	var view_round := int(view.get("round", 1))
	for card in hand_cards:
		if card.preview_seal_round != view_round:
			card.preview_seal_round = view_round
			card._refresh_face()
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
	if not view.get("relocation", {}).is_empty(): return false
	if not _my_turn():
		return false
	return bool(_hint(index).get("can_play" if side == "preparedness" else "can_use", false))


func _is_spell(index: int) -> bool:
	# Flag on: a Preparedness utility is cast like a Disaster spell, not placed in a lane.
	if side == "preparedness": return bool(_hint(index).get("utility", false))
	return side == "disaster" and index >= 0 and index < hand_cards.size() \
		and bool(hand_cards[index].card_data.get("utility", false))


## The lanes of the player's own row a picked card or tactic may go to.
func _open_lanes_for(index: int) -> Array:
	if not _my_turn():
		return []
	# Flag on: an open utility choice lights exactly the lanes of its stage.
	var open := _pending()
	if not open.is_empty(): return open.handles.duplicate() if open.stage in LANE_STAGES else []
	if side == "disaster" and not view.get("relocation", {}).is_empty(): return panel.relocation_lanes()
	if not selected_held.is_empty():
		if evolution_play_sent: return []
		return _held_entry().get("hints", {}).get("sacrifices", []).filter(func(lane): return lane not in chosen)
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


## The open utility choice from the newest view, or {}. Only a Preparedness view has one.
func _pending() -> Dictionary:
	return view.get("pending_choice", {}) if side == "preparedness" and not over else {}


## The row a lane press lands on. A Seal choice picks a Disaster card, everything else the player's own row.
func _pick_row() -> String:
	return "disaster" if _pending().get("stage", "") == "field" else ""


# ------------------------------------------------------------------- mouse
func _input(event: InputEvent) -> void:
	if not shown or over:
		return
	if _evolution_open() or view.get("evolution_waiting", false): return
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
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
			and not _pending().is_empty():
		# Esc closes the open choice first. It must not reach the leave-match menu.
		get_viewport().set_input_as_handled()
		_cancel_choice()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_pick(true)
		_cancel_choice()
		held = -1
		dragging = false
		_arrange_hand()


func _unhandled_input(event: InputEvent) -> void:
	if not shown or over:
		return
	if _evolution_open() or view.get("evolution_waiting", false): return
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
	var lane := _lane_at(point, _pick_row())
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
	var lane := _lane_at(mouse, foe) if not dragging and hovered < 0 and not over and not _evolution_open() else -1
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
		var lit := lane in open and _pick_row() == ""
		if slots[lane].visible == lit:
			continue
		slots[lane].visible = lit
		slots[lane].material_override = _lane_look() if lit else null
	# A Seal choice lights the Disaster row. That row is left alone at all other times.
	var foe_slots := _slots("disaster" if _own_side() == "response" else "response")
	var foe_open: bool = _pick_row() != "" and not open.is_empty()
	if not foe_open and not foe_lit: return
	for lane in foe_slots.size():
		var lit := foe_open and lane in open
		if foe_slots[lane].visible == lit:
			continue
		foe_slots[lane].visible = lit
		foe_slots[lane].material_override = _lane_look() if lit else null
	foe_lit = foe_open


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
	if _evolution_open() or view.get("evolution_waiting", false): return
	if over or index < 0 or index >= hand_cards.size():
		return
	if not _usable(index):
		_explain(index)
		return
	if selected == index and not _is_spell(index):
		_cancel_pick(true)
		return
	selected = index
	_clear_held_preview()
	selected_tactic = ""
	chosen.clear()
	_arrange_hand()
	panel.hand_pressed.emit(index)


func click_lane(lane: int) -> void:
	if _evolution_open() or view.get("evolution_waiting", false): return
	if side == "disaster" and not view.get("relocation", {}).is_empty():
		if over: return
		panel.pick_relocation(lane)
		_refresh_relocation()
		return
	var open := _pending()
	if not open.is_empty() and open.stage in LANE_STAGES:
		if lane not in open.handles:
			show_note("Pick a lit lane", "")
			return
		panel.lane_pressed.emit(lane)
		return
	if over or (selected < 0 and selected_tactic == "" and selected_held.is_empty()):
		return
	if lane not in _open_lanes_for(selected):
		show_note("Pick a lit lane", "")
		return
	chosen.append(lane)
	if not selected_held.is_empty() and chosen.size() >= int(_held_entry().get("card", {}).get("cost", 1)):
		evolution_play_sent = true
	panel.lane_pressed.emit(lane)


func _tactic_hint(id: String) -> Dictionary:
	for tactic: Dictionary in view.get("tactics", []):
		if str(tactic.id) == id: return tactic
	return {}


## Flag on: the host marks Supply Line, Shelter ("no_ally") and Extraction ("pick") as playable.
func _tactic_unsupported(id: String) -> bool:
	var hint := _tactic_hint(id)
	if hint.has("no_ally") or hint.has("pick"): return false
	return id in preload("res://scripts/preparedness_actions.gd").NOT_SUPPORTED_TACTICS


func click_tactic(id: String) -> void:
	if over or not _my_turn():
		return
	if not _pending().is_empty():
		show_note("Can't do that", REASONS.choice_pending)
		return
	if _tactic_unsupported(id):
		_on_event("reject", {"reason": "not_supported"})
		return
	selected = -1
	selected_tactic = id
	chosen.clear()
	_arrange_hand()
	panel.tactic_pressed.emit(id)


func click_end() -> void:
	if _evolution_open(): return
	if not view.get("relocation", {}).is_empty(): return
	if over or not _my_turn():
		return
	if not _pending().is_empty():
		show_note("Can't end the turn", REASONS.choice_pending)
		return
	_cancel_pick(false)
	panel.end_turn_pressed.emit()


func _cancel_pick(tell_session: bool) -> void:
	var had := selected >= 0 or selected_tactic != "" or not selected_held.is_empty()
	_clear_held_preview()
	selected = -1
	selected_tactic = ""
	chosen.clear()
	if had and tell_session:
		panel.hand_pressed.emit(-1)
	if had:
		_arrange_hand()


func _explain(index: int) -> void:
	# The Preparedness draw comes first. The host refuses a play then with the same text.
	if side == "preparedness" and str(view.get("phase", "")) == "draw" and not over:
		Sfx.play("invalid_action")
		show_note(REASONS.draw_first, "")
		return
	if not _my_turn():
		show_note("Not your turn", "")
		return
	var problem := str(_hint(index).get("problem", ""))
	show_note("Can't play that", REASONS.get(problem, problem if problem != "" else "Not now."))


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
	# Energy or Tension uses the same plate, fill and centered numbers as HP.
	resource_meter = _hp_plate(UI.ACTION)
	resource_plate = resource_meter.box
	resource_plate.mouse_filter = Control.MOUSE_FILTER_PASS
	resource_meter.small.hide()
	resource_label = resource_meter.title
	_place(me_plate.box, Control.PRESET_BOTTOM_LEFT, Vector2(16, -156))
	_place(resource_plate, Control.PRESET_BOTTOM_LEFT, Vector2(16, -80))
	if VersusMatch.SIDE_BY_SIDE_HUD:
		foe_meter = _hp_plate(UI.CRIMSON)
		foe_resource = foe_meter.box
		foe_resource.mouse_filter = Control.MOUSE_FILTER_PASS
		foe_meter.small.hide()
		foe_resource_label = foe_meter.title
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
	end_button.disabled = not _my_turn() or not view.get("relocation", {}).is_empty() or not _pending().is_empty()
	draw_button.visible = side == "preparedness"
	draw_button.disabled = not own_turn or phase != "DRAW"
	if view.get("evolution_waiting", false): draw_button.disabled = true
	if side == "preparedness":
		resource_label.text = "ENERGY"
		_set_resource(resource_meter, int(view.get("energy", 0)), int(view.get("energy_cap", 0)))
	else:
		resource_label.text = "TENSION"
		_set_resource(resource_meter, int(sides.disaster.resource), int(sides.disaster.resource_cap))
	if VersusMatch.SIDE_BY_SIDE_HUD:
		foe_resource_label.text = "TENSION" if side == "preparedness" else "ENERGY"
		var foe_data: Dictionary = sides.disaster if side == "preparedness" else sides.response
		_set_resource(foe_meter, int(foe_data.resource), int(foe_data.resource_cap))
		foe_plate.title.add_theme_font_size_override("font_size", 14)
		foe_plate.title.text += "   Hand %d   Deck %d" % [foe_hand, foe_deck]
		foe_plate.box.tooltip_text = foe_plate.small.text
		me_plate.box.tooltip_text = me_plate.small.text
		me_plate.small.visible = false
		foe_plate.small.visible = false
		_layout_hud()
	if is_instance_valid(disaster_grave):
		disaster_grave.get_node("CountLabel").text = str(counts.get("disaster_graveyard", 0))
	if is_instance_valid(disaster_plans) and view.has("held_evolutions"):
		disaster_plans.tooltip_text = "Evolution"
		disaster_plans.get_node("CountLabel").text = str(view.held_evolutions.size())
	if view.get("evolution_waiting", false): turn_label.text = "DISASTER CHOOSES AN EVOLUTION"
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
		var unsupported: bool = _tactic_unsupported(str(tactic.id))
		tactic_button.disabled = (not bool(tactic.available) and not unsupported) or not _my_turn()
		if unsupported: tactic_button.tooltip_text = REASONS.not_supported


## One pip per point of the cap. Full = crimson with a gold rim, spent = dark. Energy pips are squares,
## Tension pips are diamonds.
func _set_resource(meter: Dictionary, current: int, cap: int) -> void:
	current = maxi(current, 0)
	cap = maxi(cap, 0)
	meter.fill.anchor_right = clampf(float(current) / cap, 0.0, 1.0) if cap > 0 else 0.0
	meter.value.text = "%d / %d" % [current, cap]
	meter.box.tooltip_text = "%s: %d / %d" % [str(meter.title.text).capitalize(), current, cap]


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
		resource.custom_minimum_size = Vector2(rect.size.x, 0)
		resource.size = Vector2(rect.size.x, resource.get_combined_minimum_size().y)
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
	disaster_plans.pressed.connect(func() -> void:
		if view.has("held_evolutions"): panel.show_held_evolutions()
		else: show_note("Coming later", "Disaster plans are coming later."))
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
	# Flag on: the host sends the list. Flag off: only the count.
	if view.has("disaster_graveyard_list"):
		_fill_grave_list(box, view.disaster_graveyard_list)
	else:
		_label(box, 20, UI.TEXT).text = "%d cards. Card list is unavailable on this client." % count
	director.button("Close", func() -> void: grave_note.queue_free(), box)
	grave_note.reset_size()
	grave_note.position = (hud.size - grave_note.size) * 0.5


# The Disaster graveyard cards in the order the host sent them, each with its reason and round.
func _fill_grave_list(box: VBoxContainer, cards: Array) -> void:
	if cards.is_empty():
		_label(box, 20, UI.TEXT).text = "The graveyard is empty."
		return
	var scroll := ScrollContainer.new()
	scroll.name = "GraveList"
	scroll.custom_minimum_size = Vector2(minf(760, hud.size.x - 80), minf(420, hud.size.y - 220))
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	for entry: Dictionary in cards:
		director._card_tile(entry, grid)
		var reason := str(entry.get("graveyard_reason", "Destroyed"))
		var caption := _label(grid.get_child(-1).get_node("Box"), 14, UI.MUTED)
		caption.text = "%s · round %d" % [reason, int(entry.get("graveyard_round", 1))]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _refresh_relocation() -> void:
	if is_instance_valid(relocation_box):
		relocation_box.get_parent().remove_child(relocation_box)
		relocation_box.queue_free()
	relocation_box = null
	if side != "disaster" or over or view.get("relocation", {}).is_empty(): return
	relocation_box = PanelContainer.new()
	relocation_box.name = "CrosswindChoice"
	relocation_box.add_theme_stylebox_override("panel", _plate_style(UI.GOLD, 2, 12))
	hud.add_child(relocation_box)
	_place(relocation_box, Control.PRESET_CENTER_LEFT, Vector2(16, -80))
	var box := VBoxContainer.new()
	relocation_box.add_child(box)
	var title := _label(box, 24, UI.GOLD)
	title.text = "CROSSWIND"
	var prompt := _label(box, 18, UI.TEXT)
	prompt.text = "Choose an ally lane" if panel.relocation_ally < 0 else "Choose an empty lane"
	if panel.relocation_sent: prompt.text = "Waiting for the host..."
	for lane in panel.relocation_lanes():
		director.button("Lane %d" % (lane + 1), click_lane.bind(lane), box)


## Flag on: the box for the open utility choice. A prompt, a button per lane or list entry, and Cancel.
## Lane stages can also be picked on the lit table. Esc and right click cancel too.
func _refresh_choice() -> void:
	if is_instance_valid(choice_box):
		choice_box.get_parent().remove_child(choice_box)
		choice_box.queue_free()
	choice_box = null
	var open := _pending()
	if open.is_empty(): return
	choice_box = PanelContainer.new()
	choice_box.name = "UtilityChoice"
	choice_box.add_theme_stylebox_override("panel", _plate_style(UI.GOLD, 2, 12))
	hud.add_child(choice_box)
	_place(choice_box, Control.PRESET_CENTER_LEFT, Vector2(16, -80))
	var box := VBoxContainer.new()
	choice_box.add_child(box)
	_label(box, 24, UI.GOLD).text = str(open.name).to_upper()
	var prompt := _label(box, 18, UI.TEXT)
	prompt.name = "ChoicePrompt"
	prompt.text = str(open.prompt)
	prompt.custom_minimum_size = Vector2(300, 0)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if open.stage in LANE_STAGES:
		for lane: int in open.handles:
			var named := ""
			var lane_side := "disaster" if open.stage == "field" else "response"
			var lane_card: Node3D = lane_cards[lane_side][lane]
			if is_instance_valid(lane_card): named = " · " + str(lane_card.card_data.name)
			var lane_button: Button = director.button("Lane %d%s" % [lane + 1, named], click_lane.bind(lane), box)
			lane_button.name = "ChoiceLane%d" % lane
	var candidates: Array = open.get("candidates", [])
	if not candidates.is_empty():
		# Long lists scroll inside the viewport. The panel grows both ways from the center.
		var scroll := ScrollContainer.new()
		scroll.name = "ChoiceScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var entries := VBoxContainer.new()
		entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(entries)
		choice_box.grow_vertical = Control.GROW_DIRECTION_BOTH
		choice_box.offset_top = 0
		choice_box.offset_bottom = 0
		for entry: Dictionary in candidates:
			var text := "Hidden card %d" % (int(entry.handle) + 1)
			if entry.has("card"): text = str(entry.card.get("name", "?"))
			var entry_button: Button = director.button(text, _pick_candidate.bind(int(entry.handle)), entries)
			entry_button.name = "ChoiceEntry%d" % int(entry.handle)
		# Room for the title, prompt and Cancel stays outside the list.
		var row: float = entries.get_child(0).get_combined_minimum_size().y + 6.0
		scroll.custom_minimum_size.y = minf(row * candidates.size(), maxf(120.0, hud.size.y - 300.0))
	var cancel: Button = director.button("Cancel", _cancel_choice, box)
	cancel.name = "ChoiceCancel"


## Flag on, after Scout: the Disaster hand as it was when Hazard Forecast was cast. Preparedness view only.
func _refresh_forecast() -> void:
	if is_instance_valid(forecast_box):
		forecast_box.get_parent().remove_child(forecast_box)
		forecast_box.queue_free()
	forecast_box = null
	if side != "preparedness" or over or not view.has("disaster_hand_revealed"): return
	forecast_box = PanelContainer.new()
	forecast_box.name = "HazardForecast"
	forecast_box.add_theme_stylebox_override("panel", _plate_style(UI.GOLD, 2, 12))
	hud.add_child(forecast_box)
	_place(forecast_box, Control.PRESET_CENTER_RIGHT, Vector2(-16, -80))
	var box := VBoxContainer.new()
	forecast_box.add_child(box)
	_label(box, 24, UI.GOLD).text = "HAZARD FORECAST"
	var cards: Array = view.disaster_hand_revealed
	if cards.is_empty(): _label(box, 18, UI.TEXT).text = "The Disaster hand is empty."
	for card: Dictionary in cards:
		_label(box, 18, UI.TEXT).text = str(card.get("name", "?"))


func _pick_candidate(handle: int) -> void:
	if over or _pending().is_empty(): return
	panel.choice_picked.emit(handle)


func _cancel_choice() -> void:
	if _pending().is_empty(): return
	panel.choice_cancelled.emit()


func _evolution_open() -> bool:
	return is_instance_valid(panel) and panel.has_method("evolution_open") and panel.evolution_open()


func _held_entry() -> Dictionary:
	for entry in view.get("held_evolutions", []):
		if entry.id == selected_held: return entry
	return {}


func _on_held_pressed(id: String) -> void:
	if not _my_turn(): return
	_cancel_pick(false)
	selected_held = id
	var entry := _held_entry()
	if entry.is_empty():
		selected_held = ""
		return
	held_preview = _make_card(entry.card, hand_root)
	held_preview.transform = Transform3D(game.UPRIGHT.scaled(Vector3.ONE * game.HAND_SCALE),
		Vector3(1.6, game.HAND_Y + 0.1, -game.HAND_DIST))
	show_note(str(entry.card.name), "Choose %d sacrifice lanes." % int(entry.card.get("cost", 1)))
	_arrange_hand()


func _clear_held_preview() -> void:
	if is_instance_valid(held_preview):
		held_preview.hide()
		held_preview.queue_free()
	held_preview = null
	selected_held = ""
	evolution_play_sent = false


func _reset_evolutions() -> void:
	_cancel_pick(false)
	held = -1
	dragging = false
	view = {}
	end_button.disabled = true
	draw_button.disabled = true
	note.hide()
	note_head.text = ""
	note_body.text = ""
	if is_instance_valid(disaster_plans): disaster_plans.get_node("CountLabel").text = ""
