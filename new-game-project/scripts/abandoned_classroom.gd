extends Node3D
## The front-right, skewed student desk marked in the supplied reference is the board.
const ROOM = preload("res://assets/abandoned_classroom/source/old_abandoned_classroom.glb")
const ATLAS = preload("res://assets/abandoned_classroom/textures/Bitmap2Material_3_Base_Color.tga.png")
# Coordinates below are in original mesh-space metres after a -90 degree yaw.
const DESK_CENTER := Vector3(1.88549, 1.11895, 3.485565)
const DESK_YAW := 13.2825
const ROOM_SCALE := 2.5
const TABLE_SIZE := Vector3(6.35, 0.1184, 2.684)
var room_frame: Node3D

func _ready() -> void:
	name = "SchoolEnvironment"
	room_frame = Node3D.new()
	room_frame.name = "AbandonedClassroom"
	room_frame.rotation_degrees.y = DESK_YAW
	room_frame.scale = Vector3.ONE * ROOM_SCALE
	room_frame.position = Vector3(0, 1, 0) - room_frame.basis * DESK_CENTER
	add_child(room_frame)
	var source: Node3D = ROOM.instantiate()
	source.name = "OriginalRoom"
	room_frame.add_child(source)
	# Cancel the viewer export's root conversion, leaving the original mesh-space
	# metre coordinates used by DESK_CENTER. Every material mesh shares this rig.
	var reference: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0]
	var exported_rig := source.global_transform.affine_inverse() * reference.global_transform
	source.transform = Transform3D(Basis(Vector3.UP, -PI / 2), Vector3.ZERO) * exported_rig.affine_inverse()
	for mesh in source.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var imported = mesh.get_active_material(surface)
			if not imported is StandardMaterial3D: continue
			var material: StandardMaterial3D = imported.duplicate()
			# Preserve the GLB's author-supplied PBR values and texture resolutions.
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if imported.resource_name == "glass":
				# The viewer's transmission material must admit sunlight. Godot's
				# alpha/depth import can otherwise shadow it like solid wall panels.
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.set_surface_override_material(surface, material)
	add_fixture_glow(source)
	close_open_edges()
	add_sunlight()

func add_fixture_glow(source: Node3D) -> void:
	# Only the downward fluorescent faces emit; chairs and other white material
	# parts retain the GLB's original shading.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for node in source.find_children("*", "MeshInstance3D", true, false):
		if "white" not in str(node.name): continue
		var transform: Transform3D = room_frame.global_transform.affine_inverse() * node.global_transform
		var faces: PackedVector3Array = node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a: Vector3 = transform * faces[i]
			var b: Vector3 = transform * faces[i + 1]
			var c: Vector3 = transform * faces[i + 2]
			var normal := (b - a).cross(c - a).normalized()
			if minf(a.y, minf(b.y, c.y)) < 3.8 or absf(normal.y) < 0.95: continue
			for point in [a, b, c]:
				surface.set_normal(Vector3.DOWN)
				surface.add_vertex(point - Vector3(0, 0.006, 0))
			count += 1
	if count == 0: return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d5d2bc")
	material.emission_enabled = true
	material.emission = Color("fff1d1")
	material.emission_energy_multiplier = 3.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var strips := MeshInstance3D.new()
	strips.name = "FluorescentGlow"
	strips.mesh = surface.commit()
	strips.material_override = material
	strips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room_frame.add_child(strips)

func enclosure_material(region: Rect2) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ATLAS
	material.uv1_scale = Vector3(region.size.x, region.size.y, 1)
	material.uv1_offset = Vector3(region.position.x, region.position.y, 0)
	material.roughness = 1
	return material

func panel(title: String, at: Vector3, size: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	# The completion shell blocks views, while the original window frames and
	# walls cast the sunlight shadows. Otherwise this outer shell seals out light.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at
	room_frame.add_child(node)

func close_open_edges() -> void:
	# A closed, textured shell sits just beyond the original walls. This seals the
	# model's cut-away back and floor edges without covering its authored details.
	var plaster := enclosure_material(Rect2(0.455, 0.475, 0.38, 0.24))
	var floor_material := enclosure_material(Rect2(0.705, 0.205, 0.27, 0.23))
	panel("ClosedBackWall", Vector3(0.4, 2.5, 8.65), Vector3(12, 5.2, 0.2), plaster)
	panel("ClosedFrontWall", Vector3(0.4, 2.5, -6.05), Vector3(12, 5.2, 0.2), plaster)
	panel("ClosedLeftWall", Vector3(-5.55, 2.5, 1.3), Vector3(0.2, 5.2, 14.8), plaster)
	var overcast := StandardMaterial3D.new()
	overcast.albedo_color = Color("9da99b")
	overcast.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overcast.emission_enabled = true
	overcast.emission = Color("b4b6a5")
	overcast.emission_energy_multiplier = 1.0
	panel("ClosedRightWall", Vector3(6.35, 2.5, 1.3), Vector3(0.2, 5.2, 14.8), overcast)
	panel("ClosedFloor", Vector3(0.4, 0.08, 1.3), Vector3(12, 0.1, 14.8), floor_material)
	panel("ClosedCeiling", Vector3(0.4, 4.85, 1.3), Vector3(12, 0.1, 14.8), plaster)

func add_sunlight() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "WindowSunlight"
	sun.rotation_degrees = Vector3(-32, 95, 0)
	sun.light_color = Color("fff0cf")
	sun.light_energy = 0.75
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	# Gentle fill keeps blank cards and the opponent readable in the shadowed room.
	var fill := OmniLight3D.new()
	fill.name = "TableFill"
	fill.position = Vector3(0, 4.5, 1)
	fill.light_color = Color("b4c6c2")
	fill.light_energy = 0.45
	fill.omni_range = 12
	add_child(fill)

func source_point_to_world(point: Vector3) -> Vector3:
	return room_frame.to_global(point)

func camera_inside(world_point: Vector3) -> bool:
	var point := room_frame.to_local(world_point)
	return point.x > -5.35 and point.x < 6.15 and point.z > -5.85 and point.z < 8.45 and point.y > 0.2 and point.y < 4.7
