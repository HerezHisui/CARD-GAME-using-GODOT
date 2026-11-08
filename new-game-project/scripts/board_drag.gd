extends RefCounted
## Shared drag and lane-glow code for the Disaster seat and the LAN board.

const UI = preload("res://scripts/ui_theme.gd")


## Moves a held card toward the mouse on the drag plane, kept inside the board.
static func follow_mouse(game: Node, mouse: Vector2, card: Node3D, delta: float) -> void:
	var origin: Vector3 = game.camera.project_ray_origin(mouse)
	var hit: Variant = Plane(Vector3.UP, 1.6).intersects_ray(origin, game.camera.project_ray_normal(mouse))
	if hit != null:
		card.global_position = card.global_position.lerp(game.clamp_drag_position(hit), 1.0 - exp(-20.0 * delta))
	card.global_position = game.clamp_drag_position(card.global_position)


## Makes the blinking gold lane material. The blink tween belongs to owner.
static func new_lane_material(game: Node, owner: Node) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(UI.GOLD, 0.35)
	game.blink_tween(owner, material, "albedo_color", Color(UI.GOLD, 0.6), Color(UI.GOLD, 0.15))
	return material
