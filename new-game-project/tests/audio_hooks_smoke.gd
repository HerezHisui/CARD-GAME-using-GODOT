extends SceneTree
# Checks the Sfx game helpers (music choice, elements, Warden) are safe and change nothing.
var failures := 0
var checks := 0
var sfx: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	sfx = root.get_node_or_null("Sfx")
	check(sfx != null, "Sfx autoload exists")
	if sfx == null:
		quit(1)
		return
	# Disabled: every helper is a no-op.
	sfx.audio_enabled_override = false
	sfx.encounter_music("battle", 1)
	sfx.encounter_music("boss", 3)
	sfx.map_screen(false)
	sfx.play_element("fire")
	sfx.warden_enter()
	sfx.warden_prepare(null)
	sfx.warden_intent(null)
	check(sfx.current_music() == "", "disabled: helpers start no music")
	check(not sfx.is_loop_playing("school_room_tone_loop"), "disabled: no room tone")
	# Enabled: odd input is safe. Music can only start when the files are imported.
	sfx.audio_enabled_override = true
	sfx.play_element("not_an_element")
	sfx.play_element("")
	sfx.warden_prepare(null)
	sfx.warden_intent(null)
	sfx.map_screen(true)
	check(not sfx.is_loop_playing("school_room_tone_loop"), "map peek during a battle keeps the tone off")
	var imported: bool = ResourceLoader.exists(sfx.FILES["battle_ambience"])
	if imported:
		sfx.encounter_music("battle", 1)
		check(sfx.current_music() == "battle_ambience", "normal battle uses the ambience")
		sfx.encounter_music("battle", 2)
		check(sfx.current_music() == "battle_ambience", "ambience is not restarted by the next battle")
		sfx.encounter_music("boss", 2)
		check(sfx.current_music() == "boss_theme", "other boss uses boss_theme")
		sfx.encounter_music("boss", 3)
		check(sfx.current_music() == "midnight_warden", "Warden uses midnight_warden")
		sfx.map_screen(false)
		check(sfx.current_music() == "battle_ambience", "map returns to the ambience")
		check(sfx.is_loop_playing("school_room_tone_loop"), "map starts the room tone")
		sfx.encounter_music("battle", 1)
		check(not sfx.is_loop_playing("school_room_tone_loop"), "a fight drops the room tone")
	else:
		print("NOTE: audio files are not imported yet, music checks skipped")
	sfx.stop_music()
	sfx.stop_loop("school_room_tone_loop")
	sfx.audio_enabled_override = null
	print("audio_hooks_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
