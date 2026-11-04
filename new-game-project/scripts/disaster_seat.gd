extends Node
## Pass-and-play seat for a human Disaster in Versus. While the Disaster waits for input, the camera sits on
## the far side of the table and the Disaster hand is shown as real cards.
## Every action still goes through disaster_actions.gd. This file only reads the mouse.
## Base threats, spells and evolutions work here. An evolution is dropped on a threat lane, which is also the first
## sacrifice. Cost 2 or 3 then asks for the other sacrifices by click.

const UI = preload("res://scripts/ui_theme.gd")
const Card3DScene = preload("res://scenes/card_3d.tscn")

# DESK_VIEW seen from the other side of the table.
const SEAT_VIEW := {"pos": Vector3(0, 1.0, 0.4), "rot": Vector3(-30, 180, 0), "dist": 5.3, "fov": 60.0}
const DRAG_START_PIXELS := 8.0
const HOLD_MOVE_PIXELS := 12.0
# The hand sits lower than the Response hand, so it leaves the threat lanes in view.
const SEAT_HAND_DROP := 0.26

var game: Node
var active := false
var seat_hand: Node3D
var cards: Array[Node3D] = []
var hovered: Node3D
var held: Node3D  # the card the left button is down on
var held_since := 0
var press_pos := Vector2.ZERO
var dragging := false
var selected: Node3D  # a card picked by a click, waits for a lane
var playing_card: Node3D  # the card whose action is running
var playing := false
var evo := {}  # an evolution waiting for sacrifices: card, definition, slot, chosen, serial. Empty = none
var mouse := Vector2.ZERO
var lane_material: StandardMaterial3D

func setup(manager: Node) -> void:
	game = manager
	seat_hand = Node3D.new()
	game.camera.add_child(seat_hand)

## True while a human Disaster waits for input and the seat view is on.
func _wants_seat() -> bool:
	if not game.disaster_seat_view or game.encounter_kind != "versus" or not game.disaster_is_human: return false
	if not is_instance_valid(game.run_director) or not game.run_director.battle_active: return false
	return game.disaster_waiting and game.phase == game.Phase.ENEMY

func _process(delta: float) -> void:
	var want := _wants_seat()
	if want != active: _set_active(want)
	if not active: return
	_sync_hand()
	_turn_board_cards(true)
	if game.run_director.modal.visible and (held != null or not evo.is_empty()): _cancel()
	if not evo.is_empty() and _evo_stale(): _cancel()
	_check_hold()
	if dragging and is_instance_valid(held): _follow_mouse(held, delta)
	else: _update_hover()
	_update_lanes()

## The flip is an instant cut. The privacy cover is already up when it happens.
func _set_active(on: bool) -> void:
	active = on
	game.disaster_seat_on = on
	if game.camera_tween: game.camera_tween.kill()
	game.opponent_hand.visible = not on
	if on:
		mouse = get_viewport().get_mouse_position()
		game._apply_view(SEAT_VIEW)
		game._view_forward_btn.disabled = true
		game._view_back_btn.disabled = true
		return
	_clear_all()
	_turn_board_cards(false)
	game._apply_view(game.view_settings(game.view_mode))
	game._update_view_buttons()

## Board cards read upside down from the far seat. While the seat is on, every card that has landed on a lane is
## turned half a circle, and turned back when the seat closes. A card still moving is left alone.
func _turn_board_cards(turned: bool) -> void:
	for card: Node in get_tree().get_nodes_in_group("cards"):
		if not is_instance_valid(card) or card.in_hand or card.current_slot == null: continue
		var rest: Vector3 = card.current_slot.global_position + Vector3(0, 0.008, 0)
		if card.global_position.distance_to(rest) > 0.02: continue
		var half_turn := absf(absf(card.rotation.y) - PI) < 0.05
		if turned and not half_turn and absf(card.rotation.y) < 0.05: card.rotation.y = PI
		elif not turned and half_turn: card.rotation.y = 0.0

func _clear_all() -> void:
	for card in cards: card.queue_free()
	cards.clear()
	hovered = null
	held = null
	selected = null
	playing_card = null
	evo = {}
	dragging = false
	_update_lanes()

# ------------------------------------------------------------------- hand
## One Card3D per entry in enemy_hand. Cards that left the hand are freed, new ones are added.
func _sync_hand() -> void:
	var pool: Array = game.enemy_hand.duplicate()
	var changed := false
	# The card being played goes last, so it is the one that is freed when it has left the hand.
	var order: Array = cards.filter(func(c): return c != playing_card)
	if playing_card in cards: order.append(playing_card)
	for card: Node3D in order:
		var index := pool.find(card.get_meta("seat_def"))
		if index >= 0:
			pool.remove_at(index)
			continue
		_remove_card(card)
		changed = true
	for definition: Dictionary in pool:
		_add_card(definition)
		changed = true
	if changed: _arrange()

func _add_card(definition: Dictionary) -> void:
	var card: Node3D = Card3DScene.instantiate()
	seat_hand.add_child(card)
	card.setup(definition)
	card.set_meta("seat_def", definition)
	card.position = Vector3(2.6, -0.6, -game.HAND_DIST)
	card.transform.basis = game.UPRIGHT.scaled(Vector3.ONE * game.HAND_SCALE)
	cards.append(card)

func _remove_card(card: Node3D) -> void:
	cards.erase(card)
	if card == hovered: hovered = null
	if card == held:
		held = null
		dragging = false
	if card == selected: selected = null
	if card == playing_card: playing_card = null
	if not evo.is_empty() and card == evo.card: evo = {}
	card.queue_free()

## Tight, overlapping, upright fan along the bottom of the screen, like the Response hand.
func _arrange() -> void:
	var count := cards.size()
	var spacing := minf(0.6, 3.4 / maxf(1.0, count))
	for i in count:
		var n := i - (count - 1) / 2.0
		var pos := Vector3(n * spacing, game.HAND_Y - SEAT_HAND_DROP - n * n * 0.012,
			-game.HAND_DIST + i * 0.002)
		var card_basis: Basis = Basis(Vector3.BACK, deg_to_rad(-n * 2.5)) * game.UPRIGHT
		var card := cards[i]
		card.set_meta("seat_pos", pos)
		card.set_meta("seat_basis", card_basis)
		if card == held and dragging: continue
		if card == hovered or card == selected:
			card.move_in_hand(pos + card.HOVER_LIFT, game.UPRIGHT, 100)
		else:
			card.move_in_hand(pos, card_basis, i)

# ------------------------------------------------------------------- hit tests
## The screen outline of a card. A raised card uses where it is now, the others where they rest.
func _polygon(card: Node3D, raised: bool) -> PackedVector2Array:
	var card_transform: Transform3D = card.global_transform
	if not raised:
		var rest_basis: Basis = card.get_meta("seat_basis")
		card_transform = seat_hand.global_transform * Transform3D(
			rest_basis.scaled(Vector3.ONE * game.HAND_SCALE), card.get_meta("seat_pos"))
	var polygon := PackedVector2Array()
	for corner in [Vector2(-0.55, -1), Vector2(0.55, -1), Vector2(0.55, 1), Vector2(-0.55, 1)]:
		var point := Vector3(corner.x, 0, corner.y * card.card_height / 2)
		polygon.append(game.camera.unproject_position(card_transform * point))
	return polygon

func _card_at(point: Vector2) -> Node3D:
	for card in [hovered, selected]:
		if is_instance_valid(card) and Geometry2D.is_point_in_polygon(point, _polygon(card, true)): return card
	var order := cards.duplicate()
	order.reverse()
	for card: Node3D in order:
		if card == held and dragging: continue
		if card.has_meta("seat_pos") and Geometry2D.is_point_in_polygon(point, _polygon(card, false)): return card
	return null

## The threat lane under a screen point.
func _lane_at(point: Vector2) -> Node3D:
	return _slot_at(point, game._threat_slots())

## Any lane of either side. A spell is dropped on the board.
func _board_slot_at(point: Vector2) -> Node3D:
	return _slot_at(point, game._threat_slots() + game._response_slots())

## The first of these slots under a screen point. Same ray and plane test as the Response lanes use.
func _slot_at(point: Vector2, slots: Array) -> Node3D:
	for slot: Node3D in slots:
		var plane := Plane(Vector3.UP, slot.global_position.y)
		var hit: Variant = plane.intersects_ray(game.camera.project_ray_origin(point),
			game.camera.project_ray_normal(point))
		if hit == null: continue
		var local: Vector3 = slot.to_local(hit)
		var bounds: AABB = slot.get_aabb()
		if local.x >= bounds.position.x and local.x <= bounds.end.x \
				and local.z >= bounds.position.z and local.z <= bounds.end.z:
			return slot
	return null

# ------------------------------------------------------------------- input
func _can_use() -> bool:
	if not active or playing or game.disaster_actions.busy: return false
	if game.run_director.modal.visible or game.run_director.privacy_screen.visible: return false
	return not game.presentation.blocking

# Motion and release come before the GUI, so a drag always ends. Presses come after it.
func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseMotion:
		mouse = event.position
		_maybe_start_drag()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse = event.position
		_on_release(event.position)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not evo.is_empty():
		_cancel()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_use() or not event is InputEventMouseButton or not event.pressed: return
	mouse = event.position
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()
	elif event.button_index == MOUSE_BUTTON_LEFT and _on_press(event.position):
		get_viewport().set_input_as_handled()

## Where a card is dropped: a Base card on a threat lane, a spell on any lane of the board.
func _drop_slot(card: Node3D, point: Vector2) -> Node3D:
	if card.get_meta("seat_def").get("utility", false): return _board_slot_at(point)
	return _lane_at(point)

## Returns true when the press was used.
func _on_press(point: Vector2) -> bool:
	# While sacrifices are picked, a click on a threat lane is the only thing that counts.
	if not evo.is_empty():
		_pick_sacrifice(point)
		return true
	var card := _card_at(point)
	var slot: Node3D = null
	if is_instance_valid(selected): slot = _drop_slot(selected, point)
	if card == null and slot != null and is_instance_valid(selected):
		_try_play(selected, slot)
		return true
	if selected != null and selected != card:
		selected = null
		_arrange()
	if card == null: return false
	held = card
	held_since = Time.get_ticks_msec()
	press_pos = point
	dragging = false
	return true

func _maybe_start_drag() -> void:
	if held == null or dragging or mouse.distance_to(press_pos) < DRAG_START_PIXELS: return
	dragging = true
	selected = null
	if held._tween: held._tween.kill()
	held.set_layer(100)
	held.quaternion = game.UPRIGHT.get_rotation_quaternion()

func _on_release(point: Vector2) -> void:
	if held == null: return
	var card := held
	held = null
	if not dragging:
		# A click: pick the card, or let go of it.
		selected = null if selected == card else card
		_arrange()
		return
	dragging = false
	var slot := _drop_slot(card, point)
	if slot != null and _can_use(): _try_play(card, slot)
	else: _arrange()

## Right click, Esc or a popup: put everything back in the hand. An evolution that waits is given back.
func _cancel() -> void:
	if not evo.is_empty():
		if is_instance_valid(evo.card): evo.card.visible = true
		evo = {}
	held = null
	dragging = false
	selected = null
	_arrange()

## A press that stays still opens the card inspection, like holding a Response card does.
func _check_hold() -> void:
	if held == null or dragging: return
	var waited := (Time.get_ticks_msec() - held_since) / 1000.0
	if waited < game.run_director.INSPECT_HOLD_SECONDS: return
	if mouse.distance_to(press_pos) > HOLD_MOVE_PIXELS: return
	var card := held
	held = null
	game.run_director.inspect_board_card(card, true)

func _update_hover() -> void:
	var picked: Node3D = null
	if _can_use() and evo.is_empty(): picked = _card_at(mouse)
	if picked == hovered: return
	hovered = picked
	_arrange()

func _follow_mouse(card: Node3D, delta: float) -> void:
	var origin: Vector3 = game.camera.project_ray_origin(mouse)
	var hit: Variant = Plane(Vector3.UP, 1.6).intersects_ray(origin, game.camera.project_ray_normal(mouse))
	if hit != null:
		card.global_position = card.global_position.lerp(game.clamp_drag_position(hit), 1.0 - exp(-20.0 * delta))
	card.global_position = game.clamp_drag_position(card.global_position)

# ------------------------------------------------------------------- playing
func _try_play(card: Node3D, slot: Node3D) -> void:
	var definition: Dictionary = card.get_meta("seat_def")
	selected = null
	if _is_evolution(definition):
		_try_evolve(card, definition, slot)
		return
	if definition.get("utility", false):
		_try_spell(card, definition)
		return
	playing = true
	playing_card = card
	card.visible = false
	var serial: int = game.encounter_serial
	var result: Dictionary = await game.disaster_actions.play_base(definition, slot)
	playing = false
	playing_card = null
	if serial != game.encounter_serial or result.ok or not is_instance_valid(card): return
	card.visible = true
	_refuse(card, game.run_director.DISASTER_REASONS.get(result.reason, "Action refused."))

func _is_evolution(definition: Dictionary) -> bool:
	return int(definition.get("cost", 0)) > 0 and not definition.get("utility", false)

## The evolution lands on the dropped lane, and the card there is the first sacrifice.
func _try_evolve(card: Node3D, definition: Dictionary, slot: Node3D) -> void:
	var actions: RefCounted = game.disaster_actions
	var reasons: Dictionary = game.run_director.DISASTER_REASONS
	var problem: String = actions.card_problem(definition)
	if problem.is_empty() and not actions.can_use(definition): problem = "bad_sacrifice"
	var first: Node = game._get_card_in_slot(slot)
	if problem.is_empty() and first not in actions.legal_sacrifices(definition): problem = "bad_sacrifice"
	if not problem.is_empty():
		_refuse(card, reasons.get(problem, "Action refused."))
		return
	if int(definition.get("cost", 0)) == 1:
		_evolve(card, definition, [first], slot)
		return
	# Cost 2 or 3: the card waits out of the hand while the other sacrifices are clicked.
	evo = {"card": card, "definition": definition, "slot": slot, "chosen": [first],
		"serial": game.encounter_serial}
	card.visible = false
	_arrange()
	_say_pick()

func _say_pick() -> void:
	var left: int = int(evo.definition.get("cost", 0)) - evo.chosen.size()
	evo.card.spawn_popup("Pick %d more card%s to sacrifice" % [left, "" if left == 1 else "s"], UI.AMBER)

## A click while sacrifices are picked. A lane with a legal card that is not chosen yet adds it.
func _pick_sacrifice(point: Vector2) -> void:
	var lane := _lane_at(point)
	if lane == null: return
	var target: Node = game._get_card_in_slot(lane)
	if target == null or target in evo.chosen: return
	if target not in game.disaster_actions.legal_sacrifices(evo.definition): return
	evo.chosen.append(target)
	if evo.chosen.size() < int(evo.definition.get("cost", 0)):
		_say_pick()
		return
	var card: Node3D = evo.card
	var definition: Dictionary = evo.definition
	var chosen: Array = evo.chosen
	var slot: Node3D = evo.slot
	evo = {}
	_evolve(card, definition, chosen, slot)

## The pick is stale when the turn changed or a chosen card is gone or may not be sacrificed any more.
func _evo_stale() -> bool:
	if evo.serial != game.encounter_serial or not is_instance_valid(evo.card): return true
	for target in evo.chosen:
		if not game.can_sacrifice(target): return true
	return false

func _evolve(card: Node3D, definition: Dictionary, sacrifices: Array, slot: Node3D) -> void:
	playing = true
	playing_card = card
	card.visible = false
	var serial: int = game.encounter_serial
	var result: Dictionary = await game.disaster_actions.evolve(definition, sacrifices, slot)
	playing = false
	playing_card = null
	if serial != game.encounter_serial or result.ok or not is_instance_valid(card): return
	card.visible = true
	_refuse(card, game.run_director.DISASTER_REASONS.get(result.reason, "Action refused."))

## A spell with no target is cast at once. A spell with a target asks for one in the same popup the panel uses.
func _try_spell(card: Node3D, definition: Dictionary) -> void:
	var actions: RefCounted = game.disaster_actions
	var director: Node = game.run_director
	var problem: String = actions.card_problem(definition)
	var targets: Array = actions.legal_targets(definition)
	if not actions.needs_target(definition) or not problem.is_empty() or targets.is_empty():
		# cast() gives the real reason. It changes nothing when it refuses.
		_cast(card, definition, null)
		return
	var serial: int = game.encounter_serial
	var title := "CHOOSE A TARGET · " + str(definition.get("name", "")).to_upper()
	director.choose_card(title, targets, _target_chosen.bind(card, definition, serial), director._cancel_disaster_pick)
	director.disaster_pick = {"kind": "target", "card": definition, "serial": serial}
	_arrange()

# choose_card binds the chosen card in front of the arguments bound here, so target comes first.
func _target_chosen(target: Node, card: Node3D, definition: Dictionary, serial: int) -> void:
	var director: Node = game.run_director
	director.disaster_pick = {}
	director.action_cancel = Callable()
	director.close_modal()
	if serial != game.encounter_serial or not is_instance_valid(target) or not is_instance_valid(card): return
	_cast(card, definition, target)

func _cast(card: Node3D, definition: Dictionary, target: Node) -> void:
	playing = true
	playing_card = card
	card.visible = false
	var serial: int = game.encounter_serial
	var result: Dictionary = await game.disaster_actions.cast(definition, target)
	playing = false
	playing_card = null
	if serial != game.encounter_serial or result.ok or not is_instance_valid(card): return
	card.visible = true
	_refuse(card, game.run_director.DISASTER_REASONS.get(result.reason, "Action refused."))

## The card goes back to the hand and a short note floats up from it.
func _refuse(card: Node3D, text: String) -> void:
	_arrange()
	if not text.is_empty() and is_instance_valid(card): card.spawn_popup(text, UI.AMBER)

## Open threat lanes glow while a Base card is dragged or picked. For an evolution, the lanes of the cards
## that may be sacrificed glow instead.
func _update_lanes() -> void:
	var card := held if dragging else selected
	var open: Array = []
	if active and not evo.is_empty():
		open = _sacrifice_lanes(evo.definition, evo.chosen)
	elif active and is_instance_valid(card):
		var definition: Dictionary = card.get_meta("seat_def")
		if _is_evolution(definition): open = _sacrifice_lanes(definition, [])
		else: open = game.disaster_actions.legal_lanes(definition)
	for slot: Node3D in game._threat_slots():
		var lit := slot in open
		if slot.visible == lit: continue
		slot.visible = lit
		slot.material_override = _lane_look() if lit else null

## Lanes holding a card that may be sacrificed and is not chosen yet.
func _sacrifice_lanes(definition: Dictionary, chosen: Array) -> Array:
	var lanes: Array = []
	for target in game.disaster_actions.legal_sacrifices(definition):
		if target not in chosen: lanes.append(target.current_slot)
	return lanes

func _lane_look() -> StandardMaterial3D:
	if lane_material == null:
		lane_material = StandardMaterial3D.new()
		lane_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lane_material.albedo_color = Color(UI.GOLD, 0.35)
		game.blink_tween(self, lane_material, "albedo_color", Color(UI.GOLD, 0.6), Color(UI.GOLD, 0.15))
	return lane_material
