extends Node3D
## A flat standee: a leader's cut-out picture on a thin dark card cut to its outline. Presentation only, no skeleton.
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
## The card: 2.0 tall like the old figure, and thin. The standee spans CARD_HEIGHT from base to head;
## the post is CARD_DEPTH thick.
const CARD_HEIGHT := 2.0
const CARD_DEPTH := 0.02
## The outline card behind the picture: the same cut-out, this much larger, this far behind the picture.
## The larger edge shows as a thin dark rim, like the edge of cardboard.
const RIM_SCALE := 1.03
const RIM_GAP := 0.01
## The post from the base up to the hips. Never wider than the hips.
const POST_WIDTH := 0.08
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

## Makes the outline card, the picture, the post and the base. The suites measure all meshes together.
func build(id: String) -> void:
	var texture: Texture2D = load(CUTS[id])
	var picture_width := PICTURE_HEIGHT * texture.get_width() / texture.get_height()
	var card_material := StandardMaterial3D.new()
	card_material.albedo_color = CARD_COLOUR
	var top := CARD_HEIGHT * 0.5
	var picture_at := Vector3(0, top - PICTURE_HEIGHT * 0.5, CARD_DEPTH * 0.5 + PICTURE_GAP)
	# The outline card: the cut-out's shape filled with the card colour, both faces drawn.
	var cut := texture.get_image()
	if cut.is_compressed(): cut.decompress()
	var fill := Image.create(cut.get_width(), cut.get_height(), false, Image.FORMAT_RGBA8)
	fill.fill(CARD_COLOUR)
	var outline := Image.create(cut.get_width(), cut.get_height(), false, Image.FORMAT_RGBA8)
	outline.blit_rect_mask(fill, cut, Rect2i(Vector2i.ZERO, cut.get_size()), Vector2i.ZERO)
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_texture = ImageTexture.create_from_image(outline)
	rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim_quad := QuadMesh.new()
	rim_quad.size = Vector2(picture_width, PICTURE_HEIGHT) * RIM_SCALE
	add_mesh("Rim", rim_quad, rim_material, picture_at - Vector3(0, 0, RIM_GAP))
	# The cut-out in front of the rim, top edge at the standee's top. Alpha scissor keeps a hard edge.
	picture_material = StandardMaterial3D.new()
	picture_material.albedo_texture = texture
	picture_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	apply_shading()
	var quad := QuadMesh.new()
	quad.size = Vector2(picture_width, PICTURE_HEIGHT)
	add_mesh("Picture", quad, picture_material, picture_at)
	# The post stands under the middle of the hips (the bottom row of the cut-out).
	var hips := hips_span(cut)
	var hips_mid := ((hips.x + hips.y) * 0.5 / cut.get_width() - 0.5) * picture_width
	var hips_width := (hips.y - hips.x) * picture_width / cut.get_width()
	var post_box := BoxMesh.new()
	var post_bottom := -top + BASE_HEIGHT
	var post_top := top - PICTURE_HEIGHT
	post_box.size = Vector3(minf(POST_WIDTH, hips_width), post_top - post_bottom, CARD_DEPTH)
	add_mesh("Post", post_box, card_material, Vector3(hips_mid, (post_top + post_bottom) * 0.5, 0))
	var base_box := BoxMesh.new()
	base_box.size = Vector3(picture_width * 0.6, BASE_HEIGHT, BASE_DEPTH)
	add_mesh("Base", base_box, card_material, Vector3(0, -top + BASE_HEIGHT * 0.5, 0))

## The first and last solid pixel of the cut-out's bottom row, in pixels. The whole row when none is solid.
static func hips_span(cut: Image) -> Vector2:
	var row := cut.get_height() - 1
	var first := -1
	var last := -1
	for x in cut.get_width():
		if cut.get_pixel(x, row).a > 0.5:
			if first < 0: first = x
			last = x
	if first < 0: return Vector2(0, cut.get_width())
	return Vector2(first, last + 1)

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
