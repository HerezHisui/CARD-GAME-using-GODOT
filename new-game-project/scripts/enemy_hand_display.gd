extends Node3D
var game: Node
var signature := -1
var material: StandardMaterial3D
var face: QuadMesh

func setup(manager: Node) -> void:
	game = manager
	material = StandardMaterial3D.new()
	material.albedo_texture = preload("res://scripts/card_3d.gd")._card_back()
	material.roughness = 0.8
	face = QuadMesh.new()
	face.size = Vector2(0.57, 0.78)

func refresh() -> void:
	var count: int = game.enemy_hand.size()
	# Face-down backs only display count; seals do not change their appearance.
	if signature == count: return
	signature = count
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for i in range(count):
		var back := MeshInstance3D.new()
		back.mesh = face
		back.material_override = material
		back.position = Vector3((i - (count - 1) / 2.0) * 0.28, 1.75, -2.6 - i * 0.008)
		back.rotation.z = deg_to_rad((i - (count - 1) / 2.0) * -4)
		add_child(back)
