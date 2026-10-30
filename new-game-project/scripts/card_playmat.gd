extends Node3D
## Imported game board; collision and lane ownership stay with Slots.
const WIDTH := 5.3
const DEPTH := 3.2
# Measured from the GLB recess boundaries, rather than the outer frame or screenshots.
const SLOT_COLUMNS := [-0.3011, -0.0993, 0.1000, 0.3020]
const SLOT_ROWS := [-0.2230, 0.2230]
const RECESS_HEIGHT := 1.0133
const SLOT_HEIGHT := 1.016
const BOARD = preload("res://scenes/school_drill_board.tscn")
func _ready() -> void:
	name = "Playmat"
	add_child(BOARD.instantiate())
	for slot in get_parent().get_node("Slots").get_children(): slot.visible = false
