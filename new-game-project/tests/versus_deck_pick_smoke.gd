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
	await check_page()
	await check_seats()
	await check_no_art()
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
	# Player 2 won the real toss: the "you won the toss" cover is up. Ready lifts it, as a player would.
	if cover().visible: await click(cover().get_node("%ReadyButton"))
	# The fixture fixes the toss: the winner always picks Preparedness, so Preparedness goes first.
	versus.coin_winner = 1 if p1_side == Decks.SIDE_PREP else 2
	versus.choose_side(Decks.SIDE_PREP)
	return versus.player1_side == p1_side


## A real mouse click at the centre of a control.
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame


func deck_page() -> Control:
	return game.presentation.deck_root if is_instance_valid(game.presentation.deck_root) else null


func figure_row() -> Node:
	if deck_page() == null or not is_instance_valid(game.presentation.deck_box): return null
	return game.presentation.deck_box.get_node_or_null("FigureRow")


func page_title() -> String:
	return game.presentation.deck_box.get_child(0).text


func cover() -> Node:
	return director.privacy_screen


## One computer, hook on: Player 1 picks p1_figure, Player 2 picks p2_figure, both Standard, by real clicks.
## Returns true when the round starts.
func pick_both(p1_side: String, p1_figure: String, p2_figure: String) -> bool:
	game.seat_figures_override = HOOK
	if not await start_match("local", "local", p1_side): return false
	if not await wait_for(func(): return figure_row() != null): return false
	await frames(10)
	await click(figure_row().get_node("Figure_" + p1_figure))
	await click(game.presentation.deck_buttons[0])
	if not await wait_for(func(): return figure_row() != null and page_title().begins_with("PLAYER 2")):
		return false
	await frames(10)
	await click(cover().get_node("%ReadyButton"))
	await click(figure_row().get_node("Figure_" + p2_figure))
	await click(game.presentation.deck_buttons[0])
	return await wait_for(func(): return coin_logs() == 1)


## The Disaster's opening evolution offer (local Versus): Ready on its cover, then the first card, as the
## offer's double click picks it (evolution_choice._choose). True when the Preparedness turn has started.
func answer_offer() -> bool:
	var choice: RefCounted = game.evolution_choice
	if not await wait_for(func(): return cover().visible or not choice.pending()): return false
	if cover().visible: await click(cover().get_node("%ReadyButton"))
	if choice.pending():
		await wait_for(func(): return director.modal.visible)
		choice._choose(choice.offer[0].definition)
	if not await wait_for(func(): return game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]):
		return false
	# The first Preparedness turn may raise its own cover.
	await frames(3)
	if cover().visible: await click(cover().get_node("%ReadyButton"))
	await frames(3)
	return not choice.pending()


func capture(shot_name: String, table := false) -> void:
	if shot_folder == "" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1280, 720)
	# The pass-the-laptop cover and the evolution offer would hide the table.
	if table:
		cover().hide()
		director.modal.hide()
	await frames(8)
	var path := shot_folder.path_join(shot_name + ".png")
	expect(root.get_texture().get_image().save_png(path) == OK, shot_name + " frame saved")


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
	# The LAN host page with the hook off: no figure row, the buttons on at once.
	versus.automated_deck = ""
	versus.automated_figure = ""
	expect(await start_match("local", "remote", Decks.SIDE_PREP), "Hook off: the LAN host plays Preparedness")
	expect(await wait_for(func(): return deck_page() != null), "Hook off: the LAN host has the deck page")
	await frames(10)
	expect(figure_row() == null and not game.presentation.deck_buttons[0].disabled,
		"Hook off: no figure row, the deck buttons are on")
	expect(page_title() == "PLAYER 1: PREPAREDNESS DECK", "Hook off: the page title is today's")
	await click(game.presentation.deck_buttons[0])
	expect(await wait_for(func(): return coin_logs() == 1), "Hook off: a Standard click starts the round")
	expect(versus.seat_figures.p1 == "", "Hook off: no figure from the page")
	# One computer with the hook off: no deck step.
	var seen := [false]
	expect(await start_match("local", "local", Decks.SIDE_PREP), "Hook off: one computer")
	expect(await wait_for(func():
		if deck_page() != null: seen[0] = true
		return coin_logs() == 1), "Hook off: one computer, the round starts")
	expect(not seen[0] and not versus.deck_step_active, "Hook off: one computer has no deck step")
	end_match()


## 2 and 3. One computer, hook on: the rows, the order, the deck buttons and the cover, by real clicks.
func check_page() -> void:
	game.seat_figures_override = HOOK
	expect(await start_match("local", "local", Decks.SIDE_PREP), "Page: Player 1 plays Preparedness")
	expect(await wait_for(func(): return figure_row() != null), "Page: the deck step shows the figure row")
	await frames(10)
	var row := figure_row()
	var names: Array = row.get_children().map(func(button): return button.text)
	expect(names == ["SAM", "ROBIN", "SAGE", "KAI"], "Page: four leaders in order, got %s" % str(names))
	expect(page_title() == "PLAYER 1: PREPAREDNESS DECK", "Page: Player 1's title")
	var standard: Button = game.presentation.deck_buttons[0]
	expect(standard.disabled and game.presentation.deck_buttons[1].disabled, "Page: deck buttons off before a pick")
	await click(standard)
	expect(not versus.deck_ready[Decks.SIDE_PREP], "Page: a click on an off deck button does nothing")
	await click(row.get_node("Figure_sage"))
	await click(row.get_node("Figure_robin"))
	expect(row.get_node("Figure_robin").button_pressed and not row.get_node("Figure_sage").button_pressed,
		"Page: the press moves to the last pick")
	expect(row.get_meta("figure") == "robin" and not standard.disabled, "Page: Robin picked, deck buttons on")
	await capture("versus-pick-page-1280")
	await click(standard)
	expect(versus.deck_ready[Decks.SIDE_PREP] and versus.seat_figures.p1 == "robin", "Page: Robin and Standard")
	expect(await wait_for(func(): return figure_row() != null and page_title().begins_with("PLAYER 2")),
		"Page: Player 2's page follows")
	await frames(10)
	expect(page_title() == "PLAYER 2: DISASTER DECK", "Page: Player 2's title")
	names = figure_row().get_children().map(func(button): return button.text)
	expect(names == ["HALLWAY GUARDIAN", "JANITOR", "MIDNIGHT WARDEN"], "Page: three bosses, got %s" % str(names))
	expect(cover().visible, "Page: the cover hides Player 2's page")
	await click(figure_row().get_node("Figure_warden"))
	expect(figure_row().get_meta("figure") == "", "Page: a click through the cover picks nothing")
	await click(cover().get_node("%ReadyButton"))
	expect(not cover().visible, "Page: Ready lifts the cover")
	expect(coin_logs() == 0 and not game.hand_container.visible, "Page: no round and no hand during the step")
	await click(figure_row().get_node("Figure_warden"))
	await click(game.presentation.deck_buttons[0])
	expect(await wait_for(func(): return coin_logs() == 1), "Page: both picks start the round")
	expect(versus.seat_figures == {"p1": "robin", "p2": "warden"}, "Page: both figures kept")
	expect(deck_page() == null and versus.custom_decks.is_empty(), "Page: the page closed, both Standard")
	end_match()


## 4. Robin at each seat. The Disaster seat takes Robin only through the fixture (Robin is not a boss).
func check_seats() -> void:
	expect(await pick_both(Decks.SIDE_PREP, "robin", "janitor"), "Seats: Robin and the Janitor picked")
	await frames(5)
	expect(game.opponent_hand.figure.get_script() == StandeeFigure, "Seats: the near seat is Robin's standee")
	expect(body().visible and game.opponent_hand.far_standee == null, "Seats: the far seat is the Janitor mesh")
	versus.seat_figures.p2 = "robin"
	await frames(5)
	var hand: Node = game.opponent_hand
	expect(is_instance_valid(hand.far_standee) and hand.far_standee.visible and not body().visible,
		"Seats: a far Robin is a standee, the JanitorMesh is hidden")
	expect(await answer_offer(), "Seats: the opening evolution is picked, the Preparedness turn starts")
	expect(game.player_first and hand.visible, "Seats: the far seat is in view on the Preparedness turn")
	expect(game.enemy_hand.size() > 0 and hand.character.holding.get_child_count() == game.enemy_hand.size(),
		"Seats: the fan holds the Disaster hand")
	await frames(120)
	expect(is_instance_valid(hand.far_standee), "Seats: 120 frames with both standees")
	await capture("versus-prep-turn-1280", true)
	# The real seat switch (disaster_seat._wants_seat), as in tests/preparedness_figure_smoke.gd.
	game.phase = game.Phase.ENEMY
	game.disaster_waiting = true
	await frames(3)
	# The "your turn" cover rises for the Disaster. Ready lifts it, as a player would.
	if cover().visible: await click(cover().get_node("%ReadyButton"))
	director.versus_hud.update()
	expect(await wait_for(func(): return game.opponent_hand.figure.visible and not hand.visible),
		"Seats: from the Disaster seat Robin's near standee shows, the far seat does not")
	await capture("versus-disaster-seat-1280", true)
	game.disaster_waiting = false
	end_match()
	await frames(3)
	expect(game.opponent_hand.far_standee == null and body().visible, "Seats: the match end brings back the Janitor")
	expect(game.opponent_hand.figure.get_script() == PrepFigure, "Seats: the match end brings back the near figure")


## 5. Figures with no art yet show today's bodies, with no error.
func check_no_art() -> void:
	for pair: Array in [["sam", "guardian"], ["sage", "warden"], ["kai", "janitor"]]:
		var label := "No art, %s and %s: " % pair
		expect(await pick_both(Decks.SIDE_PREP, pair[0], pair[1]), label + "picked")
		await frames(120)
		expect(versus.seat_figures == {"p1": pair[0], "p2": pair[1]}, label + "kept")
		expect(game.opponent_hand.figure.get_script() == PrepFigure, label + "today's near figure")
		expect(body().visible and game.opponent_hand.far_standee == null, label + "the Janitor mesh")
		end_match()
	expect(await pick_both(Decks.SIDE_DISASTER, "guardian", "robin"), "No art: Player 1 on the Disaster")
	expect(versus.seat_figures == {"p1": "guardian", "p2": "robin"}, "No art: Player 1's boss, Player 2's leader")
	await frames(5)
	expect(game.opponent_hand.figure.get_script() == StandeeFigure and body().visible,
		"No art: Player 2's Robin stands at the near seat")
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
