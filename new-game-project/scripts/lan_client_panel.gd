extends Control
## LAN Part B: plain 2D board for the remote Disaster. Built in code, runs no game rules.
## It only draws a view from lan_view.gd. Lane buttons light up only where the host's hints allow.
## Part C connects the signals to the network.

signal relocation_picked(msg: Dictionary)
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
	var old_choice: int = int(view.get("relocation", {}).get("choice", -1))
	view = new_view
	var relocation: Dictionary = view.get("relocation", {})
	if old_choice != int(relocation.get("choice", -1)) or relocation_ally not in relocation.get("allies", []):
		relocation_ally = -1
	relocation_sent = false
	selected = -1
	if is_node_ready():
		_redraw()


# Show why the host refused the last action.
func show_reject(reason: String) -> void:
	if is_node_ready():
		reject_label.text = "Refused: " + reason


# Part E: the host says who won. No more turns, only Back to title.
func show_match_over(winner: String) -> void:
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
	if over_text != "":
		header.text = over_text
		end_button.disabled = true


# Lanes the picked card may use: free lanes for a base, sacrifice lanes for an evolution.
func _allowed_lanes() -> Array:
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
		button.disabled = not view.hints[index].can_use or not view.get("relocation", {}).is_empty()
		button.toggle_mode = true
		button.button_pressed = index == selected
		button.pressed.connect(_on_hand_pressed.bind(index))
		hand_row.add_child(button)


func _on_hand_pressed(index: int) -> void:
	if not view.get("relocation", {}).is_empty(): return
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
