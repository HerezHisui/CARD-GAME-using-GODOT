extends Control
## LAN Part D2-c: plain 2D board for a remote Preparedness player. Built in code, runs no game rules.
## It only draws a view from lan_view.gd (build(game, "preparedness")). The Disaster panel is
## lan_client_panel.gd. Lane buttons light up only where the host's hints allow.
## lan_session.attach_prep_panel connects the signals to the network.

signal hand_pressed(index: int)
signal tactic_pressed(id: String)
signal lane_pressed(lane: int)
signal end_turn_pressed
signal back_pressed
# Flag on: a pick from the open utility choice (a list entry), or its cancel. Lane picks use lane_pressed.
signal choice_picked(handle: int)
signal choice_cancelled

const LANE_COUNT := 4

var view: Dictionary = {}
var selected := -1  # picked hand card, or -1
var selected_tactic := ""  # picked tactic id, or ""
var over_text := ""  # set when the match ended, so a late view keeps it

var header: Label
var disaster_row: HBoxContainer
var response_row: HBoxContainer
var info: Label
var hand_row: HBoxContainer
var tactic_row: HBoxContainer
var reject_label: Label
var end_button: Button
var back_button: Button
var choice_label: Label
var choice_row: HBoxContainer
var choice_cancel: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	header = _add_label(box)
	disaster_row = _add_row(box)
	response_row = _add_row(box)
	info = _add_label(box)
	hand_row = _add_row(box)
	tactic_row = _add_row(box)
	# Flag on: the open utility choice. Hidden unless the host sends one, so the flag-off panel is unchanged.
	choice_label = _add_label(box)
	choice_label.visible = false
	choice_row = _add_row(box)
	choice_row.visible = false
	choice_cancel = Button.new()
	choice_cancel.text = "Cancel"
	choice_cancel.visible = false
	choice_cancel.pressed.connect(func() -> void: choice_cancelled.emit())
	box.add_child(choice_cancel)
	reject_label = _add_label(box)
	end_button = Button.new()
	end_button.text = "End Turn"
	end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	box.add_child(end_button)
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
	view = new_view
	selected = -1
	selected_tactic = ""
	if is_node_ready():
		_redraw()


# Show why the host refused the last action.
func show_reject(reason: String) -> void:
	if is_node_ready():
		reject_label.text = "Refused: " + ("Not available in LAN" if reason == "not_supported" else reason)


# The host says who won. No more turns, only Back to title.
func show_match_over(winner: String) -> void:
	if not is_node_ready():
		return
	over_text = "Match over: %s wins" % winner.capitalize()
	header.text = over_text
	end_button.disabled = true
	back_button.visible = true


func _redraw() -> void:
	var sides: Dictionary = view.sides
	header.text = "Round %d | %s | Preparedness HP %d | Disaster HP %d | Energy %d/%d" % [
		view.round, "Your turn" if view.is_prep_turn else "Their turn",
		sides.response.hp, sides.disaster.hp, view.energy, view.energy_cap,
	]
	var counts: Dictionary = view.counts
	var armed: String = view.armed if view.armed != "" else "none"
	info.text = "Their hand: %d | Your deck: %d | Plan tokens: %d | Armed: %s" % [
		counts.disaster_hand, counts.response_draw, view.plan_tokens, armed,
	]
	_fill_lanes(disaster_row, "disaster", _field_lanes())
	_fill_lanes(response_row, "response", _allowed_lanes())
	_fill_hand()
	_fill_tactics()
	_fill_choice()
	end_button.disabled = not view.is_prep_turn or not view.get("pending_choice", {}).is_empty()
	if over_text != "":
		header.text = over_text
		end_button.disabled = true


# Lanes the pick may use: free lanes for a unit, ally lanes for a tactic.
func _allowed_lanes() -> Array:
	var open: Dictionary = view.get("pending_choice", {})
	if not open.is_empty(): return open.handles.duplicate() if open.stage in ["ally", "destination"] else []
	if selected_tactic != "":
		for tactic in view.tactics:
			if tactic.id == selected_tactic:
				return tactic.lanes
		return []
	if selected < 0 or selected >= view.hints.size():
		return []
	return view.hints[selected].lanes


# Flag on: a Seal choice lights the Disaster lanes it may pick. Otherwise the Disaster row stays dark.
func _field_lanes() -> Array:
	var open: Dictionary = view.get("pending_choice", {})
	return open.handles.duplicate() if not open.is_empty() and open.stage == "field" else []


func _fill_lanes(row: HBoxContainer, side: String, allowed: Array) -> void:
	_clear(row)
	for lane in LANE_COUNT:
		var button := Button.new()
		button.text = _card_text(view.lanes[side][lane])
		button.custom_minimum_size = Vector2(140, 60)
		button.disabled = lane not in allowed
		button.pressed.connect(func() -> void: lane_pressed.emit(lane))
		row.add_child(button)


func _fill_hand() -> void:
	_clear(hand_row)
	for index in view.prep_hand.size():
		var button := Button.new()
		button.text = _card_text(view.prep_hand[index])
		button.disabled = not view.hints[index].can_play
		if view.hints[index].get("problem", "") == "not_supported":
			button.text += " (Not available in LAN)"
			button.tooltip_text = "Not available in LAN"
		button.toggle_mode = true
		button.button_pressed = index == selected
		button.pressed.connect(_on_hand_pressed.bind(index))
		hand_row.add_child(button)


func _fill_tactics() -> void:
	_clear(tactic_row)
	for tactic in view.tactics:
		var button := Button.new()
		button.text = "%s (%d)" % [tactic.name, tactic.cost]
		button.disabled = not tactic.available
		if _tactic_unsupported(tactic):
			button.text += " (Not available in LAN)"
			button.tooltip_text = "Not available in LAN"
		button.toggle_mode = true
		button.button_pressed = tactic.id == selected_tactic
		button.pressed.connect(_on_tactic_pressed.bind(str(tactic.id)))
		tactic_row.add_child(button)


func _on_hand_pressed(index: int) -> void:
	if view.hints[index].get("problem", "") == "not_supported":
		show_reject("not_supported")
		return
	selected = index
	selected_tactic = ""
	hand_pressed.emit(index)
	_redraw()


# Flag on: the host marks Supply Line, Shelter ("no_ally") and Extraction ("pick") as playable.
func _tactic_unsupported(tactic: Dictionary) -> bool:
	if tactic.has("no_ally") or tactic.has("pick"): return false
	return str(tactic.id) in preload("res://scripts/preparedness_actions.gd").NOT_SUPPORTED_TACTICS


func _on_tactic_pressed(id: String) -> void:
	for tactic in view.tactics:
		if tactic.id == id and _tactic_unsupported(tactic):
			show_reject("not_supported")
			return
	selected = -1
	selected_tactic = id
	tactic_pressed.emit(id)
	_redraw()


# The open utility choice: its prompt, the list entries to pick from, and Cancel. All hidden when nothing is open.
func _fill_choice() -> void:
	var open: Dictionary = view.get("pending_choice", {})
	choice_label.visible = not open.is_empty()
	choice_row.visible = not open.is_empty()
	choice_cancel.visible = not open.is_empty()
	_clear(choice_row)
	if open.is_empty(): return
	choice_label.text = "%s: %s" % [open.name, open.prompt]
	for entry in open.get("candidates", []):
		var button := Button.new()
		button.text = _candidate_text(entry)
		button.pressed.connect(func() -> void: choice_picked.emit(int(entry.handle)))
		choice_row.add_child(button)


# A deck or graveyard entry shows its card. A Disaster hand entry is blind: the host sends no face.
func _candidate_text(entry: Dictionary) -> String:
	if not entry.has("card"): return "Hidden card %d" % (int(entry.handle) + 1)
	var definition: Dictionary = entry.card
	if definition.get("utility", false): return str(definition.get("name", "?"))
	return "%s %d/%d" % [definition.get("name", "?"), definition.get("attack", 0), definition.get("health", 0)]


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
