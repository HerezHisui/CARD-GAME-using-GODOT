extends Node
# Sound for the whole game. Autoload name: Sfx.
# Every call is fire-and-forget: no await, no game state, no errors when a file is missing.

const AUDIO_ENABLED := true
const POOL_SIZE := 8
const MUSIC_DB := -8.0
const LOOP_DB := -14.0
# Minimum milliseconds between two plays of the same sound.
const MIN_GAP_MSEC := {"card_hover": 90}
const SFX := "res://assets/audio/sfx/"
const OST := "res://assets/audio/ost/"

# name -> file. Names are the file names without the extension.
const FILES := {
	"battle_ambience": OST + "battle_ambience.mp3",
	"boss_theme": OST + "boss_theme.mp3",
	"midnight_warden": OST + "midnight_warden.mp3",
	"brace": SFX + "attack/brace.wav",
	"clearance": SFX + "attack/clearance.wav",
	"douse": SFX + "attack/douse.wav",
	"earthquake": SFX + "attack/earthquake.ogg",
	"evac": SFX + "attack/evac.ogg",
	"fire": SFX + "attack/fire.mp3",
	"flood": SFX + "attack/flood.mp3",
	"healing_1": SFX + "attack/healing_1.ogg",
	"typhoon": SFX + "attack/typhoon.ogg",
	"card_cancel_return": SFX + "cards_and_ui/card_cancel_return.wav",
	"card_draw": SFX + "cards_and_ui/card_draw.wav",
	"card_hover": SFX + "cards_and_ui/card_hover.wav",
	"card_select": SFX + "cards_and_ui/card_select.wav",
	"choice_confirm": SFX + "cards_and_ui/choice_confirm.wav",
	"invalid_action": SFX + "cards_and_ui/invalid_action.wav",
	"menu_open_close": SFX + "cards_and_ui/menu_open_close.wav",
	"unit_deploy": SFX + "cards_and_ui/unit_deploy.wav",
	"utility_cast": SFX + "cards_and_ui/utility_cast.wav",
	"card_permanently_removed": SFX + "map_rewards_atmosphere/card_permanently_removed.wav",
	"card_reward_select": SFX + "map_rewards_atmosphere/card_reward_select.wav",
	"defeat": SFX + "map_rewards_atmosphere/defeat.wav",
	"distant_building_movement": SFX + "map_rewards_atmosphere/distant_building_movement.wav",
	"encounter_door_open": SFX + "map_rewards_atmosphere/encounter_door_open.wav",
	"fluorescent_hum_loop": SFX + "map_rewards_atmosphere/fluorescent_hum_loop.wav",
	"infirmary_treatment": SFX + "map_rewards_atmosphere/infirmary_treatment.wav",
	"locker_tick": SFX + "map_rewards_atmosphere/locker_tick.wav",
	"map_room_select": SFX + "map_rewards_atmosphere/map_room_select.wav",
	"pipe_creak": SFX + "map_rewards_atmosphere/pipe_creak.wav",
	"school_room_tone_loop": SFX + "map_rewards_atmosphere/school_room_tone_loop.wav",
	"shop_purchase": SFX + "map_rewards_atmosphere/shop_purchase.wav",
	"supplies_gained": SFX + "map_rewards_atmosphere/supplies_gained.wav",
	"upgrade_confirmed": SFX + "map_rewards_atmosphere/upgrade_confirmed.wav",
	"victory": SFX + "map_rewards_atmosphere/victory.wav",
	"ability_activate": SFX + "status/ability_activate.wav",
	"bleed_tick": SFX + "status/bleed_tick.wav",
	"burn_tick": SFX + "status/burn_tick.wav",
	"card_seal": SFX + "status/card_seal.wav",
	"cleanse": SFX + "status/cleanse.wav",
	"cost_increase": SFX + "status/cost_increase.wav",
	"poison_tick": SFX + "status/poison_tick.wav",
	"relocation": SFX + "status/relocation.wav",
	"seal_expire": SFX + "status/seal_expire.wav",
	"strength_gain": SFX + "status/strength_gain.wav",
	"adaptation_offered": SFX + "turns_resources_contingencies/adaptation_offered.wav",
	"adaptation_selected": SFX + "turns_resources_contingencies/adaptation_selected.wav",
	"contingency_unlocked": SFX + "turns_resources_contingencies/contingency_unlocked.wav",
	"contingency_unlocked_and_activated":
		SFX + "turns_resources_contingencies/contingency_unlocked_and_activated.wav",
	"end_turn_sfx": SFX + "turns_resources_contingencies/end_turn_sfx.mp3",
	"evolution_summoned": SFX + "turns_resources_contingencies/evolution_summoned.wav",
	"plan_saved": SFX + "turns_resources_contingencies/plan_saved.wav",
	"sacrifice": SFX + "turns_resources_contingencies/sacrifice.wav",
	"turn_start": SFX + "turns_resources_contingencies/turn_start.mp3",
	"attack_warning": SFX + "warden/attack_warning.wav",
	"blade_rush": SFX + "warden/blade_rush.wav",
	"boss_entrance": SFX + "warden/boss_entrance.wav",
	"phase_transition": SFX + "warden/phase_transition.wav",
	"pillar_destroyed": SFX + "warden/pillar_destroyed.wav",
	"punishment": SFX + "warden/punishment.wav",
	"shackle_summoned": SFX + "warden/shackle_summoned.wav",
	"shield_pillars_activate": SFX + "warden/shield_pillars_activate.wav",
	"static_echo": SFX + "warden/static_echo.wav",
}
const MUSIC_NAMES := ["battle_ambience", "boss_theme", "midnight_warden"]
const LOOP_NAMES := ["fluorescent_hum_loop", "school_room_tone_loop"]

# Tests set this to true or false. null means "use AUDIO_ENABLED".
var audio_enabled_override: Variant = null

var _cache := {}
var _warned := {}
var _pool: Array[AudioStreamPlayer] = []
var _next_slot := 0
var _music_player: AudioStreamPlayer
var _music_name := ""
var _loop_players := {}
var _last_msec := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = MUSIC_DB
	add_child(_music_player)

func is_enabled() -> bool:
	if audio_enabled_override != null:
		return bool(audio_enabled_override)
	return AUDIO_ENABLED

# Load a sound once. Returns null (and warns once) when the name or file is missing.
func get_stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var stream: AudioStream = null
	if not FILES.has(sound_name):
		_warn_once(sound_name, "Sfx: unknown sound '%s'" % sound_name)
	elif not ResourceLoader.exists(FILES[sound_name]):
		_warn_once(sound_name, "Sfx: file not imported '%s'" % FILES[sound_name])
	else:
		stream = load(FILES[sound_name]) as AudioStream
		if stream == null:
			_warn_once(sound_name, "Sfx: could not load '%s'" % FILES[sound_name])
		else:
			_set_loop(sound_name, stream)
	if stream != null:
		_cache[sound_name] = stream
	return stream

func _set_loop(sound_name: String, stream: AudioStream) -> void:
	if sound_name in MUSIC_NAMES and "loop" in stream:
		stream.set("loop", true)
	elif sound_name in LOOP_NAMES and stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)

func _warn_once(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(text)

# Play a one-shot sound on the next pool slot.
func play(sound_name: String, volume_db: float = 0.0) -> void:
	if not is_enabled() or _pool.is_empty():
		return
	if MIN_GAP_MSEC.has(sound_name):
		var now := Time.get_ticks_msec()
		if now - int(_last_msec.get(sound_name, -100000)) < int(MIN_GAP_MSEC[sound_name]):
			return
		_last_msec[sound_name] = now
	var stream := get_stream(sound_name)
	if stream == null:
		return
	var player := _pool[_next_slot]
	_next_slot = (_next_slot + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.play()

# Start a music track. The same track is never restarted.
func play_music(sound_name: String) -> void:
	if not is_enabled() or _music_player == null:
		return
	if sound_name == _music_name and _music_player.playing:
		return
	var stream := get_stream(sound_name)
	if stream == null:
		return
	_music_name = sound_name
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	if _music_player == null:
		return
	_music_player.stop()
	_music_name = ""

func current_music() -> String:
	return _music_name

# Start a looping room tone. Calling it again while it plays does nothing.
func start_loop(sound_name: String) -> void:
	if not is_enabled():
		return
	if _loop_players.has(sound_name) and _loop_players[sound_name].playing:
		return
	var stream := get_stream(sound_name)
	if stream == null:
		return
	if not _loop_players.has(sound_name):
		var player := AudioStreamPlayer.new()
		player.volume_db = LOOP_DB
		add_child(player)
		_loop_players[sound_name] = player
	_loop_players[sound_name].stream = stream
	_loop_players[sound_name].play()

func stop_loop(sound_name: String) -> void:
	if _loop_players.has(sound_name):
		_loop_players[sound_name].stop()

func is_loop_playing(sound_name: String) -> bool:
	return _loop_players.has(sound_name) and _loop_players[sound_name].playing

# ---------------------------------------------------------------- game helpers
# These only read public values and play sounds. They never change the game.
const ELEMENTS := ["brace", "clearance", "douse", "earthquake", "evac", "fire", "flood", "typhoon"]
var _warden_stage := 0

# An attack hit. The element name is also the sound name.
func play_element(element: String) -> void:
	if element in ELEMENTS:
		play(element, -4.0)

# Start of a fight: pick the music and drop the map room tone.
func encounter_music(kind: String, floor_level: int) -> void:
	stop_loop("school_room_tone_loop")
	if kind == "boss" and floor_level == 3:
		play_music("midnight_warden")
	elif kind == "boss":
		play_music("boss_theme")
	else:
		play_music("battle_ambience")

# Map screen: ambience and room tone, but not while the map is only peeked at during a battle.
func map_screen(in_battle: bool) -> void:
	if in_battle:
		return
	play_music("battle_ambience")
	start_loop("school_room_tone_loop")

func warden_enter() -> void:
	_warden_stage = 1
	play("boss_entrance")
	play_music("midnight_warden")

# Round start: phase change and Static Echo.
func warden_prepare(boss: Variant) -> void:
	if not is_enabled() or not is_instance_valid(boss):
		return
	var stage := int(boss.get("stage"))
	if stage != _warden_stage:
		if _warden_stage > 0:
			play("phase_transition")
		_warden_stage = stage
	if stage == 2 and bool(boss.get("pillars_spawned")):
		play("static_echo")

# Just before the Warden pattern resolves.
func warden_intent(boss: Variant) -> void:
	if not is_enabled() or not is_instance_valid(boss):
		return
	var stage := int(boss.get("stage"))
	var turn := int(boss.game.turn)
	if stage == 2:
		if not bool(boss.get("pulse_resolved")) and turn > int(boss.get("changed_round")):
			play("shield_pillars_activate")
		return
	if stage == 3:
		if turn == int(boss.get("changed_round")):
			return
		play("blade_rush")
	elif turn % 2 == 0:
		play("shackle_summoned")
	else:
		play("blade_rush")
	_play_later("punishment", 0.4)

# Plays a sound after a short pause without waiting for it.
func _play_later(sound_name: String, seconds: float) -> void:
	if is_inside_tree():
		get_tree().create_timer(seconds).timeout.connect(play.bind(sound_name))
