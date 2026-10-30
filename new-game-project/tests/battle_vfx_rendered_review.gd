extends SceneTree
## Targeted particle capture. Run with a rendered backend to check GPU emission and lifetime.
const VFX := preload("res://scripts/battle_vfx.gd")
const OUTPUT := "res://tests/artifacts/improvements/"
class MockGame extends Node3D:
	var effects_enabled := true
	func is_battle_active() -> bool:
		return true
class MockCard extends Node3D:
	var card_data := {"element": "fire", "health": 4}
	var statuses := {"burn": 2, "poison": 2}
	var in_hand := false
	var preview_only := false

func _initialize() -> void:
	call_deferred("run")

func plate(parent: Node3D, location: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	plane.material = material
	mesh.mesh = plane
	parent.add_child(mesh)
	mesh.position = location

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Particle visual review requires a rendered backend")
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var game := MockGame.new()
	root.add_child(game)
	current_scene = game
	plate(game, Vector3(0, -0.02, 0), Vector2(7, 4), Color("171b23"))
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.position = Vector3(0, 6, 2)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	var vfx := VFX.new()
	game.add_child(vfx)
	vfx.setup(game)
	var positions: Array[Vector3] = []
	var profiles := ["fire", "flood", "typhoon", "earthquake", "evac", "douse", "clearance", "brace"]
	for index in profiles.size():
		var row := floori(float(index) / 4.0)
		var point := Vector3((index % 4 - 1.5) * 1.2, 0, (row - 0.5) * 1.55)
		positions.append(point)
		plate(game, point, Vector2(0.77, 1.05), Color("48434b"))
		plate(game, point + Vector3(0, 0.004, 0.12), Vector2(0.7, 0.52), Color("10121a"))
		var label := Label3D.new()
		game.add_child(label)
		label.text = profiles[index].to_upper() + "  2 / 4"
		label.font_size = 24
		label.pixel_size = 0.0015
		label.position = point + Vector3(0, 0.015, -0.4)
		label.rotation_degrees.x = -90
		vfx.impact(profiles[index], point)
	# Warm shaders before timing a sub-second effect.
	await create_timer(1.2).timeout
	vfx.clear()
	await process_frame
	for index in profiles.size(): vfx.impact(profiles[index], positions[index])
	for frame in 5: await process_frame
	await capture("particle_profiles_review")
	await create_timer(1.0).timeout
	var retired := vfx._bursts.is_empty()
	print("RENDERED BURSTS RETIRED: ", retired)
	var card := MockCard.new()
	game.add_child(card)
	card.position = positions[0]
	vfx.sync_status(card, false)
	await create_timer(1.0).timeout
	await capture("particle_status_edges_review")
	game.queue_free()
	await process_frame
	quit(0 if retired else 1)
