extends Node3D
## The Preparedness figure at the player's end of the table. Presentation only, no skeleton.
## It is shown only while the camera sits at the Disaster seat, the mirror of the Janitor.
const MODEL = preload("res://assets/characters/preparedness/preparedness_figure.glb")
## Same scale as the Janitor (enemy_hand_display.gd), so both figures are the same height.
const FIGURE_SCALE := 2.65
## The mesh is centred on its origin and 2 units tall. This lifts the feet to the Janitor's floor line.
const FEET_LIFT := 0.25 + FIGURE_SCALE
## How much the figure grows and shrinks while it breathes.
const BREATH_AMOUNT := 0.012
## Radians per second of the breathing.
const BREATH_SPEED := 1.4
var model: Node3D
var breath_time := 0.0

func _ready() -> void:
	name = "PreparednessFigure"
	model = MODEL.instantiate()
	add_child(model)
	# No shadows, so the figure never darkens the cards. It has no collision, so mouse rays pass.
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * FIGURE_SCALE
	hide()

## Puts the figure on the seat marker, facing the table (-Z).
func place_at(anchor: Node3D) -> void:
	global_position = anchor.global_position + Vector3(0, FEET_LIFT, 0)
	rotation_degrees.y = 180.0

## A slow breathing scale while the figure is on screen.
func _process(delta: float) -> void:
	if not visible: return
	breath_time += delta * BREATH_SPEED
	var breath := 1.0 + BREATH_AMOUNT * sin(breath_time)
	model.scale = Vector3(1.0, breath, 1.0)
