extends SceneTree
# Checks the Sfx audio manager: mapping, loading, loops, music rules, safe no-ops.
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
	check(sfx.audio_enabled_override == null, "override is null by default")
	var files: Dictionary = sfx.FILES
	check(files.size() == 64, "64 mapped files (got %d)" % files.size())
	var any_imported := false
	for sound_name in files:
		check(FileAccess.file_exists(files[sound_name]), "file exists on disk: " + files[sound_name])
		if ResourceLoader.exists(files[sound_name]):
			any_imported = true
	# Disabled: nothing plays, nothing errors.
	sfx.audio_enabled_override = false
	sfx.play("card_draw")
	sfx.play_music("battle_ambience")
	sfx.start_loop("fluorescent_hum_loop")
	check(sfx.current_music() == "", "disabled: no music recorded")
	check(not sfx.is_loop_playing("fluorescent_hum_loop"), "disabled: no loop")
	for player in sfx._pool:
		check(not player.playing, "disabled: pool player silent")
	# Enabled: unknown names are safe.
	sfx.audio_enabled_override = true
	sfx.play("no_such_sound")
	sfx.play_music("no_such_sound")
	sfx.start_loop("no_such_sound")
	sfx.stop_loop("no_such_sound")
	sfx.stop_music()
	check(sfx.current_music() == "", "unknown music name not recorded")
	if any_imported:
		for sound_name in files:
			check(sfx.get_stream(sound_name) != null, "loads: " + sound_name)
		for loop_name in sfx.LOOP_NAMES:
			var wav := sfx.get_stream(loop_name) as AudioStreamWAV
			check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, loop_name + " loops forward")
			check(wav != null and wav.loop_end > 0, loop_name + " has a loop end")
		for music_name in sfx.MUSIC_NAMES:
			var music: AudioStream = sfx.get_stream(music_name)
			check(music != null and bool(music.get("loop")), music_name + " loops")
		# One-shots.
		sfx.play("card_draw")
		sfx.play("card_hover")
		sfx.play("card_hover")
		var busy := 0
		for player in sfx._pool:
			if player.playing:
				busy += 1
		check(busy == 2, "hover is rate limited (busy %d)" % busy)
		# Music never restarts.
		sfx.play_music("battle_ambience")
		check(sfx.current_music() == "battle_ambience", "ambience started")
		await create_timer(0.3).timeout
		var pos_before: float = sfx._music_player.get_playback_position()
		sfx.play_music("battle_ambience")
		await process_frame
		var pos_after: float = sfx._music_player.get_playback_position()
		check(pos_after >= pos_before, "same track does not restart")
		sfx.play_music("midnight_warden")
		check(sfx.current_music() == "midnight_warden", "switches to another track")
		sfx.stop_music()
		check(sfx.current_music() == "", "stop_music clears the track")
		# Loops.
		sfx.start_loop("school_room_tone_loop")
		check(sfx.is_loop_playing("school_room_tone_loop"), "loop starts")
		sfx.start_loop("school_room_tone_loop")
		sfx.stop_loop("school_room_tone_loop")
		check(not sfx.is_loop_playing("school_room_tone_loop"), "loop stops")
	else:
		print("NOTE: audio files are not imported yet, load checks skipped")
	sfx.audio_enabled_override = null
	print("audio_manager_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
