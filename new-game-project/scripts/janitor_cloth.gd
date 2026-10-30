extends SkeletonModifier3D
## Runtime cloth proxy: fixed-step Verlet particles with stretch, shear and bend constraints.
## Physics drives cloth skin bones after animation; it is not a keyed robe animation.
const DATA_PATH := "res://assets/characters/janitor/cloth_proxy.json"
const STEP := 1.0 / 120.0
const DAMPING := 6.0
const ITERATIONS := 7
const MAX_OFFSET := 0.09
var rest := PackedVector3Array()
var points := PackedVector3Array()
var previous := PackedVector3Array()
var pins := PackedInt32Array()
var pairs: Array[Vector2i] = []
var lengths := PackedFloat32Array()
var bone_ids := PackedInt32Array()
var bases: Array[Basis] = []
var hips := -1
var hips_rest := Transform3D.IDENTITY
var running := false
var time := 0.0
var resets := 0

func setup() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var skeleton := get_skeleton()
	for value in data.points: rest.append(Vector3(value[0], value[1], value[2]))
	for value in data.pins: pins.append(int(value))
	for value in data.constraints:
		var pair := Vector2i(value[0], value[1])
		pairs.append(pair)
		lengths.append(rest[pair.x].distance_to(rest[pair.y]))
	for bone_name in data.bones:
		var index := skeleton.find_bone(bone_name)
		bone_ids.append(index)
		bases.append(skeleton.get_bone_global_rest(index).basis)
	hips = skeleton.find_bone("Hips")
	hips_rest = skeleton.get_bone_global_rest(hips)
	reset_simulation()

func reset_simulation() -> void:
	points = rest.duplicate()
	previous = rest.duplicate()
	time = 0.0
	resets += 1

func disturb() -> void:
	# Small hand/torso motion transferred to the hanging robe as an impulse.
	for i in points.size():
		if i not in pins: previous[i].z -= 0.006 * (1.0 - float(i / 8) / 5.0)

func _physics_process(delta: float) -> void:
	if not running or points.is_empty(): return
	# A long stall or resume never becomes a single oversized integration step.
	if delta > 0.1:
		reset_simulation()
		return
	var steps := clampi(roundi(delta / STEP), 1, 8)
	for substep in steps: simulate(delta / steps)

func simulate(delta: float) -> void:
	time += delta
	var skeleton := get_skeleton()
	var waist := skeleton.get_bone_global_pose(hips) * hips_rest.affine_inverse()
	for i in points.size():
		if i in pins:
			points[i] = waist * rest[i]
			previous[i] = points[i]
			continue
		var current := points[i]
		var velocity := (current - previous[i]) * exp(-DAMPING * delta)
		var force := Vector3(sin(time * 1.3) * 0.045, -3.7, cos(time * 1.7) * 0.035)
		points[i] += velocity + force * delta * delta
		previous[i] = current
	for iteration in ITERATIONS:
		for edge in pairs.size():
			var a := pairs[edge].x
			var b := pairs[edge].y
			var offset := points[b] - points[a]
			var distance := offset.length()
			if distance < 0.000001: continue
			var correction := offset * (1.0 - lengths[edge] / distance)
			var mass_a := 0.0 if a in pins else 1.0
			var mass_b := 0.0 if b in pins else 1.0
			if mass_a + mass_b == 0.0: continue
			points[a] += correction * mass_a / (mass_a + mass_b)
			points[b] -= correction * mass_b / (mass_a + mass_b)
		for i in points.size():
			if i in pins: continue
			collide(i)
			# A tether prevents the scanned folds from stretching away from their body.
			var offset := points[i] - rest[i]
			if not offset.is_finite():
				reset_simulation()
				return
			if offset.length() > MAX_OFFSET: points[i] = rest[i] + offset.limit_length(MAX_OFFSET)

func collide(index: int) -> void:
	# Conservative underlying body ellipsoid; no body exists inside the supplied robe mesh.
	var center := Vector3(0, 0.44, -0.06)
	var radii := Vector3(0.15, 0.47, 0.115)
	var relative := (points[index] - center) / radii
	if relative.length_squared() < 1.0 and relative.length_squared() > 0.000001:
		points[index] = center + relative.normalized() * radii
	points[index].y = maxf(0.018, points[index].y)

func _process_modification_with_delta(_delta: float) -> void:
	if points.is_empty(): return
	var skeleton := get_skeleton()
	for i in bone_ids.size():
		skeleton.set_bone_global_pose(bone_ids[i], Transform3D(bases[i], points[i]))
