extends SceneTree
## Re-encode the supplied lossless WebP files and remove only the game logo's flat matte.
func _initialize() -> void:
	var output := "res://assets/branding"
	DirAccess.make_dir_recursive_absolute(output)
	for filename in ["midnight-drrills-logo", "catacomb-coders-mark"]:
		var bytes := FileAccess.get_file_as_bytes("C:/Users/0stef/Downloads/" + filename + ".png")
		var source := FileAccess.open(output.path_join(filename + "-source.webp"), FileAccess.WRITE)
		source.store_buffer(bytes)
		source.close()
		var image := Image.new()
		assert(image.load_webp_from_buffer(bytes) == OK)
		image.convert(Image.FORMAT_RGBA8)
		if filename == "midnight-drrills-logo": remove_matte(image)
		assert(image.save_png(output.path_join(filename + ".png")) == OK)
	quit()

func remove_matte(image: Image) -> void:
	var matte := Vector3(image.get_pixel(0, 0).r, image.get_pixel(0, 0).g, image.get_pixel(0, 0).b)
	# Flat palette sampled from the supplied artwork, rather than redrawing its shapes.
	var palette := [Vector3(236, 231, 210) / 255.0, Vector3(255, 85, 20) / 255.0]
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var rgb := Vector3(pixel.r, pixel.g, pixel.b)
			if rgb.distance_to(matte) < 0.007:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var alpha := 1.0
			var error := INF
			for color in palette:
				var direction: Vector3 = color - matte
				var coverage := clampf((rgb - matte).dot(direction) / direction.length_squared(), 0.0, 1.0)
				var distance: float = rgb.distance_squared_to(matte + direction * coverage)
				if distance < error:
					error = distance
					alpha = coverage
			# Reverse matte blending at edge pixels, retaining their original coverage.
			if alpha > 0.0:
				var clean := ((rgb - matte * (1.0 - alpha)) / alpha).clamp(Vector3.ZERO, Vector3.ONE)
				image.set_pixel(x, y, Color(clean.x, clean.y, clean.z, alpha))
