extends Node3D
## Reusable framed school slate; collision and lane ownership stay with Slots.
const WIDTH := 4.34
const DEPTH := 2.5
const BOARD = preload("res://scenes/school_drill_board.tscn")
func _ready() -> void:
	name = "Playmat"
	add_child(BOARD.instantiate())
	for slot in get_parent().get_node("Slots").get_children(): slot.visible = false
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("77603c")
	brass.metallic = 0.7
	brass.roughness = 0.56
	var cap := BoxMesh.new()
	cap.size = Vector3(0.22, 0.006, 0.045)
	cap.material = brass
	for x in [-1, 1]:
		for z in [-1, 1]:
			var corner := MeshInstance3D.new()
			corner.name = "BrassCorner"
			corner.mesh = cap
			corner.position = Vector3(x * 2.12, 1.022, z * 1.27)
			add_child(corner)
