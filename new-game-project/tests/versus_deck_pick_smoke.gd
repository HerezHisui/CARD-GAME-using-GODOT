extends SceneTree
## Covers: the Versus figure pick (docs/notes/versus-deck-pick-plan.md, one computer). versus_match.gd keeps each
## player's figure, seat_figures.gd reads it in Versus. The hook is on only with
## game.seat_figures_override = {"versus": true}; SEAT_FIGURES_VERSUS stays false.

const VersusMatch = preload("res://scripts/versus_match.gd")
const Decks = preload("res://scripts/versus_decks.gd")
const SeatFigures = preload("res://scripts/seat_figures.gd")
const StandeeFigure = preload("res://scripts/standee_figure.gd")
const PrepFigure = preload("res://scripts/preparedness_figure.gd")
const SAVE_PATH := "user://test_versus_deck_pick_smoke.cfg"
const HOOK := {"versus": true}

var failures := 0
var checks := 0
var game: Node
var director: Node
var versus: Node
var shot_folder := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot_folder = arg.trim_prefix("--shot=")
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	Decks.save_path = SAVE_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	director.start_versus_match()
	versus = director.versus_match
	end_match()
	check_lists()
	check_choose_deck()
	await check_hook_off()
	await check_keeps_deck()
	await check_match_end()
	versus.automated_deck = ""
	versus.automated_figure = ""
	versus.deck_choice = VersusMatch.DECK_CHOICE_ENABLED
	game.seat_figures_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: versus_deck_pick_smoke (%d checks)" % checks)
	quit(0)


# ---------------------------------------------------------------- helpers
func frames(count: int = 3) -> void:
	for i in count: await process_frame


## Waits up to 600 frames (the tree may be paused).
func wait_for(check: Callable) -> bool:
	for i in 600:
		if check.call(): return true
		await process_frame
	return check.call()


func coin_logs() -> int:
	var count := 0
	for line: String in game.battle_log:
		if line.contains("Coin:"): count += 1
	return count


func end_match() -> void:
	paused = false
	game.clear_battle()
	director.battle_finished(true)
	paused = false


## Starts a Versus match with these seats. The toss winner picks so that Player 1 gets p1_side.
func start_match(prep_seat: String, disaster_seat: String, p1_side: String) -> bool:
	end_match()
	versus.deck_choice = true
	versus.automated_side = ""
	game.set_seats(prep_seat, disaster_seat)
	director.start_versus_match()
	if not await wait_for(func(): return versus.prematch_active): return false
	var other := Decks.SIDE_DISASTER if p1_side == Decks.SIDE_PREP else Decks.SIDE_PREP
	versus.choose_side(p1_side if versus.coin_winner == 1 else other)
	return versus.player1_side == p1_side


func ids(cards: Array) -> Array:
	var out: Array = []
	for card: Dictionary in cards: out.append(card.get("id", ""))
	out.sort()
	return out


func body() -> Node3D:
	return game.opponent_hand.character.find_child("JanitorMesh", true, false)


## A legal Preparedness deck that differs from the preset (one main card swapped).
func custom_prep() -> Dictionary:
	var deck: Dictionary = Decks.preset(Decks.SIDE_PREP).duplicate(true)
	var pool: Dictionary = Decks.pool(Decks.SIDE_PREP)
	for id: String in pool.base:
		if deck.main.count(id) == 0:
			deck.main[0] = id
			break
	deck.tactics = ["brace", "supply", "flank"]
	return deck


# ---------------------------------------------------------------- checks
## The id lists and the network check.
func check_lists() -> void:
	expect(VersusMatch.figure_ids(Decks.SIDE_PREP) == ["sam", "robin", "sage", "kai"],
		"Lists: the leaders are Sam, Robin, Sage, Kai in that order")
	expect(VersusMatch.figure_ids(Decks.SIDE_DISASTER) == ["guardian", "janitor", "warden"],
		"Lists: the bosses are the keys of bosses.json in order")
	expect(VersusMatch.figure_ids("nobody").is_empty(), "Lists: an unknown side has no figures")
	expect(VersusMatch.figure_ok(Decks.SIDE_PREP, "robin"), "Lists: robin is a leader")
	for bad: Variant in [5, "nobody", "janitor", "", null, "a".repeat(5000)]:
		expect(not VersusMatch.figure_ok(Decks.SIDE_PREP, bad), "Lists: %s is not a leader" % str(bad).left(12))
	expect(not VersusMatch.figure_ok(Decks.SIDE_DISASTER, "robin"), "Lists: robin is not a boss")


## choose_deck keeps the figure for the player on that side, only from the side's list.
func check_choose_deck() -> void:
	versus.player1_side = Decks.SIDE_PREP
	versus.player2_side = Decks.SIDE_DISASTER
	versus.choose_deck(Decks.SIDE_PREP, {}, "robin")
	expect(versus.seat_figures.p1 == "", "Pick: a figure before the step is ignored")
	versus.start_deck_step()
	versus.choose_deck(Decks.SIDE_PREP, {}, "guardian")
	expect(versus.seat_figures.p1 == "" and versus.deck_ready[Decks.SIDE_PREP],
		"Pick: a boss on the Preparedness side is refused, the deck still counts")
	versus.choose_deck(Decks.SIDE_DISASTER, {}, "warden")
	expect(versus.seat_figures.p2 == "warden", "Pick: Player 2's boss is kept")
	expect(versus.figure_for(Decks.SIDE_DISASTER) == "warden" and versus.figure_for(Decks.SIDE_PREP) == "",
		"Pick: figure_for reads the player on that side")
	versus.clear_prematch()
	expect(versus.seat_figures == {"p1": "", "p2": ""}, "Pick: clear_prematch empties the figures")


## 1. Hook off: today's bodies in Versus, even with a figure kept.
func check_hook_off() -> void:
	expect(not VersusMatch.SEAT_FIGURES_VERSUS, "Hook off: SEAT_FIGURES_VERSUS is false in the repo")
	versus.automated_deck = "standard"
	versus.automated_figure = "robin"
	game.seat_figures_override = null
	var ok := await start_match("local", "remote", Decks.SIDE_PREP)
	expect(ok and await wait_for(func(): return coin_logs() == 1), "Hook off: the match starts")
	expect(versus.seat_figures.p1 == "robin", "Hook off: the pick is still kept")
	for override: Variant in [null, {"far": "robin", "near": "robin"}, {"versus": false}]:
		game.seat_figures_override = override
		await frames()
		var label := "Hook off, override %s: " % str(override)
		expect(not SeatFigures.on(game), label + "the hook is off")
		expect(SeatFigures.far_id(game) == "janitor" and SeatFigures.near_id(game) == "", label + "today's ids")
		expect(body().visible and game.opponent_hand.far_standee == null, label + "the Janitor shows")
		expect(game.opponent_hand.figure.get_script() == PrepFigure, label + "today's near figure")
	game.seat_figures_override = null
	end_match()


## 6. The figure keeps the deck: Standard stays Standard, a valid custom deck is dealt.
func check_keeps_deck() -> void:
	game.seat_figures_override = HOOK
	versus.automated_deck = "standard"
	versus.automated_figure = ""
	expect(await start_match("local", "remote", Decks.SIDE_PREP), "Deck: Player 1 plays Preparedness")
	expect(await wait_for(func(): return coin_logs() == 1), "Deck: no figure, Standard, the round starts")
	var plain := ids(game.versus_master.preparedness)
	versus.automated_figure = "robin"
	expect(await start_match("local", "remote", Decks.SIDE_PREP), "Deck: again with Robin")
	expect(await wait_for(func(): return coin_logs() == 1), "Deck: Robin, Standard, the round starts")
	expect(versus.seat_figures.p1 == "robin" and versus.custom_decks.is_empty(), "Deck: Robin kept, Standard")
	expect(ids(game.versus_master.preparedness) == plain, "Deck: versus_master unchanged by the figure")
	expect(SeatFigures.on(game) and SeatFigures.near_id(game) == "robin", "Deck: the near id is robin")
	expect(SeatFigures.far_id(game) == "janitor", "Deck: no boss picked, the far id is janitor")
	var deck := custom_prep()
	expect(Decks.validate(Decks.SIDE_PREP, deck).ok, "Fixture: the custom Preparedness deck is legal")
	Decks.save_custom(Decks.SIDE_PREP, deck)
	versus.automated_deck = "custom"
	expect(await start_match("local", "remote", Decks.SIDE_PREP), "Deck: custom with Robin")
	expect(await wait_for(func(): return coin_logs() == 1), "Deck: custom, the round starts")
	var all_ids := ids(game.deck) + ids(game.hand.map(func(card): return card.card_data))
	all_ids.sort()
	var want: Array = deck.main.duplicate()
	want.sort()
	expect(all_ids == want and versus.seat_figures.p1 == "robin", "Deck: the custom deck is dealt with Robin")
	versus.automated_deck = ""
	versus.automated_figure = ""


## 9. The match ends: the figures are gone, a singleplayer battle follows the singleplayer rule.
func check_match_end() -> void:
	expect(versus.seat_figures.p1 == "robin", "End: Robin is kept before the end")
	end_match()
	expect(versus.seat_figures == {"p1": "", "p2": ""}, "End: the match end empties the figures")
	game.set_seats("local", "local")
	game.seat_figures_override = null
	game.disaster_is_human = false
	director.battle_active = true
	game.start_encounter(director.character_deck(0), "battle", 1, 0)
	director.screen = ""
	director.close_modal()
	await wait_for(func(): return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY])
	expect(game.encounter_kind == "battle" and not SeatFigures.on(game), "End: singleplayer, the flag decides")
	expect(SeatFigures.far_id(game) == "janitor" and SeatFigures.near_id(game) == "", "End: today's ids")
	game.seat_figures_override = HOOK
	await frames()
	expect(SeatFigures.on(game) and SeatFigures.far_id(game) == "dealer", "End: an override uses the room row")
	game.seat_figures_override = null
	game.clear_battle()
	director.battle_active = false
