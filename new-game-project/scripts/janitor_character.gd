extends Node3D
## Presentation only. No card creation, resource spending, AI decisions or turn waits.
const MODEL = preload("res://assets/characters/janitor/janitor_rigged.glb")
const Cloth = preload("res://scripts/janitor_cloth.gd")
const DirectingHand = preload("res://scripts/janitor_directing_hand.gd")
const RELEASE_SECONDS := 0.52
var skeleton: Skeleton3D
var animation: AnimationPlayer
var cloth: SkeletonModifier3D
var holding: BoneAttachment3D
var playing: BoneAttachment3D
var hand_count := -1
var active_encounter := false
var action_time := -1.0
var action_kind := ""
var played_id := ""
var played_target := Vector3.ZERO
var released := false
var released_origin := Vector3.INF
var back_material: StandardMaterial3D

func _ready() -> void:
	var model := MODEL.instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	animation = model.find_child("AnimationPlayer", true, false)
	animation.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	holding = grip("Grip_R")
	playing = grip("Grip_R")
	playing.name = "FloatingSelectedCard"
	back_material = StandardMaterial3D.new()
	back_material.albedo_texture = preload("res://scripts/card_3d.gd")._card_back()
	back_material.roughness = 0.85
	# Both sides use only a back texture, including at extreme camera/hand angles.
	back_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var directing := DirectingHand.new()
	directing.character = self
	skeleton.add_child(directing)
	cloth = Cloth.new()
	skeleton.add_child(cloth)
	cloth.setup()
	animation.animation_finished.connect(animation_done)
	animation.play("idle")
	animation.advance(0)
	hide()

func grip(bone_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = bone_name
	skeleton.add_child(attachment)
	attachment.bone_name = bone_name
	return attachment

func set_encounter(enabled: bool) -> void:
	if active_encounter == enabled: return
	active_encounter = enabled
	visible = enabled
	cloth.running = enabled
	cancel_action()
	cloth.reset_simulation()

func set_hand_count(count: int) -> void:
	if hand_count == count: return
	hand_count = count
	clear_cards(holding)
	for i in count:
		var card := make_back()
		card.name = "HiddenCard%d" % i
		card.position = Vector3((i - (count - 1) * 0.5) * 0.045, .085, .015 + i * .003)
		card.rotation = Vector3(-0.2, 0, (i - (count - 1) * 0.5) * -0.09)
		holding.add_child(card)
	update_floating_cards()

func update_floating_cards() -> void:
	if not is_instance_valid(holding): return
	var time := float(Time.get_ticks_msec()) * .001
	for i in holding.get_child_count():
		var card := holding.get_child(i) as Node3D
		var spread := float(i) - float(holding.get_child_count() - 1) * .5
		var offset := Vector3(spread * .045, .24 + sin(time * 1.8 + i * .3) * .008, .035 + i * .003)
		card.global_transform = Transform3D(global_basis * Basis.from_euler(Vector3(-.12, 0, spread * -.09)),
			holding.global_position + global_basis * offset)
	if playing.get_child_count() == 0: return
	var selected := playing.get_child(0) as Node3D
	var start := holding.global_position + global_basis * Vector3(0, .25, .07)
	var progress := clampf(action_time / RELEASE_SECONDS, 0, 1)
	var direction := global_basis * Vector3(0, -.1, .45)
	if played_target != Vector3.ZERO:
		direction = (played_target - start).limit_length(global_basis.get_scale().x * .45)
	selected.global_transform = Transform3D(global_basis * Basis.from_euler(Vector3(-.12, 0, 0)),
		start + direction * smoothstep(0, 1, progress))

func make_back() -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.25)
	quad.material = back_material
	card.mesh = quad
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return card

func play_card(definition: Dictionary, target := Vector3.ZERO) -> void:
	if not active_encounter: return
	cancel_action()
	played_id = str(definition.get("id", ""))
	played_target = target
	action_time = 0.0
	action_kind = "card"
	var card := make_back()
	card.name = "SelectedBack"
	card.position = Vector3(0, .075, .02)
	playing.add_child(card)
	update_floating_cards()
	animation.play("card_play", 0.08)
	cloth.disturb()

func warden_pattern() -> void:
	if not active_encounter: return
	cancel_action()
	action_kind = "warden"
	action_time = 0.0
	animation.play("warden_pattern", 0.08)
	cloth.disturb()

func _process(delta: float) -> void:
	update_floating_cards()
	if action_time < 0.0: return
	action_time += delta
	# Release is timed to the forward gesture, never to a gameplay callback.
	if action_kind == "card" and action_time >= RELEASE_SECONDS and not released: release_card()

func release_card() -> void:
	if playing.get_child_count() > 0:
		released_origin = playing.get_child(0).global_position
	clear_cards(playing)
	released = true

func animation_done(clip: StringName) -> void:
	if clip == &"idle": return
	cancel_action()

func cancel_action() -> void:
	action_time = -1.0
	action_kind = ""
	played_id = ""
	released = false
	released_origin = Vector3.INF
	if is_instance_valid(playing): clear_cards(playing)
	if is_instance_valid(animation):
		animation.play("idle", 0.1)
		animation.advance(0)

func clear_cards(anchor: Node) -> void:
	for card in anchor.get_children():
		anchor.remove_child(card)
		card.queue_free()

func _exit_tree() -> void:
	if is_instance_valid(animation): animation.stop()
