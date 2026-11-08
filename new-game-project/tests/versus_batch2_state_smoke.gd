extends SceneTree

const Snapshot = preload("res://scripts/battle_snapshot.gd")
const Board = preload("res://scripts/lan_board_3d.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.run_director.persistence.enabled = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.set_seats("local", "local")
	var choice: RefCounted = game.evolution_choice
	var default_override: Variant = game.evolution_draw_choice_override
	game.evolution_draw_choice_override = false
	expect(not choice.enabled(), "False override forces legacy despite enabled constant")
	game.evolution_draw_choice_override = default_override
	expect(choice.enabled(), "Null override follows enabled constant")
	game.evolution_draw_choice_override = true
	# LAN follows its own flag (LAN_EVOLUTION_PICKS, ships true). Switch it off to check the local override is ignored.
	game.lan_evolution_picks_override = false
	for seats in [["local", "remote"], ["remote", "local"]]:
		game.set_seats(seats[0], seats[1])
		expect(not choice.enabled(), "LAN retains legacy even with true override")
	game.lan_evolution_picks_override = null
	game.set_seats("local", "local")
	game.encounter_kind = "battle"
	expect(not choice.enabled(), "Override does not affect singleplayer")
	game.encounter_kind = "versus"
	var evolution := {"id": "same", "name": "Evolution", "type": "disaster", "element": "fire",
		"cost": 1, "attack": 3, "health": 4, "locked_until": 3}
	game.enemy_evolution_deck.assign([evolution.duplicate(true), evolution.duplicate(true)])
	choice.draw()
	var selected: Dictionary = choice.offer[0]
	expect(choice.pick(selected.id, choice.offer_id, game.encounter_serial), "Held fixture picks physical copy")
	choice.draw()
	var held_id: String = choice.held[0].id
	var adapter := Snapshot.new()
	var data: Dictionary = JSON.parse_string(JSON.stringify(adapter.capture(game).to_dict()))
	expect(adapter.has_method("restore_evolutions"), "Snapshot exposes evolution restoration")
	if adapter.has_method("restore_evolutions"):
		choice.reset()
		game.enemy_evolution_deck.clear()
		var previous_offer: int = choice.offer_id
		expect(adapter.restore_evolutions(game, data), "JSON snapshot restores local evolutions")
		expect(choice.held.size() == 1 and choice.held[0].id == held_id, "Held physical ID survives restore")
		expect(choice.held[0].definition == evolution, "Held definition and temporary seal survive restore")
		expect(choice.pending() and choice.offer.size() == 1, "Pending offer survives restore")
		expect(is_same(choice.offer[0].definition, game.enemy_evolution_deck[int(choice.offer[0].index)]),
			"Restored offer references restored physical deck copy")
		expect(choice.offer_id > previous_offer, "Restore invalidates stale offer callbacks")
		expect(not choice.pick(choice.offer[0].id, previous_offer, game.encounter_serial), "Old callback rejected")
		expect(choice.pick(choice.offer[0].id, choice.offer_id, game.encounter_serial), "Restored offer remains usable")
		expect(choice.held.size() == 2 and choice.held[0].id != choice.held[1].id, "Duplicate definitions keep distinct IDs")
		choice.held[0].definition.health = 99
		expect(int(data.cards[data.zones.disaster.held_evolutions[0]].definition.health) == 4,
			"Restored definitions are detached from saved snapshot")
		# Restore follows evolution_choice.enabled(). With LAN picks on, LAN may restore; check the flag-off path.
		game.lan_evolution_picks_override = false
		game.set_seats("local", "remote")
		expect(not adapter.restore_evolutions(game, data), "Snapshot restore rejects LAN")
		game.lan_evolution_picks_override = null
		game.set_seats("local", "local")
	await check_seals(game)
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("%s: versus_batch2_state_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func check_seals(game: Node) -> void:
	var board: Node = Board.new()
	board.game = game
	var definition := {"id": "sealed", "name": "Sealed fixture", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 2, "health": 4, "seal_round": 3}
	board.view = {"round": 3}
	var card: Node = board._make_card(definition, game)
	var entry := {"definition": definition, "runtime": {}}
	# Both lane ownership and a host-independent clock must reach preview cards.
	if card.get("preview_seal_round") == null:
		expect(false, "LAN previews support their own seal clock")
	else:
		board._apply_runtime(card, entry, true)
		expect(card._seal_banner.visible and card._seal_banner.text == "SEALED", "Own client card shows active seal")
		board._apply_runtime(card, entry, false)
		expect(not card._seal_banner.visible, "Opponent client card hides seal banner")
		board.view.round = 2
		board._apply_runtime(card, entry, true)
		expect(card._seal_banner.visible and card._seal_banner.text == "SEAL NEXT " + char(183) + " R3",
			"Pending seal uses view round")
		board.view.round = 4
		board._apply_runtime(card, entry, true)
		expect(not card._seal_banner.visible, "Expired seal disappears on view update")
	card.queue_free()
	board.view = {"round": 3, "lanes": {"response": ["r", "", "", ""], "disaster": ["d", "", "", ""]},
		"cards": {"r": entry, "d": entry}}
	for seat in ["preparedness", "disaster"]:
		board.side = seat
		board._sync_lanes()
		var own: String = board._own_side()
		var other := "response" if own == "disaster" else "disaster"
		expect(board.lane_cards[own][0]._seal_banner.visible, seat + " own lane displays seal")
		expect(not board.lane_cards[other][0]._seal_banner.visible, seat + " opponent lane hides seal")
		if "--render-part2" in OS.get_cmdline_user_args():
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			var folder := ProjectSettings.globalize_path("res://../docs/notes/batch2-part2")
			DirAccess.make_dir_recursive_absolute(folder)
			var own_card: Node = board.lane_cards[own][0]
			expect(own_card._vp.get_texture().get_image().save_png(folder + "/" + seat + "-own-sealed.png") == OK,
				"Save own-side seal screenshot")
	for lane_side in ["response", "disaster"]:
		board.lane_cards[lane_side][0].queue_free()
	board.free()
