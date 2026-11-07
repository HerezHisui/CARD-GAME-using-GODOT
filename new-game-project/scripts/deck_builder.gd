extends Control
## Versus deck builder. Built in code. Mouse only.
## setup(side, start_deck, director) fills it. Done emits a deck that passes VersusDecks.validate.
## A deck is {"main": [...], "evolutions": [...], "tactics": [...]} as in versus_decks.gd.

signal done(deck: Dictionary)
signal back

const UI = preload("res://scripts/ui_theme.gd")
const VersusDecks = preload("res://scripts/versus_decks.gd")
const BattleRules = preload("res://scripts/battle_rules.gd")
const ContingencyRules = preload("res://scripts/contingency_rules.gd")

const LIST_WIDTH := 760
const ROW_HEIGHT := 40
const MAX_TACTICS := 2  # picked tactics on top of Brace

var side := ""
var main_pool := {}  # id -> card definition the main deck may use
var evolution_pool := {}  # id -> card definition, Disaster only
var main: Array[String] = []
var evolutions: Array[String] = []
var tactics: Array[String] = []  # Brace first, then the picked ones
var count_labels := {}  # "pile/id" -> Label "x/2"
var plus_buttons := {}  # "pile/id" -> Button
var minus_buttons := {}  # "pile/id" -> Button
var tactic_boxes := {}  # tactic id -> CheckBox
var card_list: VBoxContainer
var main_label: Label
var evolution_label: Label
var error_label: Label
var done_button: Button
var reset_button: Button
var back_button: Button


## side is VersusDecks.SIDE_PREP or SIDE_DISASTER. director may be null (tests, preview).
func setup(new_side: String, start_deck: Dictionary, director = null) -> void:
	side = new_side
	if director != null and is_instance_valid(director) and director.get("root") is Control:
		theme = director.root.theme
	else:
		theme = UI.get_theme()
	var cards := VersusDecks.pool(side)
	main_pool = cards.base.duplicate()
	main_pool.merge(cards.spells)
	evolution_pool = cards.evolutions
	_load_deck(start_deck)
	_build()
	_refresh()


## Copy a deck into the builder. Brace is always in; at most 2 other known tactics.
func _load_deck(deck: Dictionary) -> void:
	main.assign(deck.get("main", []))
	evolutions.assign(deck.get("evolutions", []))
	tactics.clear()
	if side != VersusDecks.SIDE_PREP: return
	tactics.append("brace")
	var start_tactics: Array = deck.get("tactics", [])
	for tactic: Dictionary in ContingencyRules.TACTICS:
		var id: String = tactic.id
		if id != "brace" and id in start_tactics and tactics.size() < MAX_TACTICS + 1:
			tactics.append(id)


# =================================================================== LAYOUT
func _build() -> void:
	for child in get_children(): child.queue_free()
	count_labels.clear()
	plus_buttons.clear()
	minus_buttons.clear()
	tactic_boxes.clear()
	evolution_label = null
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel", UI.panel(UI.BACKGROUND, UI.BRONZE, 16))
	add_child(frame)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	frame.add_child(columns)
	columns.add_child(_build_list())
	columns.add_child(_build_side_column())


## Left: title and the scrolling card rows.
func _build_list() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = LIST_WIDTH
	var title := _label(_side_title(), UI.HEADING_SIZE, UI.GOLD)
	left.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "CardScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	card_list = VBoxContainer.new()
	card_list.name = "CardList"
	card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card_list)
	if side == VersusDecks.SIDE_DISASTER:
		card_list.add_child(_label("Main deck (base and spells)", UI.BODY_SIZE, UI.BRONZE))
		_add_rows("main", main_pool)
		card_list.add_child(_label("Evolution pile", UI.BODY_SIZE, UI.BRONZE))
		_add_rows("evolutions", evolution_pool)
	else:
		card_list.add_child(_label("Main deck", UI.BODY_SIZE, UI.BRONZE))
		_add_rows("main", main_pool)
	return left


## Right: counters, tactics, errors and the three buttons.
func _build_side_column() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	main_label = _label("", UI.BODY_SIZE, UI.TEXT)
	main_label.name = "MainCount"
	right.add_child(main_label)
	if side == VersusDecks.SIDE_DISASTER:
		evolution_label = _label("", UI.BODY_SIZE, UI.TEXT)
		evolution_label.name = "EvolutionCount"
		right.add_child(evolution_label)
	if side == VersusDecks.SIDE_PREP:
		right.add_child(_label("Tactics: Brace plus 2 more", UI.BODY_SIZE, UI.BRONZE))
		for tactic: Dictionary in ContingencyRules.TACTICS:
			right.add_child(_tactic_box(tactic))
	error_label = _label("", UI.SMALL_SIZE, UI.DANGER)
	error_label.name = "ErrorLabel"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(error_label)
	reset_button = _button("Reset to Standard", "ResetButton", _on_reset)
	right.add_child(reset_button)
	done_button = _button("Done", "DoneButton", _on_done)
	right.add_child(done_button)
	back_button = _button("Back", "BackButton", func() -> void: back.emit())
	right.add_child(back_button)
	return right


## One row per card id in a pile, sorted by cost then name.
func _add_rows(pile: String, cards: Dictionary) -> void:
	var defs: Array = cards.values()
	defs.sort_custom(_card_before)
	for card: Dictionary in defs:
		card_list.add_child(_card_row(pile, card))


func _card_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("cost", 0)) != int(b.get("cost", 0)):
		return int(a.get("cost", 0)) < int(b.get("cost", 0))
	return str(a.get("name", "")) < str(b.get("name", ""))


func _card_row(pile: String, card: Dictionary) -> Control:
	var id: String = card.id
	var key := pile + "/" + id
	var row := HBoxContainer.new()
	row.name = "Row_%s_%s" % [pile, id]
	row.custom_minimum_size.y = ROW_HEIGHT
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = row_tooltip(card)
	var text := _label(row_text(card), UI.SMALL_SIZE, UI.TEXT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	var count := _label("", UI.BODY_SIZE, UI.GOLD)
	count.custom_minimum_size.x = 44
	count_labels[key] = count
	row.add_child(count)
	var minus := _button("-", "Minus_%s_%s" % [pile, id], _remove.bind(pile, id))
	minus.custom_minimum_size = Vector2(36, 32)
	minus_buttons[key] = minus
	row.add_child(minus)
	var plus := _button("+", "Plus_%s_%s" % [pile, id], _add.bind(pile, id))
	plus.custom_minimum_size = Vector2(36, 32)
	plus_buttons[key] = plus
	row.add_child(plus)
	return row


func _tactic_box(tactic: Dictionary) -> CheckBox:
	var box := CheckBox.new()
	var id: String = tactic.id
	box.name = "Tactic_" + id
	box.text = str(tactic.name)
	box.tooltip_text = str(tactic.description)
	box.button_pressed = id in tactics
	if id == "brace": box.disabled = true  # Brace is always in the deck
	else: box.toggled.connect(_on_tactic_toggled.bind(id))
	tactic_boxes[id] = box
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	return button


func _side_title() -> String:
	return "PREPAREDNESS DECK" if side == VersusDecks.SIDE_PREP else "DISASTER DECK"


# =================================================================== CARD TEXT
## "Name  cost  element  ATK/HP  effect" on one line.
static func row_text(card: Dictionary) -> String:
	var effect := effect_text(card)
	return _row_head(card) if effect == "" else _row_head(card) + "  " + effect


## Full text for the row's tooltip: the head on one line, the whole effect below it.
static func row_tooltip(card: Dictionary) -> String:
	var effect := effect_text(card)
	return _row_head(card) if effect == "" else _row_head(card) + "\n" + effect


## "Name  cost  element  ATK/HP". ATK/HP only when the card has them.
static func _row_head(card: Dictionary) -> String:
	var parts: PackedStringArray = [str(card.get("name", card.get("id", ""))), "%d" % int(card.get("cost", 0)),
		str(card.get("element", "")).capitalize()]
	if card.has("attack") and card.has("health"):
		parts.append("%d/%d" % [int(card.attack), int(card.health)])
	return "  ".join(parts)


## Effect text from the same helpers the cards use.
static func effect_text(card: Dictionary) -> String:
	var parts: PackedStringArray = []
	var effect := str(card.get("effect", ""))
	if effect != "" and card.get("utility", false):
		parts.append(BattleRules.utility_text(card))
	elif effect != "":
		parts.append(str(BattleRules.EFFECT_LABELS.get(effect, effect.capitalize())))
	if card.has("modifier"):
		parts.append(BattleRules.modifier_text(card, str(card.modifier)))
	var on_hit: Variant = card.get("on_hit", {})
	if on_hit is Dictionary:
		for status in on_hit:
			parts.append("On hit: %d %s." % [int(on_hit[status]), str(status).capitalize()])
	# The deck builder is a Versus screen, so it shows the Versus entry Barrier.
	var nerf: bool = preload("res://scripts/versus_match.gd").DISASTER_ENTRY_BARRIER_NERF
	var special := BattleRules.special_text(card, nerf)
	if special != "": parts.append(special.replace("\n", " "))
	return " ".join(parts)


# =================================================================== CHANGES
func _pile(pile: String) -> Array[String]:
	return evolutions if pile == "evolutions" else main


func _pile_size(pile: String) -> int:
	return VersusDecks.EVOLUTION_SIZE if pile == "evolutions" else VersusDecks.MAIN_SIZE


func can_add(pile: String, id: String) -> bool:
	var cards := _pile(pile)
	return cards.count(id) < VersusDecks.MAX_COPIES and cards.size() < _pile_size(pile)


func _add(pile: String, id: String) -> void:
	if not can_add(pile, id): return
	_pile(pile).append(id)
	_refresh()


func _remove(pile: String, id: String) -> void:
	var cards := _pile(pile)
	if id not in cards: return
	cards.erase(id)
	_refresh()


func _on_tactic_toggled(pressed: bool, id: String) -> void:
	if pressed and id not in tactics and tactics.size() < MAX_TACTICS + 1:
		tactics.append(id)
	elif pressed and id not in tactics:
		tactic_boxes[id].set_pressed_no_signal(false)  # already 2 picks: undo the check
	elif not pressed:
		tactics.erase(id)
	_refresh()


func _on_reset() -> void:
	_load_deck(VersusDecks.preset(side))
	for id: String in tactic_boxes:
		tactic_boxes[id].set_pressed_no_signal(id in tactics)
	_refresh()


func _on_done() -> void:
	var deck := current_deck()
	if not VersusDecks.validate(side, deck).ok: return  # Done never sends a bad deck
	done.emit(deck)


## The deck as it is now, in the versus_decks.gd shape.
func current_deck() -> Dictionary:
	var picked: Array[String] = []
	picked.assign(tactics)
	return {"main": main.duplicate(), "evolutions": evolutions.duplicate(), "tactics": picked}


## Update counts, buttons, tactic boxes and errors after every change.
func _refresh() -> void:
	main_label.text = "Main %d/%d" % [main.size(), VersusDecks.MAIN_SIZE]
	if evolution_label != null:
		evolution_label.text = "Evolutions %d/%d" % [evolutions.size(), VersusDecks.EVOLUTION_SIZE]
	for key: String in count_labels:
		var pile := key.get_slice("/", 0)
		var id := key.get_slice("/", 1)
		count_labels[key].text = "%d/%d" % [_pile(pile).count(id), VersusDecks.MAX_COPIES]
		plus_buttons[key].disabled = not can_add(pile, id)
		minus_buttons[key].disabled = id not in _pile(pile)
	var full := tactics.size() >= MAX_TACTICS + 1
	for id: String in tactic_boxes:
		if id != "brace": tactic_boxes[id].disabled = full and id not in tactics
	var check := VersusDecks.validate(side, current_deck())
	error_label.text = "\n".join(check.errors)
	done_button.disabled = not check.ok
