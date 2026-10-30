extends Node3D
## Supplied classroom with only the marked rear play area cleared and adapted.
const ROOM = preload("res://assets/supplied_classroom/classroom_play_area.glb")
const ROOM_SCALE := 4.5
const ROOM_YAW := 90.0
# FBX Blender coordinates (x, y, z) become Godot (x, z, -y).
# Centre of the dedicated table in the user's marked rear area.
const DESK_CENTER := Vector3(.1, .7897859, -3.0)
const TABLE_SCALE := 0.94
const TABLE_WIDTH_SCALE := 1.16
const TABLE_SIZE := Vector3(5.1 * TABLE_SCALE * TABLE_WIDTH_SCALE, .16, 7.2 * TABLE_SCALE)
var room_frame: Node3D

func _ready() -> void:
	name = "SchoolEnvironment"
	room_frame = Node3D.new()
	room_frame.name = "SuppliedClassroom"
	room_frame.scale = Vector3.ONE * ROOM_SCALE
	room_frame.rotation_degrees.y = ROOM_YAW
	room_frame.position = Vector3(0, 1, 0) - room_frame.basis * DESK_CENTER
	add_child(room_frame)
	var source: Node3D = ROOM.instantiate()
	source.name = "OriginalRoom"
	room_frame.add_child(source)
	var table: Node3D = source.find_child("GameTable", true, false)
	if table:
		table.global_transform = Transform3D(Basis.from_scale(Vector3(TABLE_SCALE * TABLE_WIDTH_SCALE, 1, TABLE_SCALE)), Vector3.ZERO) * table.global_transform
	# Imported desk/chair instances share materials. Adapt each unique material
	# once instead of allocating a copy for every mesh surface.
	var material_cache: Dictionary = {}
	for mesh in source.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var imported: Material = mesh.get_active_material(surface)
			if not imported is StandardMaterial3D: continue
			if material_cache.has(imported):
				mesh.set_surface_override_material(surface, material_cache[imported])
				if imported.resource_name in ["godray", "glass"]:
					mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				continue
			if imported.resource_name == "godray":
				var beam := ShaderMaterial.new()
				beam.shader = preload("res://assets/supplied_classroom/godray.gdshader")
				beam.set_shader_parameter("beam_texture", imported.albedo_texture)
				material_cache[imported] = beam
				mesh.set_surface_override_material(surface, beam)
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				continue
			var material: StandardMaterial3D = imported.duplicate()
			material_cache[imported] = material
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if imported.resource_name == "glass":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.set_surface_override_material(surface, material)
	# The annotation's white/player side is left in the room view; black/janitor
	# is right. Game +Z/-Z still drive the existing hand and threat/response rows.
	var player := Marker3D.new()
	player.name = "PlayerPosition"
	player.position = Vector3(0, -DESK_CENTER.y * ROOM_SCALE + 1, 4.35)
	player.set_meta("role", "Player / white mark / left in the reference")
	add_child(player)
	var anchor := Marker3D.new()
	anchor.name = "OpponentPosition"
	anchor.position = Vector3(0, -DESK_CENTER.y * ROOM_SCALE + 1, -4.35)
	anchor.rotation_degrees.y = 180
	anchor.set_meta("role", "Janitor / black mark / right in the reference")
	add_child(anchor)
	add_night_exterior()
	add_lighting()

func add_night_exterior() -> void:
	# Exterior darkness behind the transparent windows. It neither covers nor
	# changes the authored interior and does not block the directional moonlight.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.05, 9, 20)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("10151d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var night := MeshInstance3D.new()
	night.name = "NightOutsideWindows"
	night.mesh = mesh
	night.position = Vector3(4.15, 3, 0)
	night.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room_frame.add_child(night)

func add_lighting() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "WindowMoonlight"
	# Windows remain on the authored +X wall; light enters through their frames.
	moon.rotation_degrees = Vector3(-27, 90 + ROOM_YAW, 0)
	moon.light_color = Color("c3cbda")
	moon.light_energy = .45
	moon.shadow_enabled = true
	moon.light_angular_distance = .8
	moon.directional_shadow_max_distance = 70
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_blend_splits = true
	add_child(moon)
	var fill := OmniLight3D.new()
	fill.name = "BoardReadabilityFill"
	fill.position = Vector3(0, 4.4, .7)
	fill.light_color = Color("d5d1ba")
	fill.light_energy = .3
	fill.omni_range = 8
	add_child(fill)

func source_point_to_world(point: Vector3) -> Vector3:
	return room_frame.to_global(point)

func camera_inside(world_point: Vector3) -> bool:
	var point := room_frame.to_local(world_point)
	return absf(point.x) < 3.94 and absf(point.z) < 4.94 and point.y > .05 and point.y < 3.35
