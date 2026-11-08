extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")
var checks := 0
var failures := 0
var rendered := false
var output := "C:/Users/0stef/Downloads/drrills-part1-checks"

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	if not rendered: return
	await create_timer(0.4, true).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, "Capture " + name)

func check_names(director: Node, expected: Array) -> void:
	var names: Array = []
	# The offer screen moves Row out of the Cards scroll (evolution_choice._style_offer). The held browser keeps it.
	var row: Node = director.content.get_node_or_null("Cards/Row")
	if row == null: row = director.content.get_node_or_null("Row")
	expect(row != null, "Evolution picker has a card row")
	if row == null: return
	for tile in row.get_children():
		var title: Label = tile.get_node_or_null("Box/CardName")
		if title != null: names.append(title.text)
	names.sort()
	expected.sort()
	expect(names == expected, "Evolution picker shows each full card name")

func protocol_side(side_name: String) -> Node:
	var holder := Node.new()
	holder.name = side_name
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var session: Node = preload("res://scripts/lan_session.gd").new()
	session.name = "LanSession"
	holder.add_child(session)
	return session

func check_old_protocol() -> void:
	var host := protocol_side("Batch1Host")
	var client := protocol_side("Batch1Client")
	var refusals: Array = []
	client.join_refused.connect(func(reason: String): refusals.append(reason))
	client.build = "2|" + Engine.get_version_info().string
	expect(host.host_game(24716) == OK, "Protocol 3 host starts")
	expect(client.join_game("127.0.0.1", 24716) == OK, "Protocol 2 client connects for negotiation")
	var start := Time.get_ticks_msec()
	while refusals.is_empty() and Time.get_ticks_msec() - start < 10000:
		await process_frame
	expect(refusals == ["version"], "Protocol 3 refuses protocol 2 before seating")
	expect(host.disaster_peer == 0 and host.prep_peer == 0, "Old client never receives a seat")
	host.close()
	client.close()
	host.get_parent().queue_free()
	client.get_parent().queue_free()
	await frames()

func run() -> void:
	rendered = "--render-part1" in OS.get_cmdline_user_args()
	if rendered:
		DirAccess.make_dir_recursive_absolute(output)
		root.size = Vector2i(1280, 800)
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var director: Node = game.run_director
	director.persistence.enabled = false
	game.presentation.automated_choice = 0
	game.clear_battle()
	director.battle_active = true
	director.close_modal()
	game.encounter_kind = "battle"
	director.show_menu()
	expect(director.content.get_node("RulesScroll/Rules/Adaptations").visible, "Singleplayer keeps Adaptations")
	expect(director.content.get_node("RulesScroll/Rules/Augmentations").visible, "Singleplayer keeps Augmentations")
	expect(director.content.has_node("DebugButton"), "Singleplayer keeps Debug values")
	director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.disaster_waiting = true
	director.privacy_serial = game.encounter_serial
	director.privacy_last = "disaster"
	director.privacy_screen.hide()
	game._set_phase(game.Phase.ENEMY)
	await frames()
	director.show_menu()
	# With the balance patch on, the Adaptations label shows the Versus rules help instead of the adaptations.
	var adaptations: Label = director.content.get_node("RulesScroll/Rules/Adaptations")
	if game.balance_enabled():
		expect(adaptations.visible and adaptations.text.begins_with("Versus:"), "Versus shows rules help, not Adaptations")
	else:
		expect(not adaptations.visible, "Versus hides Adaptations")
	expect(not director.content.get_node("RulesScroll/Rules/Augmentations").visible, "Versus hides Augmentations")
	var debug: Node = director.content.get_node_or_null("DebugButton")
	expect(debug == null or not debug.visible, "Versus hides Debug values")
	await capture("versus-esc-menu")
	director.close_modal()
	game.evolution_draw_choice_override = true
	game.tension = 3
	game.disaster_actions.begin_turn()
	var pool: Dictionary = Decks.pool("disaster")
	game.enemy_evolution_deck.assign([pool.evolutions.wildfire.duplicate(true),
		pool.evolutions.worldbreaker.duplicate(true)])
	game.enemy_draw_evolutions(1)
	var choice: RefCounted = game.evolution_choice
	choice.show_offer()
	await frames()
	check_names(director, ["Wildfire", "Worldbreaker"])
	await capture("evolution-offer-names")
	var selected: Dictionary = choice.offer[0]
	expect(choice.pick(selected.id, choice.offer_id, game.encounter_serial), "Offer pick accepted")
	director.close_modal()
	game.disaster_seat_on = true
	choice.show_held()
	await frames()
	check_names(director, [selected.definition.name])
	await capture("evolution-held-names")
	director.close_modal()
	choice.reset()
	game.evolution_draw_choice_override = false
	# The allowance rules below are the balance-off Versus path. BALANCE_PATCH ships on and its evolve waits for
	# a confirm click, so pin it off here. The balance_* suites cover the balance-on rules.
	game.balance_patch_override = false
	var base: Dictionary = pool.base.ember.duplicate(true)
	var evolution: Dictionary = pool.evolutions.wildfire.duplicate(true)
	evolution.cost = 1
	game.enemy_hand.assign([base, evolution])
	var actions: RefCounted = game.disaster_actions
	var lane: Node3D = game._threat_slots()[0]
	expect((await actions.play_base(base, lane)).ok, "Base consumes one allowance and Tension")
	var tension_before: int = game.tension
	var allowance_before: int = actions.actions_left()
	expect((await actions.evolve(evolution, [game._get_card_in_slot(lane)], lane)).ok, "Evolution succeeds")
	expect(actions.actions_used == 2, "Evolution stays in total actions_used")
	expect(game.tension == tension_before, "Evolution spends no Tension")
	expect(actions.actions_left() == allowance_before, "Evolution spends no Versus allowance")
	game.tension = 0
	game.enemy_hand.assign([base])
	expect(actions.card_problem(base) == "no_tension", "Zero Tension has its own reason")
	game.disaster_seat._refuse(null, director.DISASTER_REASONS.no_tension)
	await capture("no-tension-message")
	game.tension = 2
	actions.begin_turn()
	actions.actions_used = actions.action_limit
	expect(actions.card_problem(base) == "action_limit", "Allowance exhausted has its own reason")
	game.disaster_seat._refuse(null, director.DISASTER_REASONS.action_limit)
	expect(director.versus_hud.note_head.text == "ACTION LIMIT REACHED", "Action limit has a distinct note")
	await capture("action-limit-message")
	actions.begin_turn()
	expect(actions.actions_left() == 2, "New turn resets evolution allowance exemption")
	game.encounter_kind = "battle"
	actions.action_limit = 3
	actions._finish(true)
	expect(actions.actions_left() == 2, "Singleplayer still counts its actions")
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	await check_old_protocol()
	print("%s: versus_batch1_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
