extends SceneTree
const VFX := preload("res://scripts/battle_vfx.gd")
var failures := 0

class MockGame extends Node3D:
	var effects_enabled := true
	func is_battle_active() -> bool:
		return true

class MockCard extends Node3D:
	var card_data := {"element": "fire", "health": 4}
	var statuses: Dictionary = {}
	var in_hand := false
	var preview_only := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	var game := MockGame.new()
	root.add_child(game)
	var vfx := VFX.new()
	game.add_child(vfx)
	vfx.setup(game)
	var card := MockCard.new()
	game.add_child(card)
	card.position = Vector3(1, 0, 1)
	for element in ["fire", "flood", "typhoon", "earthquake", "evac", "douse", "clearance", "brace"]:
		vfx.impact(element, Vector3.ZERO)
	check(vfx._bursts.size() == 8, "every attack affinity produces a burst")
	var first: GPUParticles3D = vfx._bursts[0]
	check(first.one_shot and not first.local_coords, "bursts are one shot in world space")
	check(first.amount <= 14 and first.visibility_aabb.size.length() > 0.0, "bursts have bounded budgets and AABB")
	var draw := first.draw_pass_1.material as StandardMaterial3D
	check(draw.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "pixel textures use nearest filtering")
	check(draw.albedo_texture == VFX.TEXTURES.flame, "fire uses the original pixel flame resource")
	check(first.draw_pass_1.size.x <= 0.08, "pixel bursts remain small enough for scaled board cards")
	var material := first.process_material as ParticleProcessMaterial
	check(material.color_ramp.gradient.get_color(2).a == 0.0, "particles fade alpha at end of life")
	first.finished.emit()
	check(vfx._bursts.size() == 7 and first.is_queued_for_deletion(), "finished retires disposable bursts")
	vfx.clear()
	card.statuses = {"burn": 2, "poison": 1, "barrier": 1}
	vfx.sync_status(card)
	var id := card.get_instance_id()
	check(vfx._cards[id].loops.size() == 2, "only burn and poison have persistent loops")
	var burn: GPUParticles3D = vfx._cards[id].loops.burn
	var burn_material := burn.process_material as ParticleProcessMaterial
	check(burn_material.initial_velocity_max <= 0.08
		and burn_material.emission_box_extents.x <= 0.05, "status loops stay along the card art edges")
	var burn_ramp := burn_material.color_ramp as GradientTexture1D
	check(burn_ramp.gradient.get_color(0).a <= 0.6, "persistent status particles keep subdued alpha")
	check(vfx._bursts.size() == 3, "new statuses produce brief application bursts")
	vfx.sync_status(card)
	check(vfx._bursts.size() == 3, "unchanged stacks do not repeat application bursts")
	card.statuses.burn = 100
	vfx.sync_status(card)
	check(vfx._cards[id].loops.burn.amount == 10, "large stack counts cannot grow particle budgets unbounded")
	check(vfx._cards[id].loops.size() == 2, "stack increases reuse existing persistent emitters")
	vfx.status_tick(card, "poison")
	check(vfx._bursts.size() == 5, "status ticks produce one brief burst")
	card.statuses.erase("poison")
	vfx.sync_status(card, false)
	check(not vfx._cards[id].loops.has("poison"), "removing poison stops its loop")
	card.statuses.clear()
	vfx.sync_status(card, false)
	check(vfx._cards.is_empty(), "expired statuses discard the card record")
	card.statuses.burn = 1
	vfx.sync_status(card, false)
	card.in_hand = true
	vfx._process(0.2)
	check(vfx._cards.is_empty(), "cards returned to hand lose their emitters")
	card.in_hand = false
	vfx.sync_status(card, false)
	game.effects_enabled = false
	vfx._process(0.2)
	check(vfx._cards.is_empty() and vfx._bursts.is_empty(), "disabling effects immediately clears all emitters")
	vfx.impact("fire", Vector3.ZERO)
	check(vfx._bursts.is_empty(), "disabled effects reject new bursts")
	game.effects_enabled = true
	vfx.sync_status(card, false)
	card.queue_free()
	await process_frame
	vfx._process(0.2)
	check(vfx._cards.is_empty(), "freed cards leave no persistent records")
	for index in 40: vfx.impact("fire", Vector3.ZERO)
	check(vfx._bursts.size() == VFX.MAX_BURSTS, "simultaneous bursts have a fixed upper limit")
	vfx.clear()
	await process_frame
	check(vfx.get_child_count() == 0, "battle cleanup frees all owned particle nodes")
	game.queue_free()
	await process_frame
	print("BATTLE VFX SMOKE: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
