extends Node3D
## Adapts the modular art scene to the existing card-table camera and input.
const ROOM = preload("res://assets/classroom/classroom.tscn")
const ROOM_SCALE := 1.6
const ROOM_OFFSET := Vector3(0, -0.1, -2.8)

func _ready() -> void:
	name = "SchoolEnvironment"
	var room: Node3D = ROOM.instantiate()
	room.name = "ModularClassroom"
	# Only the game owns cameras, input, and the WorldEnvironment. Decoration
	# must never intercept the physics rays used to select slots and cards.
	for child_name in ["Camera", "MidnightEnvironment", "Physics"]:
		var child := room.get_node_or_null(child_name)
		if child:
			room.remove_child(child)
			child.free()
	room.scale = Vector3.ONE * ROOM_SCALE
	room.position = ROOM_OFFSET
	clear_table_space(room.get_node("StudentDesks"))
	clear_table_space(room.get_node("StudentChairs"))
	add_child(room)
	build_table_frame()
	build_moonbeams(room)
	build_dust(room)

func clear_table_space(group: Node3D) -> void:
	for batch in group.get_children():
		if not batch is MultiMeshInstance3D: continue
		var source: MultiMesh = batch.multimesh
		var kept: Array[Transform3D] = []
		for i in source.instance_count:
			var transform := source.get_instance_transform(i)
			var at := transform.origin * ROOM_SCALE + ROOM_OFFSET
			if absf(at.x) < 4.8 and at.z > -5.3: continue
			kept.append(transform)
		# A fresh resource keeps the original modular room reusable elsewhere.
		var trimmed := MultiMesh.new()
		trimmed.transform_format = MultiMesh.TRANSFORM_3D
		trimmed.mesh = source.mesh
		trimmed.instance_count = kept.size()
		for i in kept.size(): trimmed.set_instance_transform(i, kept[i])
		batch.multimesh = trimmed

func build_table_frame() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("303b46")
	material.roughness = .65
	material.metallic = .45
	var leg := BoxMesh.new()
	leg.size = Vector3(.14, .96, .14)
	leg.material = material
	for x in [-2.8, 2.8]:
		for z in [-1.35, 1.35]:
			var node := MeshInstance3D.new()
			node.name = "PlayTableLeg"
			node.mesh = leg
			node.position = Vector3(x, .4, z)
			add_child(node)

func build_moonbeams(room: Node3D) -> void:
	if RenderingServer.get_current_rendering_method() == "forward_plus": return
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/classroom/materials/moonbeams.gdshader")
	for z in [-5.0, -2.0, 1.0, 4.0]:
		var start := Vector3(-5.84, 3.45, z)
		var finish := start + Vector3(8.9, -3.25, -2.4)
		var across := Vector3(0, .32, .82)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([start-across, start+across, finish+across, finish-across])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var beam := MeshInstance3D.new()
		beam.name = "WindowMoonbeam"
		beam.mesh = mesh
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		room.add_child(beam)

func build_dust(room: Node3D) -> void:
	var dust := CPUParticles3D.new()
	dust.name = "ClassroomDust"
	dust.amount = 32
	dust.lifetime = 35
	dust.preprocess = 5
	dust.position = Vector3(-3.8, 2.1, -1)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.2, 1.5, 5)
	dust.gravity = Vector3(0, -.002, 0)
	dust.initial_velocity_min = .004
	dust.initial_velocity_max = .012
	var mesh := SphereMesh.new()
	mesh.radius = .002
	mesh.height = .004
	mesh.radial_segments = 4
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.65, .75, .95)
	material.roughness = 1
	mesh.material = material
	dust.mesh = mesh
	room.add_child(dust)
