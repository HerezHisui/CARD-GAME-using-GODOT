extends Node3D
## Static, compatibility-renderer classroom. Decorative meshes have no collision.
const WOOD := Color("503b30")
const BRASS := Color("b99760")
const TEAL := Color("294c4a")
var materials: Dictionary = {}
var meshes: Dictionary = {}

func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(glow)
	if materials.has(key): return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.78
	if color == BRASS:
		result.metallic = 0.65
		result.roughness = 0.32
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = result
	return result

func box(title: String, size: Vector3, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var key := str(size)
	if not meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		meshes[key] = mesh
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = meshes[key]
	node.material_override = material(color, glow)
	node.position = at
	add_child(node)
	return node

func cylinder(title: String, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	add_child(node)
	return node

func lettering(title: String, words: String, at: Vector3, scale_px: float, color: Color) -> void:
	var label := Label3D.new()
	label.name = title
	label.text = words
	label.position = at
	label.font_size = 48
	label.pixel_size = scale_px
	label.modulate = color
	label.outline_size = 0
	add_child(label)

func lamp(at: Vector3) -> void:
	cylinder("LampFoot", at, 0.24, 0.07, BRASS)
	cylinder("LampStem", at + Vector3(0, 0.34, 0), 0.035, 0.65, BRASS)
	box("GreenGlassShade", Vector3(0.7, 0.23, 0.38), at + Vector3(0, 0.69, 0), TEAL)
	box("WarmLampLens", Vector3(0.58, 0.025, 0.3), at + Vector3(0, 0.56, 0), Color("ffe0a0"), true)
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, 0.48, 0.1)
	light.light_color = Color("ffd397")
	light.light_energy = 1.4
	light.omni_range = 3.0
	add_child(light)

func window(at: Vector3) -> void:
	box("WindowRecess", Vector3(2.55, 3.45, 0.2), at, Color("192b39"))
	box("NightGlass", Vector3(2.3, 3.2, 0.06), at + Vector3(0, 0, 0.13), Color("e3ba87"), true)
	for x in [-1.25, 0.0, 1.25]:
		box("WindowMullion", Vector3(0.085, 3.5, 0.17), at + Vector3(x, 0, 0.2), WOOD)
	for y in [-1.7, 0, 1.7]:
		box("WindowRail", Vector3(2.6, 0.09, 0.17), at + Vector3(0, y, 0.2), WOOD)
	box("WindowSill", Vector3(2.9, 0.12, 0.5), at + Vector3(0, -1.78, 0.28), BRASS)
	# Layered silhouettes add depth behind the glazing.
	for i in range(7):
		var h := 0.25 + float((i * 7) % 5) * 0.13
		box("DistantRoof", Vector3(0.29, h, 0.02), at + Vector3(-0.95 + i * 0.31, -1.55 + h / 2, 0.17), Color("8c8170"), true)
	for side in [-1, 1]:
		for fold in range(4):
			box("CurtainFold", Vector3(0.13, 3.55, 0.13), at + Vector3(side * (1.39 + fold * 0.12), 0, 0.25 + (fold % 2) * 0.06), Color("d0ac87") if fold % 2 else Color("b98f6e"))

func desk(at: Vector3) -> void:
	box("DeskTop", Vector3(1.9, 0.14, 1.05), at + Vector3(0, 1.2, 0), Color("ad8056"))
	box("DeskApron", Vector3(1.7, 0.26, 0.85), at + Vector3(0, 1.02, 0), WOOD)
	for x in [-0.76, 0.76]:
		for z in [-0.36, 0.36]:
			box("DeskLeg", Vector3(0.075, 1.1, 0.075), at + Vector3(x, 0.5, z), Color("263436"))
	box("ChairSeat", Vector3(0.75, 0.12, 0.75), at + Vector3(0, 0.65, 1.0), WOOD)
	box("ChairBack", Vector3(0.75, 0.52, 0.1), at + Vector3(0, 1.06, 1.32), Color("79583e"))
	for x in [-0.29, 0.29]:
		for z in [0.73, 1.27]:
			box("ChairLeg", Vector3(0.05, 0.65, 0.05), at + Vector3(x, 0.27, z), Color("263436"))
	box("Notebook", Vector3(0.5, 0.06, 0.36), at + Vector3(-0.38, 1.31, 0), Color("c4b79b"))
	box("NotebookCover", Vector3(0.52, 0.015, 0.38), at + Vector3(-0.38, 1.35, 0), TEAL)

func _ready() -> void:
	name = "SchoolEnvironment"
	box("Foundation", Vector3(18, 0.16, 23), Vector3(0, -0.22, -1), WOOD)
	# Shared mesh instances keep the parquet inexpensive.
	var planks := MultiMeshInstance3D.new()
	planks.name = "OakParquet"
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var plank := BoxMesh.new()
	plank.size = Vector3(0.72, 0.025, 2.16)
	multi.mesh = plank
	multi.instance_count = 240
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	for i in range(240):
		var x := i % 24
		var z := i / 24
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-8.65 + x * 0.75, -0.12, -10.8 + z * 2.2)))
		multi.set_instance_color(i, Color("70563f").lerp(Color("3a302a"), rng.randf_range(0.0, 0.65)))
	planks.multimesh = multi
	var floor_mat := StandardMaterial3D.new()
	floor_mat.vertex_color_use_as_albedo = true
	floor_mat.roughness = 0.72
	planks.material_override = floor_mat
	add_child(planks)
	var ceiling := box("Ceiling", Vector3(18, 0.12, 23), Vector3(0, 6.85, -1), Color("dad4c1"))
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in [-10, -5, 0, 5]:
		box("CeilingBeam", Vector3(18, 0.22, 0.18), Vector3(0, 6.65, z), WOOD)
	box("BackPlaster", Vector3(18, 7, 0.25), Vector3(0, 3.3, -11), Color("d4c7af"))
	box("BackWainscot", Vector3(18, 1.8, 0.16), Vector3(0, 0.75, -10.8), TEAL)
	for y in [0.0, 1.65, 6.4]:
		box("BackMolding", Vector3(18, 0.12, 0.23), Vector3(0, y, -10.66), WOOD)
	for x in range(-8, 9):
		box("PanelBatten", Vector3(0.055, 1.5, 0.1), Vector3(x, 0.78, -10.65), Color("41605a"))
	for side in [-1, 1]:
		box("SidePlaster", Vector3(0.2, 7, 23), Vector3(side * 9, 3.3, -1), Color("cabc9f"))
		box("SidePaneling", Vector3(0.13, 1.8, 23), Vector3(side * 8.85, 0.75, -1), TEAL)
		for y in [0.0, 1.65, 6.4]:
			box("SideMolding", Vector3(0.2, 0.12, 23), Vector3(side * 8.75, y, -1), WOOD)
		for z in [-8, -4, 0, 4]:
			box("WallPilaster", Vector3(0.25, 6.5, 0.25), Vector3(side * 8.7, 3.15, z), WOOD)
	for z in [-7.2, -2.8, 1.6]:
		var first := get_child_count()
		window(Vector3.ZERO)
		var pivot := Node3D.new()
		pivot.name = "SideWindow"
		add_child(pivot)
		var pieces := get_children().slice(first, get_child_count() - 1)
		for piece in pieces: piece.reparent(pivot, false)
		pivot.position = Vector3(8.7, 3.8, z)
		pivot.rotation_degrees.y = -90
	window(Vector3(-6.3, 3.8, -10.65))
	window(Vector3(6.3, 3.8, -10.65))
	box("ChalkFrame", Vector3(7.1, 2.9, 0.19), Vector3(0, 3.55, -10.65), BRASS)
	box("Chalkboard", Vector3(6.85, 2.65, 0.13), Vector3(0, 3.55, -10.52), Color("193b35"))
	lettering("SchoolTitle", "MIDNIGHT DRRILLS", Vector3(0, 4.12, -10.43), 0.007, Color("e0d9bb"))
	lettering("Lesson", "PREPARE  /  PROTECT  /  SURVIVE\n\nTonight's lesson: stay together.", Vector3(0, 3.2, -10.43), 0.0038, Color("b0c5ac"))
	box("ChalkTray", Vector3(7, 0.07, 0.3), Vector3(0, 2.12, -10.3), WOOD)
	for i in range(3):
		box("Chalk", Vector3(0.13, 0.025, 0.025), Vector3(-2.2 + i * 0.2, 2.17, -10.22), Color("ddd8c3"))
	var clock_face := cylinder("ClockFace", Vector3(0, 5.65, -10.55), 0.47, 0.09, Color("d9cfb1"))
	clock_face.rotation_degrees.x = 90
	box("ClockMinute", Vector3(0.035, 0.32, 0.025), Vector3(0, 5.79, -10.48), WOOD)
	var hand := box("ClockHour", Vector3(0.035, 0.23, 0.025), Vector3(-0.07, 5.7, -10.46), WOOD)
	hand.rotation_degrees.z = 50
	for side in [-1, 1]:
		for z in [-6.9, -3.4, 0.2]:
			desk(Vector3(side * 6.2, 0, z))
		lamp(Vector3(side * 6.5, 1.33, -6.9))
		# Low bookcases frame the battle without blocking the board.
		box("BookcaseBack", Vector3(2.4, 1.9, 0.12), Vector3(side * 5.9, 0.85, -9.6), WOOD)
		for y in [0.0, 0.85, 1.75]:
			box("Bookshelf", Vector3(2.5, 0.09, 0.65), Vector3(side * 5.9, y, -9.35), Color("856345"))
		for i in range(10):
			var h := rng.randf_range(0.4, 0.7)
			box("BookSpine", Vector3(0.15, h, 0.36), Vector3(side * 5.9 - 1.0 + i * 0.21, 0.9 + h / 2, -9.27), [TEAL, Color("8a5546"), Color("b59c6c")][i % 3])
	# A thin school-club tabletop at y=1, with open space underneath.
	for x in [-3.55, 3.55]:
		for z in [-2.32, 2.32]:
			box("TableLeg", Vector3(0.16, 0.93, 0.16), Vector3(x, 0.355, z), Color("444947"))
			box("TableFoot", Vector3(0.19, 0.06, 0.19), Vector3(x, -0.08, z), Color("252c2c"))
		box("TableSideApron", Vector3(0.1, 0.22, 4.7), Vector3(x, 0.72, 0), WOOD)
	for z in [-2.32, 2.32]:
		box("TableEndApron", Vector3(7.2, 0.22, 0.1), Vector3(0, 0.72, z), WOOD)
	for x in [-4.1, 4.1]:
		box("SideConsole", Vector3(0.9, 1.0, 1.6), Vector3(x, 0.4, -1.4), WOOD)
		lamp(Vector3(x, 0.94, -1.7))
	for x in [-4.4, 4.4]:
		box("PendantHousing", Vector3(2.0, 0.18, 0.65), Vector3(x, 6.0, -5), Color("253b3d"))
		box("PendantDiffuser", Vector3(1.8, 0.025, 0.5), Vector3(x, 5.89, -5), Color("ffe0b0"), true)
		for offset in [-0.7, 0.7]:
			cylinder("PendantCable", Vector3(x + offset, 6.45, -5), 0.015, 0.8, WOOD)
		var light := OmniLight3D.new()
		light.position = Vector3(x, 5.6, -5)
		light.light_color = Color("ffe0b0")
		light.light_energy = 0.8
		light.omni_range = 8
		add_child(light)
