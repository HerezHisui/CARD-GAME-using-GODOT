extends Node3D
## Presentation only. Particle amounts are bounded independently of damage and status stacks.
const BURST := preload("res://scenes/vfx/pixel_burst.tscn")
const TEXTURES := {
	"flame": preload("res://assets/vfx/pixel_flame.svg"),
	"drop": preload("res://assets/vfx/pixel_drop.svg"),
	"shard": preload("res://assets/vfx/pixel_shard.svg"),
	"wind": preload("res://assets/vfx/pixel_wind.svg"),
	"spark": preload("res://assets/vfx/pixel_spark.svg"),
	"arrow": preload("res://assets/vfx/pixel_arrow.svg"),
	"shield": preload("res://assets/vfx/pixel_shield.svg"),
}
const PROFILES := {
	"fire": ["flame", Color("ff9b42"), 0.85],
	"flood": ["drop", Color("63d9ff"), 0.95],
	"typhoon": ["wind", Color("c4a4ff"), 1.35],
	"earthquake": ["shard", Color("d6ac7b"), 0.65],
	"evac": ["arrow", Color("b7ed80"), 1.25],
	"douse": ["drop", Color("88e5ee"), 0.9],
	"clearance": ["shard", Color("ffc36d"), 1.05],
	"brace": ["shield", Color("c6d9ed"), 0.45],
	"burn": ["flame", Color("ff8b3d"), 0.55],
	"poison": ["drop", Color("9ee86d"), 0.35],
	"bleed": ["drop", Color("f26883"), 0.5],
	"healing_reduced": ["spark", Color("d193d1"), 0.3],
	"strength": ["arrow", Color("ffca70"), 0.55],
	"barrier": ["shield", Color("8bdcf4"), 0.3],
}
const MAX_BURSTS := 24
const MAX_STATUS_CARDS := 12
var game: Node
var _bursts: Array[GPUParticles3D] = []
var _cards: Dictionary = {}
var _cleanup_elapsed := 0.0

func setup(owner_game: Node) -> void:
	game = owner_game
	name = "BattleVFX"

func attack_start(attacker: Node3D, target_position: Vector3) -> void:
	if not _enabled() or not _card_active(attacker): return
	var element := str(attacker.get("card_data").get("element", ""))
	var particles := _burst(element, attacker.global_position + Vector3.UP * 0.12, 8)
	if particles:
		var material := particles.process_material as ParticleProcessMaterial
		material.direction = (target_position - attacker.global_position).normalized() + Vector3.UP * 0.5
		material.spread = 24.0

func impact(element: String, at_position: Vector3) -> void:
	_burst(element, at_position + Vector3.UP * 0.12, 14)

func sync_status(card: Node3D, application := true) -> void:
	if not is_instance_valid(card): return
	if not _enabled() or not _card_active(card):
		clear_card(card)
		return
	var id := card.get_instance_id()
	if not _cards.has(id):
		if _cards.size() >= MAX_STATUS_CARDS: return
		_cards[id] = {"card": weakref(card), "stacks": {}, "loops": {}}
	var record: Dictionary = _cards[id]
	var statuses: Dictionary = card.get("statuses")
	for status in PROFILES:
		if not status in ["burn", "poison", "bleed", "healing_reduced", "strength", "barrier"]: continue
		var stacks := maxi(0, int(statuses.get(status, 0)))
		if application and stacks > int(record.stacks.get(status, 0)):
			_status_burst(card, status, 8)
		if status in ["burn", "poison"]:
			_sync_loop(card, record.loops, status, stacks)
		if stacks > 0: record.stacks[status] = stacks
		else: record.stacks.erase(status)
	if record.stacks.is_empty():
		_clear_record(id)

func status_tick(card: Node3D, status: String) -> void:
	if not _card_active(card) or not PROFILES.has(status): return
	_status_burst(card, status, 10)

func _status_burst(card: Node3D, status: String, count: int) -> void:
	var particles := _burst(status, card.global_position + Vector3(0, 0.07, 0.12), count)
	if particles:
		var material := particles.process_material as ParticleProcessMaterial
		material.initial_velocity_min = 0.04
		material.initial_velocity_max = 0.12
		material.gravity = Vector3.ZERO

func clear_card(card: Node3D) -> void:
	if is_instance_valid(card): _clear_record(card.get_instance_id())

func clear() -> void:
	for id in _cards.keys(): _clear_record(id)
	for particles in _bursts:
		if is_instance_valid(particles):
			particles.emitting = false
			particles.queue_free()
	_bursts.clear()

func _process(delta: float) -> void:
	if not _enabled():
		if not _cards.is_empty() or not _bursts.is_empty(): clear()
		return
	_cleanup_elapsed += delta
	var cleanup := _cleanup_elapsed >= 0.15
	if cleanup: _cleanup_elapsed = 0.0
	for id in _cards.keys():
		var record: Dictionary = _cards[id]
		var card: Node3D = record.card.get_ref()
		if cleanup:
			if not _card_active(card):
				_clear_record(id)
				continue
			# Covers direct cleanse/stack edits outside the normal status helpers.
			sync_status(card, false)
		if not is_instance_valid(card) or not _cards.has(id): continue
		for status in record.loops:
			var particles: GPUParticles3D = record.loops[status]
			particles.global_position = card.global_position + _loop_offset(str(status))

func _enabled() -> bool:
	return is_instance_valid(game) and bool(game.get("effects_enabled")) and game.is_battle_active()

func _card_active(card: Node3D) -> bool:
	if not is_instance_valid(card) or card.is_queued_for_deletion() or not card.is_inside_tree(): return false
	if bool(card.get("in_hand")) or bool(card.get("preview_only")): return false
	var data: Dictionary = card.get("card_data")
	return int(data.get("health", 0)) > 0 and not bool(data.get("utility", false))

func _burst(profile: String, at_position: Vector3, count: int) -> GPUParticles3D:
	if not _enabled() or not PROFILES.has(profile): return null
	if _bursts.size() >= MAX_BURSTS: return null
	var particles := _make_particles(profile)
	particles.amount = count
	add_child(particles)
	particles.global_position = at_position
	_bursts.append(particles)
	particles.finished.connect(_finish_burst.bind(particles), CONNECT_ONE_SHOT)
	particles.emitting = true
	particles.restart()
	return particles

func _finish_burst(particles: GPUParticles3D) -> void:
	_bursts.erase(particles)
	if is_instance_valid(particles): particles.queue_free()

func _make_particles(profile: String) -> GPUParticles3D:
	var particles := BURST.instantiate() as GPUParticles3D
	var settings: Array = PROFILES[profile]
	var material := particles.process_material.duplicate() as ParticleProcessMaterial
	particles.process_material = material
	material.initial_velocity_min = float(settings[2]) * 0.55
	material.initial_velocity_max = float(settings[2])
	var gradient := Gradient.new()
	var color: Color = settings[1]
	gradient.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	gradient.colors = PackedColorArray([color.lightened(0.25), color, Color(color, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	material.color_ramp = ramp
	var mesh := particles.draw_pass_1.duplicate() as QuadMesh
	var draw := mesh.material.duplicate() as StandardMaterial3D
	draw.albedo_texture = TEXTURES[settings[0]]
	mesh.material = draw
	particles.draw_pass_1 = mesh
	return particles

func _sync_loop(card: Node3D, loops: Dictionary, status: String, stacks: int) -> void:
	if stacks <= 0:
		if loops.has(status):
			var previous: GPUParticles3D = loops[status]
			previous.emitting = false
			previous.queue_free()
			loops.erase(status)
		return
	if not loops.has(status):
		var particles := _make_particles(status)
		particles.one_shot = false
		particles.explosiveness = 0.0
		particles.lifetime = 0.55
		particles.local_coords = true
		var material := particles.process_material as ParticleProcessMaterial
		material.emission_box_extents = Vector3(0.025, 0.005, 0.1)
		material.initial_velocity_min = 0.02
		material.initial_velocity_max = 0.05
		material.gravity = Vector3(0, 0.02, 0)
		material.spread = 12.0
		material.scale_min = 0.5
		material.scale_max = 0.8
		var ramp := material.color_ramp as GradientTexture1D
		var gradient: Gradient = ramp.gradient
		for index in gradient.get_point_count():
			var color: Color = gradient.get_color(index)
			color.a *= 0.55
			gradient.set_color(index, color)
		add_child(particles)
		particles.global_position = card.global_position + _loop_offset(status)
		loops[status] = particles
		particles.amount = 4 + mini(stacks, 3) * 2
		particles.restart()
	else:
		var particles: GPUParticles3D = loops[status]
		var count := 4 + mini(stacks, 3) * 2
		if particles.amount != count: particles.amount = count

func _loop_offset(status: String) -> Vector3:
	return Vector3(-0.24 if status == "burn" else 0.24, 0.07, 0.12)

func _clear_record(id: int) -> void:
	if not _cards.has(id): return
	for particles in _cards[id].loops.values():
		if is_instance_valid(particles):
			particles.emitting = false
			particles.queue_free()
	_cards.erase(id)

func _exit_tree() -> void:
	clear()
