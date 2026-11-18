extends Node3D
## A flat standee: a leader's cut-out picture on a thin dark card. Presentation only, no skeleton.
## It offers what preparedness_figure.gd offers (hidden at start, place_at, same scale, no shadow, no collision),
## so the seat that holds it does not need to know which figure it is.
## Shape (contract A): 2.0 units tall, centred on the origin, front to +Z.

## Off until Simple has played it. Only tests reach the standee, through game.standee_override.
const STANDEE_ENABLED := false
## The cut-out picture of each leader that has a standee.
const CUTS := {"robin": "res://assets/characters/standees/robin.png"}
const PrepFigure = preload("res://scripts/preparedness_figure.gd")
## Same scale and lift as the Preparedness figure, so both stand the same.
const FIGURE_SCALE := PrepFigure.FIGURE_SCALE
const FEET_LIFT := PrepFigure.FEET_LIFT
## The card: 2.0 tall like the old figure, and thin.
const CARD_HEIGHT := 2.0
const CARD_DEPTH := 0.02
## The interface panel grey.
const CARD_COLOUR := Color("#1e1c20")
## The picture ends at the hips, so it covers only the upper part of the card, head at head height.
## Tuned from 1.15: at 0.77 the hips line sits at the desk edge seen from the Disaster seat.
const PICTURE_HEIGHT := 0.77
## The picture sits this far in front of the card face.
const PICTURE_GAP := 0.001
## The small base at the bottom of the card.
const BASE_HEIGHT := 0.04
const BASE_DEPTH := 0.3
## true shows the picture unshaded (no room light), for a comparison frame. Call apply_shading() after a change.
var unshaded := false
var picture_material: StandardMaterial3D

## The standee id for this game, or "". Only the test override picks one today.
static func leader(game: Node) -> String:
	var id: Variant = game.standee_override
	if id is String and CUTS.has(id): return id
	return ""

## The figure for the player's seat: a standee when a leader has one, else the Preparedness figure.
static func make_for(game: Node) -> Node3D:
	var id := leader(game)
	if id == "": return PrepFigure.new()
	var standee: Node3D = load("res://scripts/standee_figure.gd").new()
	standee.build(id)
	return standee

func _ready() -> void:
	name = "StandeeFigure"
	scale = Vector3.ONE * FIGURE_SCALE
	hide()

## Makes the card, the picture and the base. The card must be the first mesh: the suites measure it.
func build(id: String) -> void:
	var texture: Texture2D = load(CUTS[id])
	var picture_width := PICTURE_HEIGHT * texture.get_width() / texture.get_height()
	var card_material := StandardMaterial3D.new()
	card_material.albedo_color = CARD_COLOUR
	var card_box := BoxMesh.new()
	card_box.size = Vector3(picture_width, CARD_HEIGHT, CARD_DEPTH)
	add_mesh("Card", card_box, card_material, Vector3.ZERO)
	# The cut-out on the front face, top edge on the card's top edge. Alpha scissor keeps a hard edge.
	picture_material = StandardMaterial3D.new()
	picture_material.albedo_texture = texture
	picture_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	apply_shading()
	var quad := QuadMesh.new()
	quad.size = Vector2(picture_width, PICTURE_HEIGHT)
	var top := CARD_HEIGHT * 0.5
	add_mesh("Picture", quad, picture_material,
		Vector3(0, top - PICTURE_HEIGHT * 0.5, CARD_DEPTH * 0.5 + PICTURE_GAP))
	var base_box := BoxMesh.new()
	base_box.size = Vector3(picture_width * 0.6, BASE_HEIGHT, BASE_DEPTH)
	add_mesh("Base", base_box, card_material, Vector3(0, -top + BASE_HEIGHT * 0.5, 0))

## Shaded takes the room's light like the cards on the table; unshaded is for the comparison frame.
func apply_shading() -> void:
	picture_material.shading_mode = (BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL)

## One mesh child with no shadow, so the standee never darkens the cards.
func add_mesh(mesh_name: String, mesh: Mesh, material: Material, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

## Puts the standee on the seat marker, facing the table (-Z).
func place_at(anchor: Node3D) -> void:
	global_position = anchor.global_position + Vector3(0, FEET_LIFT, 0)
	rotation_degrees.y = 180.0
