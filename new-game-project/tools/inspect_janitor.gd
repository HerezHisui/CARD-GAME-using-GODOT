extends SceneTree
## Read-only inspection of the supplied GLB. Optional rendered turntable captures go to TEMP.
var model: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var source := "C:/Users/0stef/Downloads/meshy-model-2026-10-30T09-10-58-481Z.glb"
	assert(document.append_from_file(source, state) == OK)
	model = document.generate_scene(state)
	root.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", node.name, " bounds=", node.get_aabb(), " transform=", node.global_transform)
	for path in ["midnight-drrills-logo.png", "catacomb-coders-mark.png"]:
		var logo := Image.new()
		var bytes := FileAccess.get_file_as_bytes("C:/Users/0stef/Downloads/" + path)
		if bytes.slice(0, 4).get_string_from_ascii() == "RIFF": logo.load_webp_from_buffer(bytes)
		elif bytes[0] == 255: logo.load_jpg_from_buffer(bytes)
		else: logo.load_png_from_buffer(bytes)
		print("LOGO ", path, " size=", logo.get_size(), " alpha=", logo.detect_alpha(),
			" corner=", logo.get_pixel(0, 0))
	if DisplayServer.get_name() == "headless":
		quit()
		return
	root.size = Vector2i(1000, 1000)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-30, -30, 0)
	light.light_energy = 1.8
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.18, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	root.add_child(environment)
	var output := OS.get_environment("TEMP").path_join("midnight-janitor-inspect")
	DirAccess.make_dir_recursive_absolute(output)
	for angle in [0, 90, 180, 270]:
		camera.position = Vector3(sin(deg_to_rad(angle)) * 4, 0, cos(deg_to_rad(angle)) * 4)
		camera.look_at(Vector3.ZERO)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("model_%d.png" % angle))
	quit()
