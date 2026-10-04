extends Node3D

@onready var camera: Camera3D = $Camera3D

func _unhandled_input(event: InputEvent) -> void:
	# The camera is now completely fixed as requested.
	# We still allow left click for raycasting (if needed by the scene), 
	# but card.gd primarily handles its own dragging via Area3D's _input_event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_raycast_mouse(event.position)

func _raycast_mouse(mouse_pos: Vector2) -> void:
	if not camera: return
	
	var space_state = camera.get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider.get_parent() is MeshInstance3D and "Slot" in collider.get_parent().name:
			print("Clicked on 3D Slot: ", collider.get_parent().name)
