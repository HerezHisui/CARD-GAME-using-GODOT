extends Node3D
## Thin cloth mat with printed zones; the existing slot colliders remain authoritative.
const WIDTH := 6.2
const DEPTH := 4.2
const PPU := 160

func rounded_surface(y: float, width: float, depth: float, radius: float) -> ArrayMesh:
	var outline: Array[Vector3] = []
	for corner in range(4):
		var center := Vector2((width / 2 - radius) * (1 if corner < 2 else -1), (depth / 2 - radius) * (1 if corner in [0, 3] else -1))
		for step in range(9):
			var angle := deg_to_rad(corner * 90.0 + step * 90.0 / 8.0)
			outline.append(Vector3(center.x + sin(angle) * radius, y, center.y + cos(angle) * radius))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size()):
		for point in [Vector3(0, y, 0), outline[(i + 1) % outline.size()], outline[i]]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(point.x / width + 0.5, point.z / depth + 0.5))
			surface.add_vertex(point)
	return surface.commit()

func line(img: Image, a: Vector2i, size: Vector2i, color: Color) -> void:
	img.fill_rect(Rect2i(a, size), color)

func _ready() -> void:
	name = "Playmat"
	var width := int(WIDTH * PPU)
	var height := int(DEPTH * PPU)
	var img := Image.create(width, height, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 192
	for y in range(height):
		for x in range(width):
			var weave := (0.013 if (x + y) % 3 == 0 else -0.006) + rng.randf_range(-0.008, 0.008)
			var shade := 0.025 * sin(float(x) / width * PI)
			img.set_pixel(x, y, Color(0.105 + weave + shade, 0.23 + weave + shade, 0.215 + weave + shade))
	var ink := Color("b6bd9e")
	var stitch := Color("c5b991")
	# Short stitches around the perimeter read as sewn fabric rather than metal.
	for x in range(24, width - 24, 10):
		for y in [14, height - 15]: line(img, Vector2i(x, y), Vector2i(5, 1), stitch)
	for y in range(24, height - 24, 10):
		for x in [14, width - 15]: line(img, Vector2i(x, y), Vector2i(1, 5), stitch)
	for slot in get_parent().get_node("Slots").get_children():
		if not slot is MeshInstance3D: continue
		slot.visible = false
		var cx := int((slot.position.x + WIDTH / 2) * PPU)
		var cy := int((slot.position.z + DEPTH / 2) * PPU)
		var sx := int(1.1 * PPU / 2)
		var sy := int(1.5 * PPU / 2)
		# Flat screen-printed registration corners, with no recessed wells.
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				var corner := Vector2i(cx + dx * sx, cy + dy * sy)
				line(img, corner + Vector2i(-24 if dx == 1 else 0, 0), Vector2i(30, 4), ink)
				line(img, corner + Vector2i(0, -24 if dy == 1 else 0), Vector2i(4, 30), ink)
	for x in range(45, width - 45, 16):
		if abs(x - width / 2) > 45: line(img, Vector2i(x, height / 2), Vector2i(7, 1), ink)
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var top := MeshInstance3D.new()
	top.mesh = rounded_surface(1.008, WIDTH, DEPTH, 0.12)
	top.material_override = mat
	add_child(top)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("202e2b")
	rubber.roughness = 1
	rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
	for layer in range(4):
		var edge := MeshInstance3D.new()
		edge.mesh = rounded_surface(1.001 + layer * 0.0015, WIDTH + 0.018, DEPTH + 0.018, 0.12)
		edge.material_override = rubber
		add_child(edge)
	for row in [-1, 1]:
		var label := Label3D.new()
		label.text = "THREAT ZONE" if row == -1 else "RESPONSE ZONE"
		label.font_size = 32
		label.pixel_size = 0.003
		label.outline_size = 0
		label.modulate = ink
		label.position = Vector3(0, 1.012, row * 1.92)
		label.rotation_degrees.x = -90
		add_child(label)

static func oak_material() -> StandardMaterial3D:
	var image := Image.create(512, 256, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 34
	noise.frequency = 0.035
	for y in range(256):
		for x in range(512):
			var grain := noise.get_noise_2d(x * 0.12, y * 2.0)
			var fine := sin(y * 1.8 + grain * 5.0) * 0.025
			var value := clampf(0.48 + grain * 0.3 + fine, 0, 1)
			image.set_pixel(x, y, Color("8c603d").lerp(Color("c59a68"), value))
	image.generate_mipmaps()
	var result := StandardMaterial3D.new()
	result.albedo_texture = ImageTexture.create_from_image(image)
	result.roughness = 0.72
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return result
