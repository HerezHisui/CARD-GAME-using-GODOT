extends Control
## Preview only: open tests/deck_builder_preview.tscn and press F6 to look at the deck builder.
## Not part of the game flow. Done and Back only print; nothing is saved.

const DeckBuilder = preload("res://scripts/deck_builder.gd")
const VersusDecks = preload("res://scripts/versus_decks.gd")
const UI = preload("res://scripts/ui_theme.gd")

var builder: Control


func _ready() -> void:
	theme = UI.get_theme()
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(16, 8)
	add_child(buttons)
	buttons.add_child(_side_button("Preparedness", "PreparednessButton", VersusDecks.SIDE_PREP))
	buttons.add_child(_side_button("Disaster", "DisasterButton", VersusDecks.SIDE_DISASTER))


func _side_button(text: String, node_name: String, side: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(_open.bind(side))
	return button


## Replace the open builder with one for this side, below the two buttons.
func _open(side: String) -> void:
	if is_instance_valid(builder): builder.queue_free()
	builder = DeckBuilder.new()
	add_child(builder)
	builder.setup(side, VersusDecks.preset(side), null)
	builder.offset_top = 56
	builder.done.connect(func(deck: Dictionary) -> void: print("Done: ", deck))
	builder.back.connect(func() -> void: print("Back"))
