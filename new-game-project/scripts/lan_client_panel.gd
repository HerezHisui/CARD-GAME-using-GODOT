extends Control
## LAN Part B: plain 2D board for the remote Disaster. Built in code, runs no game rules.
## It only draws a view from lan_view.gd. Lane buttons light up only where the host's hints allow.
## Part C connects the signals to the network.

signal relocation_picked(msg: Dictionary)
signal evolution_pick_requested(msg: Dictionary)
signal held_pressed(id: String)
signal hand_pressed(index: int)
signal lane_pressed(lane: int)
signal end_turn_pressed
# Part E: the Back to title button after the match ended.
signal back_pressed

const LANE_COUNT := 4

var view: Dictionary = {}
var selected := -1
var relocation_ally := -1
var relocation_sent := false
var over_text := ""  # Part E: set when the match ended, so a late view keeps it

var header: Label
var response_row: HBoxContainer
var disaster_row: HBoxContainer
var hand_row: HBoxContainer
var info: Label
var reject_label: Label
var end_button: Button
var back_button: Button
var evolution_button: Button
var evolution_director: Node
var evolution_layer: CanvasLayer
var evolution_choices: HBoxContainer
var evolution_cancel: Button
var evolution_browser := false
var evolution_sent := false
var evolution_key := ""
var selected_held_id := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	header = _add_label(box)
	response_row = _add_row(box)
	disaster_row = _add_row(box)
	info = _add_label(box)
	hand_row = _add_row(box)
	reject_label = _add_label(box)
	end_button = Button.new()
	end_button.text = "End Turn"
	end_button.pressed.connect(func() -> void:
		if not view.get("evolution_waiting", false): end_turn_pressed.emit())
	box.add_child(end_button)
	evolution_button = Button.new()
	evolution_button.visible = false
	evolution_button.pressed.connect(show_held_evolutions)
	box.add_child(evolution_button)
	back_button = Button.new()
	back_button.text = "Back to title"
	back_button.visible = false
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	box.add_child(back_button)
	if not view.is_empty():
		_redraw()
	else:
		header.text = "Connected. Waiting for the host to start..."


func _add_label(parent: Node) -> Label:
	var label := Label.new()
	parent.add_child(label)
	return label


func _add_row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row


# Draw a new view from the host. Clears the pick, because the hand may have changed.
func show_view(new_view: Dictionary) -> void:
	if new_view.has("match_id") and new_view.match_id != view.get("match_id"):
		close_evolution_browser()
		evolution_sent = false
		over_text = ""
		if is_instance_valid(back_button): back_button.hide()
	var old_choice: int = int(view.get("relocation", {}).get("choice", -1))
	view = new_view
	var relocation: Dictionary = view.get("relocation", {})
	if old_choice != int(relocation.get("choice", -1)) or relocation_ally not in relocation.get("allies", []):
		relocation_ally = -1
	relocation_sent = false
	selected = -1
	selected_held_id = ""
	var offer: Dictionary = view.get("evolution_offer", {})
	var key := "%s:%s" % [offer.get("match_id", ""), offer.get("offer_id", "")]
	if key != evolution_key:
		evolution_sent = false
		evolution_key = key
		close_evolution_browser()
	if view.get("side", "disaster") != "disaster": reset_evolutions()
	if is_node_ready():
		_redraw()
	_refresh_evolutions()


# Show why the host refused the last action.
func show_reject(reason: String) -> void:
	if is_node_ready():
		reject_label.text = "Refused: " + reason
	if evolution_sent:
		evolution_sent = false
		_refresh_evolutions()


# Part E: the host says who won. No more turns, only Back to title.
func show_match_over(winner: String) -> void:
	reset_evolutions()
	if not is_node_ready():
		return
	over_text = "Match over: %s wins" % winner.capitalize()
	header.text = over_text
	end_button.disabled = true
	back_button.visible = true
	if not view.get("relocation", {}).is_empty(): _redraw()


func _redraw() -> void:
	var sides: Dictionary = view.sides
	header.text = "Round %d | %s | Preparedness HP %d | Disaster HP %d | Tension %d/%d" % [
		view.round, "Your turn" if view.is_disaster_turn else "Their turn",
		sides.response.hp, sides.disaster.hp, sides.disaster.resource, sides.disaster.resource_cap,
	]
	var counts: Dictionary = view.counts
	info.text = "Their hand: %d | Your deck: %d | Evolutions: %d | Actions left: %d" % [
		counts.response_hand, counts.disaster_draw, counts.disaster_evolution, view.actions_left,
	]
	if not view.get("relocation", {}).is_empty():
		info.text = "Crosswind: choose an ally lane." if relocation_ally < 0 else "Crosswind: choose an empty lane."
	_fill_lanes(response_row, "response", [])
	_fill_lanes(disaster_row, "disaster", _allowed_lanes())
	_fill_hand()
	end_button.disabled = not view.is_disaster_turn or not view.get("relocation", {}).is_empty()
	if view.has("evolution_waiting"):
		end_button.disabled = end_button.disabled or view.evolution_waiting
		evolution_button.visible = view.has("held_evolutions")
		evolution_button.text = "Evolution (%d)" % view.get("held_evolutions", []).size()
		if view.evolution_waiting: info.text = "Disaster is choosing an evolution..."
	if over_text != "":
		header.text = over_text
		end_button.disabled = true


# Lanes the picked card may use: free lanes for a base, sacrifice lanes for an evolution.
func _allowed_lanes() -> Array:
	if view.get("evolution_waiting", false): return []
	if not selected_held_id.is_empty():
		for entry in view.get("held_evolutions", []):
			if entry.id == selected_held_id: return entry.hints.get("sacrifices", [])
	if not view.get("relocation", {}).is_empty(): return relocation_lanes()
	if selected < 0 or selected >= view.hints.size():
		return []
	var hint: Dictionary = view.hints[selected]
	return hint.sacrifices if not hint.sacrifices.is_empty() else hint.lanes


func _fill_lanes(row: HBoxContainer, side: String, allowed: Array) -> void:
	_clear(row)
	for lane in LANE_COUNT:
		var button := Button.new()
		button.text = _card_text(view.lanes[side][lane])
		button.custom_minimum_size = Vector2(140, 60)
		button.disabled = side == "response" or lane not in allowed
		button.pressed.connect(func() -> void:
			if not view.get("relocation", {}).is_empty(): pick_relocation(lane)
			else: lane_pressed.emit(lane)
		)
		row.add_child(button)


func _fill_hand() -> void:
	_clear(hand_row)
	for index in view.disaster_hand.size():
		var button := Button.new()
		button.text = _card_text(view.disaster_hand[index])
		button.disabled = not view.hints[index].can_use or not view.get("relocation", {}).is_empty() \
			or view.get("evolution_waiting", false)
		button.toggle_mode = true
		button.button_pressed = index == selected
		button.pressed.connect(_on_hand_pressed.bind(index))
		hand_row.add_child(button)


func _on_hand_pressed(index: int) -> void:
	if view.get("evolution_waiting", false): return
	if not view.get("relocation", {}).is_empty(): return
	selected_held_id = ""
	selected = index
	hand_pressed.emit(index)
	_redraw()


# Name plus attack and health, or "-" for an empty lane.
func _card_text(id: String) -> String:
	if id == "" or not view.cards.has(id):
		return "-"
	var definition: Dictionary = view.cards[id].definition
	if definition.get("utility", false):
		return str(definition.get("name", "?"))
	return "%s %d/%d" % [definition.get("name", "?"), definition.get("attack", 0), definition.get("health", 0)]


func _clear(row: Node) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


func relocation_lanes() -> Array:
	if over_text != "" or relocation_sent or not view.get("is_disaster_turn", false): return []
	var relocation: Dictionary = view.get("relocation", {})
	return relocation.get("allies" if relocation_ally < 0 else "destinations", [])

func pick_relocation(lane: int) -> void:
	if lane not in relocation_lanes(): return
	if relocation_ally < 0:
		relocation_ally = lane
	else:
		var relocation: Dictionary = view.relocation
		relocation_sent = true
		relocation_picked.emit({"kind": "move_ally", "choice": relocation.choice,
			"encounter": relocation.encounter, "ally": relocation_ally, "lane": lane})
	if is_node_ready(): _redraw()


# This layer stays visible when the 3D board hides the plain panel below it.
func setup_evolutions(owner_director: Node) -> void:
	evolution_director = owner_director
	_refresh_evolutions()


func evolution_open() -> bool:
	return is_instance_valid(evolution_layer)


func close_evolution_browser() -> void:
	if is_instance_valid(evolution_layer):
		evolution_layer.hide()
		evolution_layer.queue_free()
	evolution_layer = null
	evolution_choices = null
	evolution_cancel = null
	evolution_browser = false


func reset_evolutions() -> void:
	close_evolution_browser()
	selected_held_id = ""
	evolution_key = ""
	evolution_sent = false
	if is_instance_valid(evolution_button): evolution_button.hide()
	for field in ["evolution_offer", "held_evolutions", "match_id", "evolution_waiting"]: view.erase(field)


func show_held_evolutions() -> void:
	if over_text != "" or not view.has("held_evolutions"): return
	if not view.get("evolution_offer", {}).is_empty():
		_refresh_evolutions()
		return
	evolution_browser = true
	_refresh_evolutions()


func _refresh_evolutions() -> void:
	if not is_instance_valid(evolution_director) or over_text != "": return
	var offer: Dictionary = view.get("evolution_offer", {})
	var held_open := evolution_browser
	close_evolution_browser()
	if offer.is_empty() and (not held_open or not view.has("held_evolutions")): return
	evolution_browser = offer.is_empty()
	evolution_layer = CanvasLayer.new()
	evolution_layer.layer = 25
	add_child(evolution_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	evolution_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	evolution_layer.add_child(center)
	var frame := PanelContainer.new()
	frame.theme = evolution_director.root.theme
	frame.add_theme_stylebox_override("panel", evolution_director.style(
		preload("res://scripts/ui_theme.gd").PANEL, preload("res://scripts/ui_theme.gd").GOLD))
	var viewport := get_viewport_rect().size
	frame.custom_minimum_size = Vector2(minf(960, viewport.x - 48), minf(640, viewport.y - 48))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	frame.add_child(box)
	box.add_child(evolution_director.label("HELD EVOLUTIONS" if evolution_browser else "CHOOSE AN EVOLUTION",
		28, preload("res://scripts/ui_theme.gd").GOLD, true))
	var prompt := "Choose a card, then click its sacrifice lanes on the board." if evolution_browser \
		else "Choose 1. The other cards stay in the deck."
	if evolution_sent: prompt = "Waiting for the host..."
	box.add_child(evolution_director.label(prompt, 20))
	var screen: Control = preload("res://scenes/ui/ui_choose_cards.tscn").instantiate()
	box.add_child(screen)
	evolution_choices = screen.get_node("Cards/Row")
	evolution_cancel = screen.get_node("CancelButton")
	evolution_cancel.visible = evolution_browser
	evolution_cancel.pressed.connect(close_evolution_browser)
	var entries: Array = view.get("held_evolutions", []) if evolution_browser else offer.get("candidates", [])
	for entry in entries:
		var action: Callable = _select_held.bind(str(entry.id)) if evolution_browser else \
			_choose_evolution.bind(str(entry.id), str(offer.match_id), int(offer.offer_id))
		evolution_director._card_tile(entry.card, evolution_choices, action, "Choose", true)
		var tile: Control = evolution_choices.get_child(-1)
		# Private previews stay inside this disposable layer, outside the shared catalog inspector.
		var face: Control = tile.get_node("Box/Center").get_child(0).get_child(0)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.set_meta("evolution_id", entry.id)
		tile.get_node("Box/ActionButton").disabled = evolution_sent or \
			(evolution_browser and not entry.hints.get("can_use", false))
		for child in tile.get_children():
			if child is Node3D and child.get("preview_only") == true:
				child.preview_seal_round = int(view.get("round", 1))
				child._refresh_face()


func _choose_evolution(id: String, match_id: String, offer_id: int) -> void:
	var offer: Dictionary = view.get("evolution_offer", {})
	if evolution_sent or offer.get("match_id") != match_id or offer.get("offer_id") != offer_id: return
	if not offer.get("candidates", []).any(func(entry): return entry.id == id): return
	evolution_sent = true
	for tile in evolution_choices.get_children(): tile.get_node("Box/ActionButton").disabled = true
	evolution_pick_requested.emit({"kind": "evolution_pick", "match_id": match_id, "offer_id": offer_id, "id": id})


func _select_held(id: String) -> void:
	if view.get("evolution_waiting", false): return
	for entry in view.get("held_evolutions", []):
		if entry.id != id or not entry.hints.get("can_use", false): continue
		close_evolution_browser()
		selected_held_id = id
		selected = -1
		held_pressed.emit(id)
		_redraw()
		return


func _input(event: InputEvent) -> void:
	if not evolution_open() or not event is InputEventKey: return
	if event.pressed and event.keycode == KEY_ESCAPE and evolution_browser: close_evolution_browser()
	if event.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: get_viewport().set_input_as_handled()
