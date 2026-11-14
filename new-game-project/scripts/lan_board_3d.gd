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
const PrepFigure = preload("res://scripts/preparedness_figure.gd")
const Card3DScene = preload("res://scenes/card_3d.tscn")
const Sfx = preload("res://scripts/sfx_call.gd")
# p2-parity Part 1: the host's catalog inspect overlay, with the same dossier and card face.
const InspectionScene = preload("res://scenes/ui/ui_catalog_inspection.tscn")
const HOLD_MOVE_PIXELS := 12.0  # same as the host's hold check
# p2-parity Part 3: the host's result notice and seal tooltip helpers.
const RoomMenuStyle = preload("res://scripts/room_menu_style.gd")
const CardScript = preload("res://scripts/card_3d.gd")
const BoardDrag = preload("res://scripts/board_drag.gd")
# p2-plans: the host's Plans screen parts (run_director.show_plans).
const PlansScene = preload("res://scenes/ui/ui_plans.tscn")
const MenuSkin = preload("res://scripts/suspended_menu.gd")
const Contingency = preload("res://scripts/contingency_rules.gd")

# DESK_VIEW seen from the far side of the table, the Disaster seat.
const SEAT_VIEW := {"pos": Vector3(0, 1.0, 0.4), "rot": Vector3(-30, 180, 0), "dist": 5.3, "fov": 60.0}
const SEAT_HAND_DROP := 0.26
const DRAG_START_PIXELS := 8.0  # p2-feel: the card lifts at once; a release closer than this is still a click
const NOTE_SECONDS := 2.6
# p2-feel: the host lifts a hovered card but does not grow it (card_3d._apply_hover), so neither does P2.
const HAND_SCALE_HOVER := 1.0
const HOVER_LIFT_SECONDS := 0.14  # same lift time as the host (card_3d._apply_hover)
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
var choice_box: PanelContainer
# Crosswind, Lane Marshal and Evacuation Route: the ally is dragged onto an empty lane, as in hot-seat.
var move_ally := -1  # the lane of the ally being dragged, -1 = none
var move_queued := {}  # Preparedness: {choice, lane} to send once the host has taken the ally
var move_hint := -1  # the last move choice that showed the drag hint
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
var prep_figure: Node3D
var foe_resource: Control
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
var resource_plate: Control
var resource_label: Label
var resource_meter: Dictionary
var end_button: Button
var draw_button: Button
var tactic_box: VBoxContainer  # the tile list inside the Plans screen
var plans_screen: ColorRect  # p2-plans: the dimmer that holds the host's Plans screen, hidden when closed
var plans_panel: PanelContainer
var plans_status: Label
var plans_armed: Label
var plans_toggle: Button  # Preparedness: the host's Plans icon box, opens the Plans screen
var prep_grave: Button  # Preparedness: the host's graveyard counter
var tactic_signature := 0
var note: PanelContainer
var note_head: Label
var note_body: Label
var note_tween: Tween
var over_box: PanelContainer
var over_label: Label
var over_note: Label  # p2-parity Part 3: the host's result subtitle
var seal_tooltip: Label  # p2-parity Part 3: the host's seal hint on hover
# p2-parity Part 1: hold or right click opens this. Only cards the view already has can be inspected.
var inspection: Control
var inspection_dossier: Control
var inspection_card = null  # the Card3D the overlay shows, or null for a choice entry
var inspect_target = null  # a Card3D or a card Dictionary that a held press may inspect
var inspect_elapsed := 0.0  # p2-feel: game time since the press, the same clock as the host's hold timer
var inspect_origin := Vector2.ZERO
var suppress_release := false
# P2 lists: L (log), D (deck) and G (graveyard) ask the host; the answer opens this box.
var list_overlay: PanelContainer
var list_wanted := ""  # the list asked for and not answered yet, "" = none


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
	session.list_received.connect(_on_list)
	if not session.last_view.is_empty():
		_on_view(session.last_view)


func _exit_tree() -> void:
	if is_instance_valid(janitor): janitor.queue_free()
	if is_instance_valid(prep_figure): prep_figure.queue_free()
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
		for part in _play_hud(): part.visible = true
	view = new_view
	_cancel_pick(false)
	if not shown:
		_reveal()
	_sync_lanes()
	_sync_hand()
	_sync_foe()
	_refresh_hud()
	_refresh_choice()
	_refresh_forecast()
	_send_queued_move()
	_show_move_hint()
	# The boxes above are made again each view. The inspect overlay stays on top of them.
	if is_instance_valid(inspection): hud.move_child(inspection, -1)


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
	# The Disaster seat sees the Preparedness figure across the table, like the host's Disaster seat.
	if flipped:
		prep_figure = PrepFigure.new()
		game.add_child(prep_figure)
		prep_figure.transform = game.opponent_hand.figure.global_transform
		prep_figure.show()


func _on_event(kind: String, data: Dictionary) -> void:
	if kind != "reject":
		return
	var reason := str(data.get("reason", ""))
	# p2-feel: a card hidden at the play comes back when the host refuses it.
	for card in hand_cards: card.visible = true
	Sfx.play("invalid_action")
	show_note("Refused", REASONS.get(reason, reason.replace("_", " ").capitalize()))


func _on_match_over(winner: String) -> void:
	over = true
	close_inspection()
	close_list()
	held = -1
	dragging = false
	_cancel_pick(false)
	_refresh_choice()
	# p2-parity Part 3: the host's words (versus_match.finish), the same on both seats.
	var prep_won := winner == "preparedness"
	over_label.text = "PREPAREDNESS WINS" if prep_won else "DISASTER WINS"
	over_note.text = "The school is safe." if prep_won else "The school was lost."
	over_box.visible = true
	end_button.disabled = true
	# The last view can be stale (old health, "OPPONENT'S TURN"), so the match HUD hides behind the result.
	for part in _play_hud(): part.visible = false
	close_plans()


## The HUD parts that show the running match: health, Energy or Tension, the turn plate and the buttons.
func _play_hud() -> Array:
	var parts: Array = [turn_plate, me_plate.box, foe_plate.box, resource_plate, end_button, draw_button]
	for part in [foe_resource, disaster_plans, disaster_grave, plans_toggle, prep_grave]:
		if is_instance_valid(part): parts.append(part)
	return parts


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
	# A1/A8: a card whose data did not change keeps its face. Only a changed card repaints.
	var signature: int = hash([entry, own_side, int(view.get("round", 1)) if own_side else -1])
	if card.has_meta("lan_signature") and card.get_meta("lan_signature") == signature: return
	card.set_meta("lan_signature", signature)
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
			found.visible = true  # p2-feel: undo the hide at the play if the card is still in the hand
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
		# p2-colors: the host never greys a hand card it cannot play, so the client does not either.
		# The grey hit every card at the start of a P2 turn, while the host was still busy.
		card.art_sprite.modulate = Color.WHITE
		if i == held and dragging:
			continue
		var smooth: bool = VersusMatch.SIDE_BY_SIDE_HUD and side == "disaster"
		if i == hovered or i == selected:
			card.move_in_hand(pos + card.HOVER_LIFT, game.UPRIGHT, 100, HOVER_LIFT_SECONDS)
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
	# A move lights the allies, and the empty lanes while one is dragged.
	if _move_open(): return _move_destinations() if move_ally >= 0 else _move_allies()
	# Flag on: an open utility choice lights exactly the lanes of its stage.
	var open := _pending()
	if not open.is_empty(): return open.handles.duplicate() if open.stage in LANE_STAGES else []
	# A Crosswind that cannot be dragged now (match over) lights nothing.
	if side == "disaster" and not view.get("relocation", {}).is_empty(): return []
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
	if _inspect_input(event): return
	if _list_input(event): return
	if _plans_input(event): return
	if _evolution_open() or view.get("evolution_waiting", false): return
	# W and S would move the idle game's camera.
	if event is InputEventKey and event.keycode in [KEY_W, KEY_S]:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		mouse = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_on_release(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
			and not _pending().is_empty():
		# Esc closes the open choice first. It must not reach the leave-match menu.
		get_viewport().set_input_as_handled()
		_cancel_choice()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# With nothing to cancel, a right click on a card inspects it.
		if held < 0 and not _picking() and _right_click_inspect(event.position): return
		# The host plays this when a right click drops the dragged card back.
		if held >= 0 and dragging: Sfx.play("card_cancel_return")
		_cancel_pick(true)
		_cancel_choice()
		move_ally = -1
		held = -1
		dragging = false
		_arrange_hand()


func _unhandled_input(event: InputEvent) -> void:
	if not shown or over:
		return
	if _evolution_open() or view.get("evolution_waiting", false): return
	if is_instance_valid(inspection): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_press(event.position)


func _on_press(point: Vector2) -> void:
	mouse = point
	# A move: press an ally, drag it, and let go on an empty lane.
	if _move_open():
		var ally := _lane_at(point)
		move_ally = ally if ally in _move_allies() else -1
		if move_ally >= 0: return
	var index := _hand_at(point)
	if index >= 0:
		# Own hand cards can always be inspected, also on the other player's turn.
		_start_inspect_hold(hand_cards[index], point)
		if not _usable(index):
			_explain(index)
			return
		# p2-feel: like the host, the card lifts and follows the mouse from the press, not after 8 px.
		held = index
		dragging = true
		press_pos = point
		var card: Node3D = hand_cards[index]
		if card._tween: card._tween.kill()
		card.set_layer(100)
		Sfx.play("card_select")
		return
	# Nothing picked: a press on a lane card may become a hold that inspects it, like the host.
	if not _picking():
		var lane_card: Node3D = _lane_card_at(point)
		if lane_card != null: _start_inspect_hold(lane_card, point)
	var lane := _lane_at(point, _pick_row())
	if lane >= 0:
		click_lane(lane)


func _on_release(point: Vector2) -> void:
	if move_ally >= 0:
		var ally := move_ally
		move_ally = -1
		_drop_move(ally, _lane_at(point))
		return
	if held < 0:
		return
	var index := held
	# The card lifted at the press. A release that barely moved is still a click that picks the card.
	var was_drag := dragging and point.distance_to(press_pos) > DRAG_START_PIXELS
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
	# The host's drop sounds: a wrong lane is refused, no lane sends the card back.
	var on_lane := not _is_spell(index) and _lane_at(point) >= 0
	Sfx.play("invalid_action" if on_lane else "card_cancel_return")
	_arrange_hand()


func _process(delta: float) -> void:
	# The game can be freed before this board (a test or a teardown): touch nothing then.
	if not shown or not is_instance_valid(game):
		return
	# The director hides the game every frame outside a battle. This runs after it, because it is a child.
	game.visible = true
	_layout_hud()
	if dragging and held >= 0 and held < hand_cards.size():
		BoardDrag.follow_mouse(game, mouse, hand_cards[held], delta)
	else:
		mouse = get_viewport().get_mouse_position()
		_update_hover()
	inspect_elapsed += delta
	_check_inspect_hold()
	for i in hand_cards.size():
		var grow := HAND_SCALE_HOVER if i == hovered or i == selected else 1.0
		var target: Vector3 = Vector3.ONE * game.HAND_SCALE * grow
		hand_cards[i].scale = hand_cards[i].scale.lerp(target, 1.0 - exp(-16.0 * delta))
	_update_lanes()
	_update_lane_inspection()
	_update_seal_tooltip()


func _update_hover() -> void:
	var index := _hand_at(mouse) if not over and not is_instance_valid(inspection) and not plans_open() else -1
	if index == hovered:
		return
	hovered = index
	if index >= 0: Sfx.play("card_hover")  # same as the host's update_hand_hover
	_arrange_hand()


func _update_lane_inspection() -> void:
	var foe := "response" if side == "disaster" else "disaster"
	var free := not dragging and hovered < 0 and not over and not _evolution_open() \
		and not is_instance_valid(inspection) and not plans_open()
	var lane := _lane_at(mouse, foe) if free else -1
	var card: Node3D = lane_cards[foe][lane] if lane >= 0 else null
	if card == inspected_lane: return
	inspected_lane = card
	if is_instance_valid(lane_inspection): lane_inspection.queue_free()
	if not is_instance_valid(card): return
	lane_inspection = PanelContainer.new()
	lane_inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane_inspection.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD))
	hud.add_child(lane_inspection)
	var face := TextureRect.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.texture = card._vp.get_texture()
	face.custom_minimum_size = Vector2(220, 310)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lane_inspection.add_child(face)
	lane_inspection.position = Vector2(hud.size.x - 250, 220)


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
		if index < 0 or index >= hand_cards.size() or not hand_cards[index].visible: continue
		if Geometry2D.is_point_in_polygon(point, _polygon(index, true)):
			return index
	for index in range(hand_cards.size() - 1, -1, -1):
		if index == held and dragging or not hand_cards[index].visible:
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
	if lane_material == null: lane_material = BoardDrag.new_lane_material(game, self)
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
	# Crosswind is a drag (_drop_move). A lane click alone does nothing.
	if side == "disaster" and not view.get("relocation", {}).is_empty(): return
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
		Sfx.play("invalid_action")
		show_note("Pick a lit lane", "")
		return
	chosen.append(lane)
	if not selected_held.is_empty() and chosen.size() >= int(_held_entry().get("card", {}).get("cost", 1)):
		evolution_play_sent = true
	# p2-feel: a hand unit leaves the fan at once, with the host's deploy sound. The next view shows the truth:
	# _sync_hand shows a kept card again, and a refusal shows the hand again.
	if selected >= 0 and selected < hand_cards.size() and selected_held.is_empty() and selected_tactic == "" \
			and not _is_spell(selected):
		hand_cards[selected].visible = false
		Sfx.play("unit_deploy")
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
	# The screen closes once a tactic is picked, like the host Plans screen.
	close_plans()


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
	Sfx.play("invalid_action")  # the host refuses an unplayable card with this sound
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
	# The host's HUD pieces (versus_hud.gd): HP, Energy and Tension are all the host HP widget.
	# Preparedness bars are gold, Disaster bars crimson, whichever seat this is.
	var own_disaster := side == "disaster"
	foe_plate = _meter("FoeHealth", not own_disaster)
	me_plate = _meter("OwnHealth", own_disaster)
	_place(foe_plate.box, Control.PRESET_TOP_LEFT, Vector2(16, 12))
	# Round and turn, top centre, the same plate as the host.
	var turn: Dictionary = VersusHud.make_turn_plate(hud)
	turn_plate = turn.plate
	round_label = turn.round
	turn_label = turn.side
	resource_meter = _meter("OwnResource", own_disaster)
	resource_plate = resource_meter.box
	resource_label = resource_meter.title
	_place(me_plate.box, Control.PRESET_BOTTOM_LEFT, Vector2(16, -156))
	_place(resource_plate, Control.PRESET_BOTTOM_LEFT, Vector2(16, -80))
	if VersusMatch.SIDE_BY_SIDE_HUD:
		foe_meter = _meter("FoeResource", not own_disaster)
		foe_resource = foe_meter.box
		foe_resource_label = foe_meter.title
	# End turn and the deck counter: copies of the host buttons, in the host's places (hud.tscn).
	end_button = game._end_turn_btn.duplicate(0)
	end_button.name = "EndTurnButton"
	hud.add_child(end_button)
	end_button.pressed.connect(click_end)
	draw_button = game.get_node("HUD/Root/DeckDrawButton").duplicate(0)
	draw_button.name = "ClientDrawButton"
	hud.add_child(draw_button)
	draw_button.pressed.connect(_draw_pressed)
	# Preparedness tactics: the host's Plans screen, opened from the Plans icon box like the host.
	_build_plans_screen()
	_build_note()
	_build_over()
	_build_seal_tooltip()
	_build_disaster_controls()
	_build_prep_controls()


## One HUD meter (HP, Energy or Tension): the host widget from versus_hud.make_meter.
func _meter(meter_name: String, disaster: bool) -> Dictionary:
	var box: Control = VersusHud.make_meter(game, hud, meter_name, "", disaster)
	var bar: ProgressBar = box.get_node("Bar")
	return {"box": box, "title": box.get_node("Caption"), "bar": bar, "value": bar.get_node("Value"),
		"mark": box.get_node("HealthMark")}


## Preparedness: the host's Plans icon box (tokens) opens the tactic list; the graveyard counter sits bottom left.
func _build_prep_controls() -> void:
	if side != "preparedness": return
	plans_toggle = director.plans_button.duplicate(0)
	plans_toggle.name = "ClientPlansButton"
	plans_toggle.disabled = false
	plans_toggle.visible = true
	hud.add_child(plans_toggle)
	_place_icon_box(plans_toggle, Control.PRESET_BOTTOM_RIGHT, Vector2(-116, -72))
	plans_toggle.pressed.connect(toggle_plans)
	prep_grave = director.graveyard_button.duplicate(0)
	prep_grave.name = "ClientGraveyardButton"
	prep_grave.disabled = false
	prep_grave.visible = true
	hud.add_child(prep_grave)
	_place_icon_box(prep_grave, Control.PRESET_BOTTOM_LEFT, Vector2(16, -72))
	# P2 lists: the host sends the graveyard cards when asked, like G.
	prep_grave.pressed.connect(toggle_list.bind("grave"))


## A 100 x 56 icon box in a corner, like the host's Plans and Graveyard boxes.
func _place_icon_box(button: Button, preset: int, top_left: Vector2) -> void:
	button.set_anchors_preset(preset)
	button.offset_left = top_left.x
	button.offset_top = top_left.y
	button.offset_right = top_left.x + 100
	button.offset_bottom = top_left.y + 56


func _place(control: Control, preset: int, offset: Vector2) -> void:
	control.set_anchors_preset(preset)
	control.grow_horizontal = Control.GROW_DIRECTION_END if offset.x >= 0 else Control.GROW_DIRECTION_BEGIN
	control.grow_vertical = Control.GROW_DIRECTION_END if offset.y >= 0 else Control.GROW_DIRECTION_BEGIN
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x
	control.offset_bottom = offset.y




func _build_note() -> void:
	note = PanelContainer.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.ACTION, 2, 14))
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
	note_head = VersusHud._label(box, 30, UI.DANGER)
	note_body = VersusHud._label(box, 18, UI.TEXT)
	note_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_over() -> void:
	over_box = PanelContainer.new()
	over_box.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD, 3, 24))
	over_box.set_anchors_preset(Control.PRESET_CENTER)
	over_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	over_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	# p2-parity Part 3: the host's result size (run_director._panel_layout).
	var screen := get_viewport().get_visible_rect().size
	over_box.custom_minimum_size = Vector2(minf(760, screen.x - 48), minf(460, screen.y - 100))
	over_box.visible = false
	hud.add_child(over_box)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	over_box.add_child(box)
	over_label = VersusHud._label(box, 64, UI.GOLD)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_note = director.label("", 16, UI.MUTED, true)
	over_note.name = "ResultNote"
	box.add_child(over_note)
	var back: Button = director.button("Back to title", func() -> void: panel.back_pressed.emit(), box)
	back.name = "BackButton"
	back.custom_minimum_size = Vector2(200, 52)
	# The host's dark result notice: icon, title and the same button style.
	box.set_meta("style_kind", "result")
	RoomMenuStyle.result(over_box, box, "result")
	# Over LAN the words say who won, so the title stays gold for both players.
	over_label.add_theme_color_override("font_color", UI.GOLD)


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
	# The host's captions and P1 / P2 tags. Over LAN the host is always Player 1, this client Player 2.
	_set_plate(me_plate, sides[mine], side.to_upper(), "P2")
	_set_plate(foe_plate, sides[foe], ("DISASTER" if foe == "disaster" else "PREPAREDNESS"), "P1")
	var foe_hand := int(counts.get("disaster_hand" if side == "preparedness" else "response_hand", 0))
	var foe_deck := int(counts.get("disaster_draw" if side == "preparedness" else "response_draw", 0))
	foe_plate.box.tooltip_text = "Hand %d   Deck %d" % [foe_hand, foe_deck]
	var barrier := int(sides[mine].get("barrier", 0))
	me_plate.box.tooltip_text = ("Barrier %d" % barrier) if barrier > 0 else ""
	round_label.text = "ROUND %d" % int(view.get("round", 1))
	var phase := str(view.get("phase", "play" if _my_turn() else "end")).to_upper()
	var turn_side := str(view.get("turn_side", side if _my_turn() else ""))
	var own_turn: bool = turn_side == side
	turn_plate.visible = not turn_side.is_empty() and not over
	if turn_plate.visible: VersusHud.set_turn_text(turn_label, turn_side, "P2" if own_turn else "P1")
	end_button.disabled = not _my_turn() or not view.get("relocation", {}).is_empty() or not _pending().is_empty()
	# The deck counter is the host's: the own draw pile, and the draw button on a Preparedness draw.
	draw_button.visible = not over
	var own_draw := "response_draw" if side == "preparedness" else "disaster_draw"
	draw_button.get_node("DeckCountLabel").text = str(int(counts.get(own_draw, 0)))
	draw_button.disabled = side != "preparedness" or not own_turn or phase != "DRAW"
	if view.get("evolution_waiting", false): draw_button.disabled = true
	if is_instance_valid(plans_toggle):
		plans_toggle.get_node("CountLabel").text = "%d/2" % int(view.get("plan_tokens", 0))
	if is_instance_valid(prep_grave):
		prep_grave.get_node("CountLabel").text = str(int(counts.get("response_graveyard", 0)))
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
		_layout_hud()
	# The side that is not playing is dimmed, as on the host.
	resource_plate.modulate.a = 0.5 if not turn_side.is_empty() and not own_turn else 1.0
	if is_instance_valid(foe_resource): foe_resource.modulate.a = 0.5 if own_turn else 1.0
	if is_instance_valid(disaster_grave):
		disaster_grave.get_node("CountLabel").text = str(counts.get("disaster_graveyard", 0))
	if is_instance_valid(disaster_plans) and view.has("held_evolutions"):
		disaster_plans.tooltip_text = "Evolution"
		disaster_plans.get_node("CountLabel").text = str(view.held_evolutions.size())
	if view.get("evolution_waiting", false): turn_label.text = "DISASTER CHOOSES AN EVOLUTION"
	_fill_tactics()
	_refresh_plans()


func _set_plate(plate: Dictionary, data: Dictionary, title: String, tag: String) -> void:
	var hp := maxi(int(data.hp), 0)
	var max_hp := maxi(int(data.max_hp), 1)
	plate.title.text = title
	plate.mark.text = tag
	plate.bar.max_value = max_hp
	plate.bar.value = hp
	plate.value.text = "%d / %d" % [hp, max_hp]


func _fill_tactics() -> void:
	# A8: the buttons are made again only when the tactics, the turn or the seat changed.
	var signature: int = hash([view.get("tactics", []), _my_turn(), side])
	if signature == tactic_signature: return
	tactic_signature = signature
	for child in tactic_box.get_children():
		tactic_box.remove_child(child)
		child.queue_free()
	if side != "preparedness":
		return
	# One host choice tile per tactic: "Name · N Plan" and the description from contingency_rules.gd.
	for tactic: Dictionary in view.get("tactics", []):
		var id := str(tactic.id)
		var description := str(Contingency.find_tactic(id).get("description", ""))
		var tactic_button: Button = director.choice_tile(director.plans_tile_title(str(tactic.name),
			int(tactic.cost)), description, _pick_tactic.bind(id), tactic_box)
		tactic_button.clip_text = true  # the host's compact Plans layout clips long titles
		var tile: Control = tactic_button.get_parent().get_parent()
		tile.name = "Tactic_" + id
		tile.custom_minimum_size.y = 125
		var unsupported: bool = _tactic_unsupported(id)
		tactic_button.disabled = (not bool(tactic.available) and not unsupported) or not _my_turn()
		if unsupported: tactic_button.tooltip_text = REASONS.not_supported
	# The host skins the tiles after they are made, so this does too.
	MenuSkin.style_children(tactic_box)


## The Plans status and the ARMED line, from the view, like the host screen.
func _refresh_plans() -> void:
	plans_status.text = "PLANS %d / 2" % int(view.get("plan_tokens", 0))
	var armed := str(view.get("armed", ""))
	plans_armed.visible = not armed.is_empty()
	if plans_armed.visible:
		plans_armed.text = "ARMED: " + str(Contingency.find_tactic(armed).get("name", armed))


## The pick button of a tactic tile, or null.
func tactic_tile_button(id: String) -> Button:
	return tactic_box.get_node_or_null("Tactic_%s/Box/PickButton" % id)


# ------------------------------------------------------------------- Plans screen (p2-plans)
## The host's Plans screen (run_director.show_plans): same words, ui_plans.tscn, tiles and skin.
## It is made once and hidden. The host pauses its tree for it; the client does not, so the link keeps running.
func _build_plans_screen() -> void:
	# The host's ModalDimmer: same colour, under the top bar.
	plans_screen = ColorRect.new()
	plans_screen.name = "ClientPlansScreen"
	plans_screen.color = Color(0.043137256, 0.043137256, 0.050980393, 0.86)
	plans_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	plans_screen.offset_top = 52.0
	plans_screen.visible = false
	hud.add_child(plans_screen)
	plans_panel = PanelContainer.new()
	plans_panel.name = "PlansPanel"
	plans_panel.set_meta("suspended_menu", true)
	plans_screen.add_child(plans_panel)
	# The host's compact screens hold the content in a scroll (ModalScroll), so wrapped text cannot stretch the panel.
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	plans_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Content"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(director.label(director.PLANS_TITLE, 24, UI.GOLD, true))
	box.add_child(director.label(director.PLANS_SUBTITLE, 18, UI.MUTED, true))
	var layout := PlansScene.instantiate()
	# The nodes leave the scene, so they should not keep it as their owner (like run_director.unpack_screen).
	for node in layout.find_children("*", "", true, false): node.owner = null
	for child in layout.get_children():
		layout.remove_child(child)
		box.add_child(child)
	layout.free()
	plans_status = box.get_node("Status")
	plans_armed = box.get_node("Armed")
	tactic_box = box.get_node("Scroll/List")
	director.hook_button(box.get_node("ReturnButton"), close_plans)
	MenuSkin.apply_skin(plans_panel, box)
	# The straps above the frame, like the host's screen. Top level, so the panel does not lay it out.
	var straps := MenuSkin.new()
	straps.name = "SuspendedFrame"
	straps.top_level = true
	straps.panel = plans_panel
	plans_panel.add_child(straps)


func plans_open() -> bool:
	return is_instance_valid(plans_screen) and plans_screen.visible


func toggle_plans() -> void:
	if plans_open(): close_plans()
	else: open_plans()


## Opens the screen in the host's place: 560 x 680 at most, centred, below the top bar.
func open_plans() -> void:
	if side != "preparedness" or over or dragging: return
	close_inspection()
	close_list()
	var viewport := get_viewport().get_visible_rect().size
	var panel_size := Vector2(minf(560, viewport.x - 32), minf(680, viewport.y - 48))
	var top := maxf((viewport.y - panel_size.y) / 2, 66)
	var bottom := viewport.y - (viewport.y - panel_size.y) / 2
	# The dimmer starts 52 px down, so the panel is placed in its space.
	plans_panel.position = Vector2((viewport.x - panel_size.x) / 2, top - plans_screen.offset_top)
	plans_panel.size = Vector2(panel_size.x, bottom - top)
	plans_screen.visible = true
	hud.move_child(plans_screen, -1)


func close_plans() -> void:
	if is_instance_valid(plans_screen): plans_screen.visible = false


## A tile pick sends the tactic like the old list buttons did, then the screen closes.
func _pick_tactic(id: String) -> void:
	click_tactic(id)
	close_plans()


## While the screen is open, Esc closes it and the table ignores the mouse. The tiles still get clicks.
func _plans_input(event: InputEvent) -> bool:
	if not plans_open(): return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_plans()
	return true


## Energy or Tension as current / cap on the host's bar. The bar is empty at cap 0.
func _set_resource(meter: Dictionary, current: int, cap: int) -> void:
	current = maxi(current, 0)
	cap = maxi(cap, 0)
	meter.bar.max_value = maxi(cap, 1)
	meter.bar.value = current if cap > 0 else 0
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
		# Same size as the HP plate, so every bar has the same height (as on the host).
		resource.set_anchors_preset(Control.PRESET_TOP_LEFT)
		resource.size = rect.size
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
	_place_icon_box(disaster_plans, Control.PRESET_BOTTOM_RIGHT, Vector2(-116, -72))
	disaster_plans.pressed.connect(func() -> void:
		if view.has("held_evolutions"): panel.show_held_evolutions()
		else: show_note("Coming later", "Disaster plans are coming later."))
	disaster_grave = director.graveyard_button.duplicate(0)
	disaster_grave.name = "DisasterGraveyardButton"
	disaster_grave.visible = true
	disaster_grave.disabled = false
	hud.add_child(disaster_grave)
	_place_icon_box(disaster_grave, Control.PRESET_BOTTOM_LEFT, Vector2(16, -72))
	disaster_grave.pressed.connect(show_disaster_graveyard)

func show_disaster_graveyard() -> void:
	if is_instance_valid(grave_note): grave_note.queue_free()
	grave_note = PanelContainer.new()
	grave_note.name = "DisasterGraveyardNotice"
	grave_note.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD, 2, 16))
	hud.add_child(grave_note)
	var box := VBoxContainer.new()
	grave_note.add_child(box)
	VersusHud._label(box, 26, UI.GOLD).text = "DISASTER GRAVEYARD"
	var count := int(view.get("counts", {}).get("disaster_graveyard", 0))
	# Flag on: the host sends the list. Flag off: only the count.
	if view.has("disaster_graveyard_list"):
		_fill_grave_list(box, view.disaster_graveyard_list)
	else:
		VersusHud._label(box, 20, UI.TEXT).text = "%d cards. Card list is unavailable on this client." % count
	director.button("Close", func() -> void: grave_note.queue_free(), box)
	grave_note.reset_size()
	grave_note.position = (hud.size - grave_note.size) * 0.5


# The Disaster graveyard cards in the order the host sent them, each with its reason and round.
func _fill_grave_list(box: VBoxContainer, cards: Array) -> void:
	if cards.is_empty():
		VersusHud._label(box, 20, UI.TEXT).text = "The graveyard is empty."
		return
	var scroll := ScrollContainer.new()
	scroll.name = "GraveList"
	scroll.custom_minimum_size = Vector2(minf(760, hud.size.x - 80), minf(420, hud.size.y - 220))
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	scroll.add_child(grid)
	for entry: Dictionary in cards:
		director._card_tile(entry, grid)
		var reason := str(entry.get("graveyard_reason", "Destroyed"))
		var caption := VersusHud._label(grid.get_child(-1).get_node("Box"), 14, UI.MUTED)
		caption.text = "%s · round %d" % [reason, int(entry.get("graveyard_round", 1))]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Flag on: the box for the open utility choice. A prompt, a button per lane or list entry, and Cancel.
## Lane stages can also be picked on the lit table. Esc and right click cancel too.
func _refresh_choice() -> void:
	if is_instance_valid(choice_box):
		choice_box.get_parent().remove_child(choice_box)
		choice_box.queue_free()
	choice_box = null
	var open := _pending()
	# Lane Marshal and Evacuation Route are a drag now (_drop_move), so no box opens. Esc skips them.
	if open.is_empty() or _move_open(): return
	choice_box = PanelContainer.new()
	choice_box.name = "UtilityChoice"
	choice_box.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD, 2, 12))
	hud.add_child(choice_box)
	_place(choice_box, Control.PRESET_CENTER_LEFT, Vector2(16, -80))
	var box := VBoxContainer.new()
	choice_box.add_child(box)
	VersusHud._label(box, 24, UI.GOLD).text = str(open.name).to_upper()
	var prompt := VersusHud._label(box, 18, UI.TEXT)
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
	if VersusMatch.UI_CARD_PICKER and not candidates.is_empty():
		_build_card_picker(box, candidates)
		candidates = []
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
			# A hidden card has no "card" here, so it cannot be inspected.
			if entry.has("card"): _hook_entry_inspect(entry_button, entry.card)
		# Room for the title, prompt and Cancel stays outside the list.
		var row: float = entries.get_child(0).get_combined_minimum_size().y + 6.0
		scroll.custom_minimum_size.y = minf(row * candidates.size(), maxf(120.0, hud.size.y - 300.0))
	var cancel: Button = director.button("Cancel", _cancel_choice, box)
	cancel.name = "ChoiceCancel"


## UI_CARD_PICKER: the candidates as a grid of real card tiles instead of a list of text buttons. The panel is only as
## large as the cards need and scrolls when they do not fit. Hidden entries show a card back. Handles are unchanged.
func _build_card_picker(box: VBoxContainer, candidates: Array) -> void:
	var cards_per_row := clampi(int(hud.size.x * 0.8 / 232.0), 1, 6)
	var scroll := ScrollContainer.new()
	scroll.name = "ChoiceScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = mini(cards_per_row, candidates.size())
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for entry: Dictionary in candidates:
		var handle := int(entry.handle)
		var tile_index := grid.get_child_count()
		if entry.has("card"):
			var data := {"type": "response", "element": "evac", "cost": 0, "attack": 0, "health": 1}
			data.merge(entry.card, true)
			director._card_tile(data, grid, _pick_candidate.bind(handle), "Pick", false)
		else:
			_hidden_tile(grid, handle)
		var tile: Control = grid.get_child(tile_index)
		# Deck-viewer look: bare cards, no plate and no name above (the card face already has its name).
		tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var action: Button = tile.find_child("ActionButton", true, false)
		if action != null:
			action.name = "ChoiceEntry%d" % handle
			action.text = str(entry.card.get("name", "?")) if entry.has("card") else "Hidden card %d" % (handle + 1)
			_click_overlay(tile, action)
			# A hidden card has no "card" here, so it cannot be inspected.
			if entry.has("card"): _hook_entry_inspect(action, entry.card)
	_fit_card_picker.call_deferred(scroll, grid)
	_place(choice_box, Control.PRESET_CENTER, Vector2.ZERO)
	choice_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	choice_box.grow_vertical = Control.GROW_DIRECTION_BOTH


## After one layout pass the grid knows its real size: the panel takes it, up to what the screen allows.
func _fit_card_picker(scroll: ScrollContainer, grid: GridContainer) -> void:
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not is_instance_valid(grid): return
	var wide: float = minf(grid.size.x + 14.0, hud.size.x * 0.92)
	var tall: float = minf(grid.size.y + 4.0, maxf(180.0, hud.size.y - 280.0))
	scroll.custom_minimum_size = Vector2(wide, tall)


## The whole card is the button: a click on the card picks it. The button covers the tile and shows an outline on hover.
func _click_overlay(tile: Control, button: Button) -> void:
	if button.get_parent() != tile: button.reparent(tile)
	# The text stays (the card name, or Hidden card N) so tools and tests can read it; it is drawn invisible.
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(color, Color(0, 0, 0, 0))
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.07)
	hover.border_color = UI.GOLD
	hover.set_border_width_all(3)
	hover.set_corner_radius_all(8)
	button.add_theme_stylebox_override("hover", hover)


## A card the player cannot see: the card back and a Pick button. Same size as a card tile.
func _hidden_tile(parent: Node, handle: int) -> void:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(tile)
	var column := VBoxContainer.new()
	tile.add_child(column)
	director.card_image(preload("res://scripts/card_3d.gd")._card_back(), column, 180)
	var pick: Button = director.button("Hidden card %d" % (handle + 1), _pick_candidate.bind(handle), tile)
	pick.name = "ActionButton"
	_click_overlay(tile, pick)


## Flag on, after Scout: the Disaster hand as it was when Hazard Forecast was cast. Preparedness view only.
func _refresh_forecast() -> void:
	if is_instance_valid(forecast_box):
		forecast_box.get_parent().remove_child(forecast_box)
		forecast_box.queue_free()
	forecast_box = null
	if side != "preparedness" or over or not view.has("disaster_hand_revealed"): return
	forecast_box = PanelContainer.new()
	forecast_box.name = "HazardForecast"
	forecast_box.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD, 2, 12))
	hud.add_child(forecast_box)
	_place(forecast_box, Control.PRESET_CENTER_RIGHT, Vector2(-16, -80))
	var box := VBoxContainer.new()
	forecast_box.add_child(box)
	VersusHud._label(box, 24, UI.GOLD).text = "HAZARD FORECAST"
	var cards: Array = view.disaster_hand_revealed
	if cards.is_empty(): VersusHud._label(box, 18, UI.TEXT).text = "The Disaster hand is empty."
	for card: Dictionary in cards:
		VersusHud._label(box, 18, UI.TEXT).text = str(card.get("name", "?"))


func _pick_candidate(handle: int) -> void:
	if over or _pending().is_empty(): return
	panel.choice_picked.emit(handle)


func _cancel_choice() -> void:
	if _pending().is_empty(): return
	panel.choice_cancelled.emit()


# ------------------------------------------------------------------- move by drag
## True while a move of a friendly ally is open: Crosswind (Disaster), Lane Marshal, Evacuation Route or
## Emergency Extraction (Preparedness). The host still checks every lane (disaster_relocation.gd,
## lan_utility_choice.gd).
func _move_open() -> bool:
	if over or not _my_turn(): return false
	if side == "disaster": return not view.get("relocation", {}).is_empty()
	var open := _pending()
	var kind := str(open.get("kind", ""))
	var effect := str(open.get("effect", ""))
	# Extraction picks an ally and its escape lane the same way, so it is a drag too. Nothing moves until it fires.
	if kind == "tactic": return effect == "extract"
	return kind == "relocation" or (kind == "utility" and effect == "move")


## The lanes a move drag may start from. After the host took the ally, only that ally.
func _move_allies() -> Array:
	if side == "disaster":
		return [] if panel.relocation_sent else view.relocation.get("allies", [])
	var open := _pending()
	if open.stage == "ally": return open.handles
	return [int(open.get("ally", -1))]


## The empty lanes a dragged ally may land on.
func _move_destinations() -> Array:
	if side == "disaster": return view.relocation.get("destinations", [])
	var open := _pending()
	if open.stage == "destination": return open.handles
	var lanes: Array = []
	var own: Array = lane_cards[_own_side()]
	for lane in own.size():
		if own[lane] == null: lanes.append(lane)
	return lanes


## The dragged ally lands on the empty lane under the mouse. Anywhere else, nothing moves.
func _drop_move(ally: int, lane: int) -> void:
	if lane < 0 or lane == ally or not _move_open(): return
	if lane not in _move_destinations():
		show_note("Cannot move there", "")
		return
	if side == "disaster":
		# One message with both lanes, the same one the old lane buttons sent.
		panel.relocation_ally = -1
		panel.pick_relocation(ally)
		panel.pick_relocation(lane)
		return
	var open := _pending()
	if open.stage == "destination":
		panel.lane_pressed.emit(lane)
		return
	# The host takes the ally first. The lane is sent when its view comes back (_send_queued_move).
	move_queued = {"choice": int(open.choice), "lane": lane}
	panel.lane_pressed.emit(ally)


## Preparedness: the second half of a drag, once the host has moved the choice on to the lane stage.
func _send_queued_move() -> void:
	if move_queued.is_empty(): return
	var open := _pending()
	if int(open.get("choice", -1)) != move_queued.choice:
		move_queued = {}
		return
	if open.stage != "destination": return
	var lane: int = move_queued.lane
	move_queued = {}
	if lane in open.handles: panel.lane_pressed.emit(lane)
	else: show_note("Cannot move there", "")


## A short note when a move opens, since there is no panel any more.
func _show_move_hint() -> void:
	if not _move_open(): return
	var id: int = int(view.relocation.choice) if side == "disaster" else int(_pending().choice)
	if id == move_hint: return
	move_hint = id
	var title := "CROSSWIND" if side == "disaster" else str(_pending().get("name", "MOVE")).to_upper()
	var skip := "" if side == "disaster" else " Esc to skip."
	show_note(title, "Drag an ally onto an empty lane." + skip)


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
	close_inspection()
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


# ------------------------------------------------------------------- inspect (p2-parity Part 1)
## True while a press on the table is an action: a picked card, tactic or evolution, an open choice or Crosswind.
func _picking() -> bool:
	return selected >= 0 or selected_tactic != "" or not selected_held.is_empty() or not _pending().is_empty() \
		or not view.get("relocation", {}).is_empty()


## The lane card on either row under a screen point, or null.
func _lane_card_at(point: Vector2) -> Node3D:
	for lane_side: String in ["response", "disaster"]:
		var lane := _lane_at(point, lane_side)
		if lane >= 0 and is_instance_valid(lane_cards[lane_side][lane]): return lane_cards[lane_side][lane]
	return null


func _has_inspect_target() -> bool:
	return inspect_target is Dictionary or is_instance_valid(inspect_target)


func _start_inspect_hold(target, point: Vector2) -> void:
	inspect_target = target
	inspect_elapsed = 0.0
	inspect_origin = point
	_inspect_log("hold starts on " + _inspect_name(target))


## p2-inspect-freeze: debug build in a real window only. One line per inspect step in the Output panel,
## so a frozen Player 2 window shows the last step it reached.
func _inspect_log(text: String) -> void:
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		print("[P2 inspect] frame %d: %s" % [Engine.get_process_frames(), text])


func _inspect_name(target) -> String:
	if target is Dictionary: return str(target.get("name", "?"))
	if target is Node3D and is_instance_valid(target): return str(target.card_data.get("name", "?"))
	return "nothing"


## A press that stays still for the host's hold time opens the inspect panel.
func _check_inspect_hold() -> void:
	if is_instance_valid(inspection) and inspection_card != null and not is_instance_valid(inspection_card):
		close_inspection()
	# p2-feel: a held card is lifted at once now, so only a real drag (moved past the hold distance) stops it.
	var moved := dragging and mouse.distance_to(press_pos) > HOLD_MOVE_PIXELS
	if not _has_inspect_target() or moved or is_instance_valid(inspection): return
	# Game time, like the host's create_timer(INSPECT_HOLD_SECONDS).
	if inspect_elapsed < director.INSPECT_HOLD_SECONDS: return
	var target = inspect_target
	inspect_target = null
	_inspect_log("hold time reached")
	# A held hand card goes back to the fan, so the release does not play it.
	held = -1
	dragging = false
	_arrange_hand()
	open_inspection(target)


func _right_click_inspect(point: Vector2) -> bool:
	var index := _hand_at(point)
	var card: Node3D = hand_cards[index] if index >= 0 else _lane_card_at(point)
	if card == null: return false
	get_viewport().set_input_as_handled()
	open_inspection(card)
	return true


## A choice entry with a visible card opens the same inspect panel on hold or right click.
func _hook_entry_inspect(entry_button: Button, card: Dictionary) -> void:
	entry_button.gui_input.connect(func(event: InputEvent) -> void:
		if not event is InputEventMouseButton or not event.pressed: return
		if event.button_index == MOUSE_BUTTON_RIGHT: open_inspection(card)
		elif event.button_index == MOUSE_BUTTON_LEFT: _start_inspect_hold(card, event.global_position))


## Esc or a left click outside the dossier closes the panel, like the host.
## Returns true when the board must not use the event.
func _inspect_input(event: InputEvent) -> bool:
	var left: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	if left and not event.pressed:
		inspect_target = null
		if suppress_release or is_instance_valid(inspection):
			suppress_release = false
			get_viewport().set_input_as_handled()
			return true
	if not is_instance_valid(inspection):
		if event is InputEventMouseMotion and _has_inspect_target() \
				and event.position.distance_to(inspect_origin) > HOLD_MOVE_PIXELS:
			inspect_target = null
		return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_inspection()
		get_viewport().set_input_as_handled()
	elif left and event.pressed and not inspection_dossier.get_global_rect().has_point(event.position):
		close_inspection()
		suppress_release = true
		get_viewport().set_input_as_handled()
	elif left and event.pressed:
		_inspect_log("click inside the dossier, the panel stays open")
	return true


## The host's inspect panel: the same dossier and card face, built only from the view.
## target is a Card3D of this board (lane or own hand) or a card Dictionary from a choice entry.
func open_inspection(target) -> void:
	if over or is_instance_valid(inspection): return
	var card: Node3D = target if target is Node3D and is_instance_valid(target) else null
	if card == null and not target is Dictionary: return
	_inspect_log("open starts: " + _inspect_name(target))
	var definition: Dictionary = director.live_definition(card) if card != null else target.duplicate(true)
	inspection = InspectionScene.instantiate()
	inspection.name = "LanInspection"
	hud.add_child(inspection)
	var row: Control = inspection.get_node("Center/Row")
	director.add_dossier(row, definition, _combat_text(card) if card != null else "")
	inspection_dossier = row.get_child(0)
	inspection_card = card
	var face_card := card
	if face_card == null:
		face_card = _make_card(definition, inspection)
		face_card.hide()
	else:
		face_card._refresh_face()
	director.card_image(face_card._vp.get_texture(), row, 330)
	if is_instance_valid(lane_inspection): lane_inspection.queue_free()
	inspected_lane = null
	# A held choice button keeps the mouse. Building the list again lets it go, so no pick happens.
	if card == null: _refresh_choice()
	hud.move_child(inspection, -1)
	_inspect_log("open done")


func close_inspection() -> void:
	inspect_target = null
	if is_instance_valid(inspection):
		_inspect_log("close")
		inspection.hide()
		inspection.queue_free()
	inspection = null
	inspection_dossier = null
	inspection_card = null


## The THIS COMBAT lines the view carries, in the host's words: seal, plan protection, plan attack, Ignore Taunt.
## The movement, conditional ability and Blood Pact lines come from the host's lane_notes (lan_view.gd).
func _combat_text(card: Node3D) -> String:
	var lines: PackedStringArray = []
	var note := _lane_note(card)
	# Only the field seal here, like the host's field_seal_text. The card script words it.
	var seal_only := {"seal_round": card.card_data.get("seal_round", -1)}
	var seal_text := CardScript.seal_hint(seal_only, int(view.get("round", 1)))
	if not seal_text.is_empty(): lines.append(seal_text)
	if card.planned_guard > 0: lines.append("Plan protection: %d" % card.planned_guard)
	var movement := int(note.get("movement", 0))
	if movement > 0: lines.append("Temporary movement attack: +%d" % movement)
	if card.plan_attack_bonus > movement: lines.append("Plan attack: +%d" % (card.plan_attack_bonus - movement))
	if note.has("condition"):
		lines.append("[b]Conditional ability: %s[/b]" % ("ACTIVE" if note.condition else "inactive"))
	if card.plan_ignore_taunt: lines.append("Ignore Taunt")
	if note.get("blood_pact", false): lines.append("Blood Pact: defeat a card this turn or die")
	return "" if lines.is_empty() else "[b]THIS COMBAT[/b]\n" + "\n".join(lines) + "\n"


## The host's note for a lane card, or {} for a hand card or an older view without notes.
func _lane_note(card: Node3D) -> Dictionary:
	var notes: Dictionary = view.get("lane_notes", {})
	for lane_side in lane_cards:
		var lane: int = lane_cards[lane_side].find(card)
		if lane >= 0 and lane < notes.get(lane_side, []).size():
			return notes[lane_side][lane]
	return {}


# ------------------------------------------------------------------- lists (P2 lists)
## L, D and G open the log, the own deck and the own graveyard; the same key or Esc closes it.
## Returns true when the event was used.
func _list_input(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	var kinds := {KEY_L: "log", KEY_D: "deck", KEY_G: "grave"}
	if event.keycode == KEY_ESCAPE and (is_instance_valid(list_overlay) or list_wanted != ""):
		close_list()
	elif kinds.has(event.keycode):
		toggle_list(kinds[event.keycode])
	else:
		return false
	get_viewport().set_input_as_handled()
	return true


## Opens one list, or closes it when it is already open. The host sends the cards (lan_session.ask_list).
func toggle_list(kind: String) -> void:
	var open_kind := str(list_overlay.get_meta("kind", "")) if is_instance_valid(list_overlay) else ""
	if open_kind == kind or list_wanted == kind:
		close_list()
		return
	list_wanted = kind
	session.request_list(kind)


func close_list() -> void:
	list_wanted = ""
	if is_instance_valid(list_overlay): list_overlay.queue_free()
	list_overlay = null


## The host's answer. Only the list still wanted opens, so a late answer after Esc is dropped.
func _on_list(kind: String, items: Array) -> void:
	if over or kind != list_wanted: return
	list_wanted = ""
	if is_instance_valid(list_overlay): list_overlay.queue_free()
	list_overlay = PanelContainer.new()
	list_overlay.name = "List_" + kind
	list_overlay.set_meta("kind", kind)
	list_overlay.add_theme_stylebox_override("panel", VersusHud._plate_style(UI.GOLD, 2, 16))
	hud.add_child(list_overlay)
	var box := VBoxContainer.new()
	list_overlay.add_child(box)
	var own := "DISASTER" if side == "disaster" else "PREPAREDNESS"
	var titles := {"log": "BATTLE LOG", "deck": own + " DECK", "grave": own + " GRAVEYARD"}
	VersusHud._label(box, 26, UI.GOLD).text = titles.get(kind, kind.to_upper())
	var list_size := Vector2(minf(760, hud.size.x - 80), minf(420, hud.size.y - 220))
	if kind == "log":
		var text := RichTextLabel.new()
		text.name = "LogText"
		text.custom_minimum_size = list_size
		text.scroll_following = true
		text.text = "\n".join(items) if not items.is_empty() else "No battle events yet."
		box.add_child(text)
	elif items.is_empty():
		VersusHud._label(box, 20, UI.TEXT).text = "No cards here yet." if kind == "deck" else "The graveyard is empty."
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = list_size
		box.add_child(scroll)
		var grid := GridContainer.new()
		grid.name = "ListGrid"
		grid.columns = 3
		scroll.add_child(grid)
		for entry: Dictionary in items:
			director._card_tile(entry, grid)
			if kind != "grave": continue
			# The graveyard reason and round under the card, like the host's graveyard.
			var caption := VersusHud._label(grid.get_child(-1).get_node("Box"), 14, UI.MUTED)
			caption.text = "%s · round %d" % [str(entry.get("graveyard_reason", "Destroyed")),
				int(entry.get("graveyard_round", 1))]
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	director.button("Close", close_list, box)
	list_overlay.reset_size()
	list_overlay.position = (hud.size - list_overlay.size) * 0.5
	# The inspect overlay stays on top.
	if is_instance_valid(inspection): hud.move_child(inspection, -1)


# ------------------------------------------------------------------- seal tooltip (p2-parity Part 3)
## The host's seal tooltip (run_director._refresh_seal_tooltip): same label style, same text.
func _build_seal_tooltip() -> void:
	seal_tooltip = Label.new()
	seal_tooltip.name = "SealTooltip"
	seal_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal_tooltip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seal_tooltip.custom_minimum_size.x = 420
	seal_tooltip.add_theme_font_size_override("font_size", 22)
	seal_tooltip.add_theme_stylebox_override("normal", director.style(UI.PANEL, UI.GOLD))
	seal_tooltip.hide()
	hud.add_child(seal_tooltip)


## A hovered hand or lane card with a seal shows the hint next to the mouse. The round is the host's.
func _update_seal_tooltip() -> void:
	var card: Node3D = null
	var quiet := over or dragging or _evolution_open() or is_instance_valid(inspection)
	if not quiet: card = hand_cards[hovered] if hovered >= 0 and hovered < hand_cards.size() else _lane_card_at(mouse)
	var hint := CardScript.seal_hint(card.card_data, int(view.get("round", 1))) if card != null else ""
	if hint.is_empty():
		seal_tooltip.hide()
		return
	if seal_tooltip.text != hint: seal_tooltip.text = hint
	seal_tooltip.size = Vector2(420, 0)
	var bounds := get_viewport().get_visible_rect().size - seal_tooltip.size - Vector2(8, 8)
	seal_tooltip.position = (mouse + Vector2(18, 18)).clamp(Vector2(8, 8), bounds)
	seal_tooltip.show()
	if seal_tooltip.get_index() != hud.get_child_count() - 1: hud.move_child(seal_tooltip, -1)
