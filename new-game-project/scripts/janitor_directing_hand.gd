extends SkeletonModifier3D
## Small destination-facing adjustment layered after the authored directing gesture.
var character: Node3D

func _process_modification() -> void:
	if not is_instance_valid(character) or character.action_kind != "card": return
	if character.played_target == Vector3.ZERO: return
	var skeleton := get_skeleton()
	var arm := skeleton.find_bone("Arm_L")
	var pose := skeleton.get_bone_global_pose(arm)
	var target := skeleton.to_local(character.played_target)
	var direction := target - pose.origin
	var progress := clampf(character.action_time / character.RELEASE_SECONDS, 0, 1)
	var fade := 1.0 - smoothstep(.72, 1.2, character.action_time)
	var angle := clampf(atan2(direction.x, direction.z), -.16, .16)
	pose.basis = Basis(Vector3.UP, angle * smoothstep(0, 1, progress) * fade) * pose.basis
	skeleton.set_bone_global_pose(arm, pose)
