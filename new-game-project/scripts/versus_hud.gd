extends Node
## Versus-only look for the HUD. A Versus match reuses the singleplayer HUD, which has parts that mean nothing there.
## While a match runs this node hides those parts, shows Energy and Tension as bars under each side's HP plate,
## adds a round and turn plate, and shows a note when the Disaster has no Tension left.
## It changes nothing in a singleplayer run. Set ENABLED to false to get the old Versus HUD back.
## Child of run_director. run_director._process calls update() last, so it has the final word on what shows.

const UI = preload("res://scripts/ui_theme.gd")
const ENABLED := true
const VersusMatch = preload("res://scripts/versus_match.gd")
const HEALTH_TOP := 66.0
const HEALTH_HEIGHT := 60.0
const HEALTH_WIDTH := 300.0
const HUD_MARGIN := 16.0
const OUT_OF_TENSION := "Not enough Tension."
const NOTE_SECONDS := 2.4

var director: Node
var game: Node
var active := false
var built := false

var turn_plate: PanelContainer
var round_label: Label
var side_label: Label
var energy_plate: PanelContainer
var energy_bar: ProgressBar
var tension_plate: PanelContainer
var tension_bar: ProgressBar
var note: PanelContainer
var note_head: Label
var note_body: Label
var note_tween: Tween
var pulse_tween: Tween
var last_side := ""
var saved_fills := {} # HP bar fills put back when the match ends
var disaster_plans: Button
var disaster_grave: Button
var saved_health := {}
var saved_grave := [] # Graveyard button offsets put back when the match ends

func setup(owner_director: Node) -> void:
	director = owner_director
	game = director.game

## The side whose turn it is. "" outside a turn (coin flip, game over).
func turn_side() -> String:
	if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: last_side = "preparedness"
	elif game.phase == game.Phase.ENEMY: last_side = "disaster"
	elif game.phase in [game.Phase.SETUP, game.Phase.GAME_OVER]: last_side = ""
	return last_side

## "P1" or "P2" for a side once the coin flip has given out the sides. "" before that.
func player_tag(side: String) -> String:
	var match_node = director.versus_match
	if not is_instance_valid(match_node) or str(match_node.player1_side).is_empty(): return ""
	return "P1" if match_node.player1_side == side else "P2"

## The deck the Deck button shows: the side that sits at the table right now.
func deck_side() -> String:
	return "disaster" if game.disaster_seat_on else "preparedness"

func deck_title() -> String:
	return "DISASTER DECK" if deck_side() == "disaster" else "PREPAREDNESS DECK"

## Every card the side started with. The Disaster list holds the evolutions too.
func deck_cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	cards.assign(game.versus_master.get(deck_side(), []))
	return cards

# ------------------------------------------------------------------- build
func _build() -> void:
	built = true
	var top_bar: Control = game.get_node("HUD/TopBar")
	var hud_root: Control = game.get_node("HUD/Root")
	# Turn plate, top centre.
	turn_plate = PanelContainer.new()
	turn_plate.name = "VersusTurnPlate"
	turn_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_plate.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
	turn_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	turn_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	turn_plate.offset_top = 7
	turn_plate.custom_minimum_size = Vector2(300, 34)
	top_bar.add_child(turn_plate)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	turn_plate.add_child(row)
	round_label = _label(row, 18, UI.MUTED)
	side_label = _label(row, 20, UI.GOLD)
	# Energy (Preparedness) and Tension (Disaster) sit under the two HP plates.
	energy_plate = _resource_plate(hud_root, "VersusEnergy", "ENERGY")
	energy_bar = energy_plate.get_meta("bar")
	tension_plate = _resource_plate(hud_root, "VersusTension", "TENSION")
	tension_bar = tension_plate.get_meta("bar")
	# The note for a refused action.
	note = PanelContainer.new()
	note.name = "VersusNote"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_stylebox_override("panel", _plate_style(UI.ACTION, 2, 14))
	note.set_anchors_preset(Control.PRESET_CENTER_TOP)
	note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note.offset_top = 70
	note.custom_minimum_size = Vector2(360, 0)
	note.modulate.a = 0.0
	note.visible = false
	hud_root.add_child(note)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(box)
	note_head = _label(box, 34, UI.DANGER)
	note_body = _label(box, 20, UI.TEXT)
	note_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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

func _resource_plate(parent: Control, plate_name: String, title: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = plate_name
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.add_theme_stylebox_override("panel", _plate_style(UI.BRONZE.darkened(0.2)))
	plate.visible = false
	parent.add_child(plate)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	plate.add_child(box)
	var heading := _label(box, 18, UI.GOLD)
	heading.text = title
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 24)
	bar.show_percentage = false
	box.add_child(bar)
	var value := _label(bar, 18, UI.TEXT)
	value.name = "Value"
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.set_meta("bar", bar)
	return plate

# ------------------------------------------------------------------- update
func update() -> void:
	var on: bool = ENABLED and game.encounter_kind == "versus" and director.battle_active
	if on != active: _set_active(on)
	if not active: return
	_refresh()

## Parts of the singleplayer HUD that mean nothing in a Versus match.
func _clutter() -> Array[CanvasItem]:
	var parts: Array[CanvasItem] = [game._view_forward_btn, game._view_back_btn]
	for path in ["HUD/TopBar/SuppliesIcon", "HUD/TopBar/SuppliesLabel"]:
		parts.append(game.get_node(path))
	return parts

func _marks() -> Array[Label]:
	var marks: Array[Label] = []
	for health: Control in [game._player_hp_ui, game._enemy_hp_ui]:
		marks.append(health.get_node("HealthMark"))
	return marks

func _set_active(on: bool) -> void:
	active = on
	if on and not built: _build()
	for part in _clutter(): part.visible = not on
	for mark in _marks():
		mark.text = "" if on else "+"
		mark.visible = true
	if is_instance_valid(turn_plate): turn_plate.visible = on
	if is_instance_valid(energy_plate): energy_plate.visible = on
	if is_instance_valid(tension_plate): tension_plate.visible = on
	if is_instance_valid(disaster_plans): disaster_plans.visible = false
	if is_instance_valid(disaster_grave): disaster_grave.visible = false
	_style_hp_fills(on)
	if on:
		for pair in [[energy_bar, game._player_hp_ui], [tension_bar, game._enemy_hp_ui]]:
			var hp: ProgressBar = pair[1].get_node("Bar")
			for part in ["background", "fill"]:
				pair[0].add_theme_stylebox_override(part, hp.get_theme_stylebox(part))
	_move_graveyard(on)
	if on:
		last_side = ""
	else:
		_restore_health()
		_stop_pulse()
		director.prep.get_parent().modulate.a = 1.0
		director.threat.get_parent().modulate.a = 1.0
		if is_instance_valid(note):
			note.visible = false
			note.modulate.a = 0.0

## The Energy gauge that stood beside the Graveyard button is gone, so the button moves to the corner.
func _move_graveyard(on: bool) -> void:
	var grave: Button = director.graveyard_button
	if on and saved_grave.is_empty():
		saved_grave = [grave.offset_left, grave.offset_right]
		grave.offset_right = 16.0 + (grave.offset_right - grave.offset_left)
		grave.offset_left = 16.0
	elif not on and not saved_grave.is_empty():
		grave.offset_left = saved_grave[0]
		grave.offset_right = saved_grave[1]
		saved_grave = []

## The Disaster HP bar gets a crimson fill so the two sides read apart at a glance.
func _style_hp_fills(on: bool) -> void:
	var bar: ProgressBar = game._enemy_hp_ui.get_node("Bar")
	if on:
		saved_fills["fill"] = bar.get_theme_stylebox("fill")
		var fill := UI.bar(UI.ACTION.darkened(0.15))
		fill.set_corner_radius_all(0)
		fill.set_border_width_all(0)
		fill.set_expand_margin_all(-2)
		fill.content_margin_left = 5
		fill.content_margin_right = 5
		bar.add_theme_stylebox_override("fill", fill)
	elif saved_fills.has("fill"):
		bar.add_theme_stylebox_override("fill", saved_fills["fill"])
		saved_fills.erase("fill")

static func health_rect(view_width: float, on_left: bool) -> Rect2:
	var width := minf(HEALTH_WIDTH, (view_width - HUD_MARGIN * 3.0) / 2.0)
	var x := HUD_MARGIN if on_left else view_width - HUD_MARGIN - width
	return Rect2(x, HEALTH_TOP, width, HEALTH_HEIGHT)

func _layout_health() -> void:
	if not VersusMatch.SIDE_BY_SIDE_HUD: return
	var disaster_left: bool = game.lan_remote_prep or (not game.lan_remote_disaster and game.disaster_seat_on)
	var width := get_viewport().get_visible_rect().size.x
	for health: Control in [game._player_hp_ui, game._enemy_hp_ui]:
		if not saved_health.has(health):
			saved_health[health] = [health.offset_left, health.offset_top, health.offset_right, health.offset_bottom]
		var on_left: bool = (health == game._player_hp_ui) != disaster_left
		var rect := health_rect(width, on_left)
		health.size = rect.size
		health.global_position = rect.position
	# Preserve the hidden Janitor in the Disaster seat camera.
	var far_seat: bool = game.disaster_seat_on or game.lan_disaster_view()
	game.opponent_hand.visible = not director.modal.visible and not far_seat
	game.opponent_hand.character.holding.visible = not far_seat

func _restore_health() -> void:
	for health: Control in saved_health:
		var offsets: Array = saved_health[health]
		health.offset_left = offsets[0]
		health.offset_top = offsets[1]
		health.offset_right = offsets[2]
		health.offset_bottom = offsets[3]
	saved_health.clear()
	game.opponent_hand.character.holding.visible = true

func _refresh() -> void:
	_layout_health()
	_update_disaster_controls()
	# The singleplayer gauges are replaced by the Versus bars. They stay in the tree, only clear,
	# so the code that shows and hides them is untouched.
	director.prep.get_parent().modulate.a = 0.0
	director.threat.get_parent().modulate.a = 0.0
	var side := turn_side()
	var seated_disaster: bool = game.disaster_seat_on
	# Whose side is whose: P1 / P2 where the "+" used to be.
	var marks := _marks()
	marks[0].text = player_tag("preparedness")
	marks[1].text = player_tag("disaster")
	# Turn plate.
	turn_plate.visible = not side.is_empty()
	if turn_plate.visible:
		round_label.text = "ROUND %d" % game.turn
		var who := side.to_upper()
		var tag := player_tag(side)
		side_label.text = who if tag.is_empty() else "%s  %s" % [tag, who]
		side_label.add_theme_color_override("font_color", UI.DANGER if side == "disaster" else UI.GOLD)
	# Energy and Tension plates sit under the HP plates; the side that is not playing is dimmed.
	var left: Control = game._player_hp_ui.get_node("Plate")
	var right: Control = game._enemy_hp_ui.get_node("Plate")
	var top := maxf(left.global_position.y + left.size.y, right.global_position.y + right.size.y) + 6.0
	_place(energy_plate, left.global_position.x, top, left.size.x)
	_place(tension_plate, right.global_position.x, top, right.size.x)
	energy_plate.visible = true
	tension_plate.visible = true
	energy_plate.modulate.a = 0.5 if side == "disaster" else 1.0
	tension_plate.modulate.a = 1.0 if side == "disaster" else 0.5
	_update_resource(energy_plate, energy_bar, game.preparedness, game.energy_cap, "Energy")
	_update_resource(tension_plate, tension_bar, game.tension, game.tension_cap, "Tension")
	# The Disaster has no tactics, and its draw pile is its own deck.
	if seated_disaster:
		director.plans_button.visible = false
		game.get_node("HUD/Root/DeckDrawButton/DeckCountLabel").text = str(game.enemy_deck.size())
	# End turn glows once the seated Disaster has spent its Tension.
	var spent: bool = seated_disaster and game.tension <= 0 and not game.disaster_actions.busy
	if spent: _start_pulse()
	else: _stop_pulse()

func _place(plate: PanelContainer, x: float, y: float, width: float) -> void:
	plate.custom_minimum_size = Vector2(width, 0)
	plate.size = Vector2(width, plate.get_combined_minimum_size().y)
	plate.global_position = Vector2(x, y)

func _update_resource(plate: PanelContainer, bar: ProgressBar, current: int, cap: int, title: String) -> void:
	current = maxi(current, 0)
	cap = maxi(cap, 0)
	bar.max_value = maxi(cap, 1)
	bar.value = current if cap > 0 else 0
	var text := "%d / %d" % [current, cap]
	bar.get_node("Value").text = text
	plate.tooltip_text = title + ": " + text

# ------------------------------------------------------------------- note and pulse
## A big note near the top for a refused action. It fades by itself.
func show_note(head: String, body: String) -> void:
	if not active or not built: return
	note_head.text = head.to_upper()
	note_body.text = body
	note.visible = true
	if note_tween: note_tween.kill()
	note.modulate.a = 0.0
	note_tween = create_tween()
	note_tween.tween_property(note, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	note_tween.tween_interval(NOTE_SECONDS)
	note_tween.tween_property(note, "modulate:a", 0.0, 0.3)
	note_tween.tween_callback(func(): note.visible = false)

func _start_pulse() -> void:
	if pulse_tween and pulse_tween.is_valid(): return
	var button: Button = game._end_turn_btn
	pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(button, "self_modulate", Color(1.5, 1.35, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(button, "self_modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE)

func _stop_pulse() -> void:
	if pulse_tween: pulse_tween.kill()
	pulse_tween = null
	if is_instance_valid(game) and is_instance_valid(game._end_turn_btn): game._end_turn_btn.self_modulate = Color.WHITE

func _open_disaster_plans() -> void:
	if game.evolution_choice.enabled(): game.evolution_choice.show_held()
	else: show_note("Coming later", "Disaster plans are coming later.")

func _update_disaster_controls() -> void:
	if not VersusMatch.SIDE_BY_SIDE_HUD: return
	if not is_instance_valid(disaster_plans):
		disaster_plans = director.plans_button.duplicate(0)
		disaster_plans.name = "DisasterPlansButton"
		disaster_plans.icon = null
		var icon: TextureRect = disaster_plans.get_node("HubIcon")
		icon.texture = load("res://assets/ui/contingency_disaster.svg")
		icon.modulate = UI.GOLD
		disaster_plans.text = ""
		disaster_plans.get_node("CountLabel").text = ""
		disaster_plans.pressed.connect(_open_disaster_plans)
		game.get_node("HUD/Root").add_child(disaster_plans)
		disaster_grave = director.graveyard_button.duplicate(0)
		disaster_grave.name = "DisasterGraveyardButton"
		disaster_grave.pressed.connect(director.show_graveyard.bind("disaster"))
		game.get_node("HUD/Root").add_child(disaster_grave)
	var local_disaster: bool = game.lan_remote_prep or (not game.lan_remote_disaster and game.disaster_seat_on)
	var on: bool = local_disaster and not director.modal.visible
	disaster_plans.text = ""
	disaster_plans.get_node("HubIcon").visible = true
	disaster_plans.tooltip_text = "Evolution" if game.evolution_choice.enabled() else ""
	disaster_plans.get_node("CountLabel").text = (
		str(game.evolution_choice.held.size()) if game.evolution_choice.enabled() else "")
	disaster_plans.visible = on
	disaster_grave.visible = on and not game.presentation.blocking
	if not local_disaster: return
	director.plans_button.visible = false
	director.graveyard_button.visible = false
	disaster_plans.disabled = director._dragging() or not game.board_input.action.is_empty()
	disaster_grave.disabled = disaster_plans.disabled
	disaster_plans.size = director.plans_button.size
	disaster_plans.global_position = director.plans_button.global_position
	disaster_grave.size = director.graveyard_button.size
	disaster_grave.global_position = director.graveyard_button.global_position
	disaster_grave.get_node("CountLabel").text = str(game.disaster_graveyard.size())
