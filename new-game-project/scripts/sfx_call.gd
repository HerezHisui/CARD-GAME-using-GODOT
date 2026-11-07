extends RefCounted
# Safe way to call the Sfx autoload. A script that preloads this compiles even when the
# autoload is not in the tree yet (some tests load game scripts very early). No node means no sound.

static func _node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("Sfx")

static func play(sound_name: String, volume_db: float = 0.0) -> void:
	var sfx := _node()
	if sfx: sfx.play(sound_name, volume_db)

static func play_element(element: String) -> void:
	var sfx := _node()
	if sfx: sfx.play_element(element)

static func encounter_music(kind: String, floor_level: int) -> void:
	var sfx := _node()
	if sfx: sfx.encounter_music(kind, floor_level)

static func map_screen(in_battle: bool) -> void:
	var sfx := _node()
	if sfx: sfx.map_screen(in_battle)

static func warden_enter() -> void:
	var sfx := _node()
	if sfx: sfx.warden_enter()

static func warden_prepare(boss: Variant) -> void:
	var sfx := _node()
	if sfx: sfx.warden_prepare(boss)

static func warden_intent(boss: Variant) -> void:
	var sfx := _node()
	if sfx: sfx.warden_intent(boss)
