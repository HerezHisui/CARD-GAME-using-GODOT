extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := load("res://assets/coin/midnight_coin.glb") as PackedScene
	check(scene != null, "the coin imports as a reusable scene")
	if scene == null:
		quit(1)
		return
	var coin := scene.instantiate() as Node3D
	root.add_child(coin)
	check(coin.transform.is_equal_approx(Transform3D.IDENTITY), "the toss pivot is centered")
	var meshes := coin.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() >= 40, "the model contains solid borders and separate relief geometry")
	var bounds := AABB()
	var first := true
	var heads := 0
	var tails := 0
	var edge_vertices := PackedVector3Array()
	for child in meshes:
		var instance := child as MeshInstance3D
		check(not instance.mesh is QuadMesh, "the coin uses real mesh relief")
		var box: AABB = instance.global_transform * instance.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if instance.name.begins_with("Heads"):
			heads += 1
			check(box.get_center().z > 0.0, "Heads relief faces positive Z")
		if instance.name.begins_with("Tails"):
			tails += 1
			check(box.get_center().z < 0.0, "Tails relief faces negative Z")
			var landed: Basis = Basis(Vector3.RIGHT, PI) * instance.basis
			check(landed.is_equal_approx(Basis.IDENTITY), "Tails reads upright at the final toss rotation")
		if instance.name.begins_with("Octagonal"):
			edge_vertices = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for surface in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			check(material != null and material.metallic >= 0.5, "gold materials are embedded and metallic")
	check(heads >= 20 and tails >= 15, "both sides contain their own border and symbols")
	check(bounds.get_center().length() < 0.01, "model bounds are centered on the pivot")
	check(bounds.size.x > 1.99 and bounds.size.y > 1.99, "the octagonal coin spans two units")
	check(bounds.size.z >= 0.35 and bounds.size.z < 0.5, "the body and relief have real thickness")
	# The widest body ring must have exactly eight corners, with full-length flat sides.
	var corners: Array[Vector2] = []
	for vertex in edge_vertices:
		if absf(vertex.z - 0.075) > 0.0001:
			continue
		var point := Vector2(vertex.x, vertex.y)
		if point.length() > 1.08 and not corners.any(func(p: Vector2): return p.distance_to(point) < 0.001):
			corners.append(point)
	check(corners.size() == 8, "the body is genuinely octagonal")
	coin.free()
	var presentation := load("res://scripts/game_presentation.gd").new() as CanvasLayer
	root.add_child(presentation)
	var coin_view: SubViewportContainer = presentation.make_coin_view()
	root.add_child(coin_view)
	check(presentation.coin_pivot.find_children("*", "MeshInstance3D", true, false).size() == meshes.size(),
		"the live presentation instantiates the imported GLB")
	var viewport := coin_view.get_child(0) as SubViewport
	check(viewport.own_world_3d and viewport.transparent_bg, "the coin keeps its isolated transparent viewport")
	check(viewport.find_children("*", "WorldEnvironment", true, false).size() == 1,
		"the metal has local ambient lighting")
	coin_view.free()
	presentation.free()
	print("Coin geometry smoke: %d failures" % failures)
	quit(1 if failures else 0)
