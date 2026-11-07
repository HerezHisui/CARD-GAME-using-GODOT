extends SceneTree
## Audit A3. The production defaults of the late LAN flags, with every test override left at null.
## The legacy suites switch the flags off explicitly; this suite covers the flags-on path.

const Session = preload("res://scripts/lan_session.gd")
const View = preload("res://scripts/lan_view.gd")
const Flags = preload("res://scripts/versus_match.gd")

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.run_director.persistence.enabled = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	expect(game.lan_evolution_picks_override == null and game.lan_prep_utilities_override == null
		and game.evolution_draw_choice_override == null, "all test overrides are null by default")
	expect(Flags.LAN_EVOLUTION_PICKS and Flags.LAN_PREP_UTILITIES and Flags.EVOLUTION_DRAW_CHOICE,
		"the late flags are on")
	expect(Session.PROTOCOL == 6 and Session.build_string().begins_with("6|"), "protocol 6 with both LAN flags on")
	# Local Versus keeps the evolution draw choice; a remote seat uses the LAN picks.
	game.set_seats("local", "local")
	expect(game.evolution_choice.enabled(), "local Versus: the draw choice is on")
	expect(not game.evolution_choice.lan_enabled(), "local Versus: no LAN picks")
	game.set_seats("remote", "local")
	expect(game.evolution_choice.lan_enabled(), "remote Preparedness: LAN picks are on")
	expect(game.preparedness_actions.utilities_on(), "remote Preparedness: utilities are on")
	game.set_seats("local", "remote")
	expect(game.evolution_choice.lan_enabled() and game.preparedness_actions.flag_on(),
		"remote Disaster: LAN picks and the graveyard list flag are on")
	expect(View.build(game, "disaster").has("disaster_graveyard_list"), "the Disaster view carries the graveyard list")
	# Singleplayer never changes.
	game.encounter_kind = "battle"
	game.set_seats("local", "local")
	expect(not game.evolution_choice.enabled() and not game.preparedness_actions.flag_on(),
		"singleplayer: both flags stay off")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		push_error("lan_flag_defaults_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: lan_flag_defaults_smoke (%d checks)" % checks)
	quit(0)
