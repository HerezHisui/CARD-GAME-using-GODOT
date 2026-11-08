extends SceneTree
## Deck builder Part 2: the deck step after the side pick (LAN host), and the re-deal.
## No network here: the host is forced with game.set_seats(...) before the match, like lan_title does.
## The flag is turned on through versus_match.deck_choice, the const stays false.

const VersusMatch = preload("res://scripts/versus_match.gd")
const Decks = preload("res://scripts/versus_decks.gd")
const SAVE_PATH := "user://test_versus_deck_step_smoke.cfg"
const WAIT_MS := 8000

var failures := 0
var checks := 0
var game: Node
var director: Node
var versus: Node
var deck_screen_seen := false # set by the frame waits when the deck screen shows


func _initialize() -> void:
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
	check_wait_state()
	await check_wait_ends_at_once()
	await check_flag_off()
	await check_hot_seat()
	await check_standard_click()
	await check_custom_prep()
	await check_custom_disaster()
	await check_abort()
	versus.deck_choice = false
	game.set_seats("local", "local")
	game.clear_battle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: versus_deck_step_smoke (%d checks)" % checks)
	quit(0)


# ---------------------------------------------------------------- helpers
func coin_logs() -> int:
	var count := 0
	for line: String in game.battle_log:
		if line.contains("Coin:"): count += 1
	return count


func deck_screen_open() -> bool:
	return is_instance_valid(game.presentation.deck_root)


# Waits in frames (the tree may be paused). Notes when the deck screen shows.
func wait_for(check: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not check.call() and Time.get_ticks_msec() - start < WAIT_MS:
		if deck_screen_open(): deck_screen_seen = true
		await process_frame
	if deck_screen_open(): deck_screen_seen = true
	return check.call()


func frames(count: int) -> void:
	for i in count: await process_frame


func end_match() -> void:
	paused = false
	game.clear_battle()
	director.battle_finished(true)
	paused = false


# Starts a Versus match with these seats. The toss winner picks so that Player 1 gets host_side.
func start_match(prep_seat: String, disaster_seat: String, host_side: String, deck_on: bool) -> bool:
	end_match()
	deck_screen_seen = false
	versus.deck_choice = deck_on
	versus.automated_side = ""
	game.set_seats(prep_seat, disaster_seat)
	director.start_versus_match()
	if not await wait_for(func(): return versus.prematch_active): return false
	var other := Decks.SIDE_DISASTER if host_side == Decks.SIDE_PREP else Decks.SIDE_PREP
	versus.choose_side(host_side if versus.coin_winner == 1 else other)
	return versus.player1_side == host_side


func ids(cards: Array) -> Array:
	var out: Array = []
	for card: Dictionary in cards: out.append(card.get("id", ""))
	out.sort()
	return out


func hand_ids() -> Array:
	var out: Array = []
	for card in game.hand: out.append(card.card_data.get("id", ""))
	out.sort()
	return out


# A legal deck that differs from the preset: one copy of a main card is swapped for another.
func custom_deck(side: String) -> Dictionary:
	var deck: Dictionary = Decks.preset(side).duplicate(true)
	var pool: Dictionary = Decks.pool(side)
	var main_pool: Dictionary = pool.base.duplicate()
	if side == Decks.SIDE_DISASTER: main_pool.merge(pool.spells)
	deck.main = swap_one(deck.main, main_pool)
	if side == Decks.SIDE_DISASTER: deck.evolutions = swap_one(deck.evolutions, pool.evolutions)
	else: deck.tactics = ["brace", "supply", "flank"]
	return deck


func swap_one(pile: Array, allowed: Dictionary) -> Array:
	var out: Array = pile.duplicate()
	for id: String in allowed:
		if out.count(id) == 0:
			out[0] = id
			return out
	return out


# ---------------------------------------------------------------- checks
func check_wait_state() -> void:
	expect(VersusMatch.DECK_CHOICE_ENABLED, "Flag: DECK_CHOICE_ENABLED is true in the repo")
	expect(versus.deck_choice == VersusMatch.DECK_CHOICE_ENABLED, "Flag: deck_choice starts from the const")
	var good := custom_deck(Decks.SIDE_PREP)
	expect(Decks.validate(Decks.SIDE_PREP, good).ok, "Fixture: the custom Preparedness deck is legal")
	versus.choose_deck(Decks.SIDE_PREP, good)
	expect(not versus.deck_ready[Decks.SIDE_PREP], "Wait: a choice before the step is ignored")
	versus.start_deck_step()
	versus.choose_deck("nobody", {})
	expect(not versus.decks_are_ready() and versus.custom_decks.is_empty(), "Wait: an unknown side is ignored")
	versus.choose_deck(Decks.SIDE_PREP, {"main": ["not_a_card"], "tactics": ["brace"]})
	expect(versus.deck_ready[Decks.SIDE_PREP], "Wait: an invalid deck still makes the side ready")
	expect(not versus.custom_decks.has(Decks.SIDE_PREP), "Wait: an invalid deck counts as Standard")
	versus.choose_deck(Decks.SIDE_PREP, good)
	expect(not versus.custom_decks.has(Decks.SIDE_PREP), "Wait: a repeated choice is ignored")
	versus.choose_deck(Decks.SIDE_DISASTER, custom_deck(Decks.SIDE_DISASTER))
	expect(versus.decks_are_ready() and versus.custom_decks.has(Decks.SIDE_DISASTER), "Wait: a valid deck is kept")
	var cards: Dictionary = versus.deck_cards(Decks.SIDE_DISASTER)
	expect(cards.main.size() == 24 and cards.evolutions.size() == 6, "Wait: deck_cards gives 24 and 6 cards")
	versus.clear_prematch()
	expect(not versus.deck_step_active and not versus.decks_are_ready() and versus.custom_decks.is_empty(),
		"Wait: clear_prematch resets the deck step")
	versus.choose_deck(Decks.SIDE_PREP, {})
	expect(not versus.deck_ready[Decks.SIDE_PREP], "Wait: a late choice is ignored")


func check_wait_ends_at_once() -> void:
	versus.start_deck_step()
	versus.choose_deck(Decks.SIDE_PREP, {})
	versus.choose_deck(Decks.SIDE_DISASTER, {})
	var before := Engine.get_process_frames()
	var ok: bool = await versus.wait_for_decks()
	expect(ok and Engine.get_process_frames() == before, "Wait: ends at once when both sides are ready")
	versus.start_deck_step()
	var serial: int = versus.prematch_serial
	var done := [false, true]
	var waiter := func():
		done[1] = await versus.wait_for_decks()
		done[0] = true
	waiter.call()
	await frames(3)
	expect(not done[0], "Wait: waits while a side has no deck")
	versus.clear_prematch()
	await frames(3)
	expect(done[0] and not done[1] and versus.prematch_serial != serial, "Wait: clear_prematch wakes the wait")


func check_flag_off() -> void:
	var ok := await start_match("local", "remote", Decks.SIDE_PREP, false)
	expect(ok, "Flag off: the LAN host plays Preparedness")
	expect(await wait_for(func(): return coin_logs() == 1), "Flag off: the round starts right after the side")
	expect(not deck_screen_seen and not versus.deck_step_active, "Flag off: no deck screen")
	end_match()


func check_hot_seat() -> void:
	var ok := await start_match("local", "local", Decks.SIDE_PREP, true)
	expect(ok, "Hot seat: Player 1 plays Preparedness")
	# A hot-seat Disaster raises the privacy cover. The round still starts.
	expect(await wait_for(func(): return coin_logs() == 1), "Hot seat: the round starts")
	expect(not deck_screen_seen and not versus.deck_step_active, "Hot seat: never shows the deck step")
	end_match()


# Standard through the real input path: hand and decks stay the same.
func check_standard_click() -> void:
	var ok := await start_match("local", "remote", Decks.SIDE_PREP, true)
	expect(ok, "Standard: the LAN host plays Preparedness")
	expect(await wait_for(deck_screen_open), "Standard: the deck screen shows after the side pick")
	expect(coin_logs() == 0 and versus.deck_step_active, "Standard: no round during the deck step")
	expect(versus.deck_ready[Decks.SIDE_DISASTER], "Standard: the client side is Standard and ready")
	var old_nodes: Array = game.hand.duplicate()
	var old_hand := hand_ids()
	var old_deck := ids(game.deck)
	var old_enemy := ids(game.enemy_deck) + ids(game.enemy_hand)
	var old_evolutions := ids(game.enemy_evolution_deck)
	var old_tactics: Array = game.plans.unlocked.duplicate()
	await frames(20)
	var button: Button = game.presentation.deck_buttons[0]
	expect(button.text == "Standard deck", "Standard: the first button is Standard deck")
	var point := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		click.global_position = point
		root.push_input(click, true)
		await process_frame
	expect(await wait_for(func(): return coin_logs() == 1), "Standard: the click ends the step, the round starts")
	expect(not deck_screen_open() and not versus.deck_step_active, "Standard: the deck screen is closed")
	expect(game.hand == old_nodes and hand_ids() == old_hand, "Standard: the same hand cards")
	expect(ids(game.deck) == old_deck, "Standard: the same Preparedness deck")
	expect(ids(game.enemy_deck) + ids(game.enemy_hand) == old_enemy, "Standard: the same Disaster cards")
	expect(ids(game.enemy_evolution_deck) == old_evolutions, "Standard: the same evolution pile")
	expect(game.plans.unlocked == old_tactics, "Standard: the same tactics")
	end_match()


func check_custom_prep() -> void:
	var deck := custom_deck(Decks.SIDE_PREP)
	Decks.save_custom(Decks.SIDE_PREP, deck)
	var ok := await start_match("local", "remote", Decks.SIDE_PREP, true)
	expect(ok, "Custom Preparedness: the LAN host plays Preparedness")
	expect(await wait_for(deck_screen_open), "Custom Preparedness: the deck screen shows")
	var old_nodes: Array = game.hand.duplicate()
	var old_enemy := ids(game.enemy_deck) + ids(game.enemy_hand)
	var hp: int = game.player_hp
	var energy: int = game.preparedness
	var tension: int = game.tension
	# Customize opens the builder on the saved deck. Done saves and chooses it.
	game.presentation.open_deck_builder(Decks.SIDE_PREP, versus)
	var builder: Control = game.presentation.deck_builder
	expect(is_instance_valid(builder), "Custom Preparedness: Customize opens the builder")
	expect(builder.current_deck().main == deck.main, "Custom Preparedness: the builder opens on the saved deck")
	builder.back.emit()
	await process_frame
	expect(game.presentation.deck_box.visible, "Custom Preparedness: Back shows the two buttons again")
	game.presentation.open_deck_builder(Decks.SIDE_PREP, versus)
	game.presentation.deck_builder.done.emit(deck)
	expect(await wait_for(func(): return coin_logs() == 1), "Custom Preparedness: the round starts")
	var all_ids := ids(game.deck)
	all_ids.append_array(hand_ids())
	all_ids.sort()
	var want: Array = deck.main.duplicate()
	want.sort()
	expect(all_ids == want, "Custom Preparedness: deck plus hand are the 24 custom cards")
	expect(game.hand.size() == 3 and game.deck.size() == 21, "Custom Preparedness: 3-card hand, 21 in the deck")
	expect(game.plans.unlocked == ["brace", "supply", "flank"], "Custom Preparedness: the new tactics")
	var stale := 0
	for card in old_nodes:
		if is_instance_valid(card) and card.is_in_group("cards"): stale += 1
	expect(stale == 0, "Custom Preparedness: no old hand card left in the cards group")
	for card in get_nodes_in_group("cards"):
		if card in old_nodes: stale += 1
	expect(stale == 0, "Custom Preparedness: the cards group has only new cards")
	expect(ids(game.enemy_deck) + ids(game.enemy_hand) == old_enemy, "Custom Preparedness: Disaster unchanged")
	expect(game.player_hp == hp and game.preparedness == energy and game.tension == tension and game.turn == 1,
		"Custom Preparedness: HP, energy, tension and turn stay")
	expect(game.hand_container.visible, "Custom Preparedness: a Preparedness host sees the hand")
	var saved := Decks.load_custom(Decks.SIDE_PREP)
	expect(saved.main == deck.main, "Custom Preparedness: Done saved the deck")
	end_match()


func check_custom_disaster() -> void:
	var deck := custom_deck(Decks.SIDE_DISASTER)
	expect(Decks.validate(Decks.SIDE_DISASTER, deck).ok, "Fixture: the custom Disaster deck is legal")
	Decks.save_custom(Decks.SIDE_DISASTER, deck)
	versus.automated_deck = "custom"
	var ok := await start_match("remote", "local", Decks.SIDE_DISASTER, true)
	expect(ok, "Custom Disaster: the LAN host plays the Disaster")
	var old_hand := hand_ids()
	var old_deck := ids(game.deck)
	expect(await wait_for(func(): return coin_logs() == 1), "Custom Disaster: the automated deck ends the step")
	versus.automated_deck = ""
	expect(deck_screen_seen, "Custom Disaster: the deck screen showed")
	var main_ids := ids(game.enemy_deck)
	var evolution_ids := ids(game.enemy_evolution_deck)
	for card: Dictionary in game.enemy_hand:
		if card.get("id", "") in deck.evolutions and card.get("id", "") not in deck.main:
			evolution_ids.append(card.id)
		else:
			main_ids.append(card.id)
	main_ids.sort()
	evolution_ids.sort()
	var want_main: Array = deck.main.duplicate()
	want_main.sort()
	var want_evolutions: Array = deck.evolutions.duplicate()
	want_evolutions.sort()
	expect(main_ids == want_main and evolution_ids == want_evolutions, "Custom Disaster: the new 24 and 6 piles")
	if game.evolution_choice.enabled():
		# LAN evolution picks (on by default): the opening evolution is an offer. Nothing leaves the pile until a pick.
		expect(game.enemy_deck.size() == 21 and game.enemy_evolution_deck.size() == 6
			and game.evolution_choice.pending(), "Custom Disaster: 3 main cards drawn, evolution offered")
		expect(game.enemy_hand.size() == 3, "Custom Disaster: a 3-card hand while the evolution is offered")
	else:
		expect(game.enemy_deck.size() == 21 and game.enemy_evolution_deck.size() == 5,
			"Custom Disaster: 3 main cards and 1 evolution drawn")
		expect(game.enemy_hand.size() == 4, "Custom Disaster: a 3-card hand plus 1 evolution")
	expect(hand_ids() == old_hand and ids(game.deck) == old_deck, "Custom Disaster: Preparedness unchanged")
	expect(not game.hand_container.visible, "Custom Disaster: the Disaster host never sees the Preparedness hand")
	end_match()


func check_abort() -> void:
	var ok := await start_match("local", "remote", Decks.SIDE_PREP, true)
	expect(ok, "Abort: the LAN host plays Preparedness")
	expect(await wait_for(deck_screen_open), "Abort: the deck screen shows")
	versus.abort("OPPONENT LEFT", "The other player left the match.")
	await frames(5)
	expect(not deck_screen_open() and not versus.deck_step_active, "Abort: the deck step closes")
	expect(coin_logs() == 0, "Abort: no round starts")
	game.presentation.pick_standard_deck(Decks.SIDE_PREP, versus)
	await frames(3)
	expect(coin_logs() == 0, "Abort: a late choice starts nothing")
	end_match()
