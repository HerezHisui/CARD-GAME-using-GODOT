extends SceneTree
var game: Node
var director: Node

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAILED: " + message)
		quit(1)
		assert(condition, message)

func definition(id: String) -> Dictionary:
	for card in director.catalog:
		if card.id == id: return card.duplicate(true)
	assert(false, "missing " + id)
	return {}

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_hp = 20
	game.enemy_hp = 20
	game.turn = 1
	game.player_first = false
	game.energy_cap = 10
	game.preparedness = 10
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func make_card(data: Dictionary, slot: Node3D = null) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data)
	if slot:
		card.current_slot = slot
		card.in_hand = false
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.show_characters()
	await capture("characters")
	for i in range(4):
		var starter: Array = director.character_deck(i)
		check(starter.size() == 12, "each character has a complete starter deck")
		director.selected_character = i
		director.new_run()
		check(game.player_run_buffs.has(director.CHARACTERS[i].buff), "character perk assigned")
		check(director.collection == starter, "chosen character deck assigned")
		check(game.enemy_run_buffs.is_empty(), "character perks belong to player")
	director.show_character_preview(2)
	await capture("character_deck")
	director.selected_character = 0
	director.new_run()
	for seed_value in range(300):
		director.rng.seed = seed_value
		director.generate_map()
		check(director.rooms.size() == 31, "longer floor")
		var minimum: Dictionary = {}
		for room in director.rooms:
			var combat := 1 if room.kind in ["battle", "elite"] else 0
			if room.row == 0: minimum[room.id] = combat
			check(minimum.has(room.id), "every node reachable")
			if room.kind != "boss": check(not room.links.is_empty(), "no dead ends")
			for id in room.links:
				check(director.rooms[id].row == room.row + 1, "forward-only routes")
				var next_combat := 1 if director.rooms[id].kind in ["battle", "elite"] else 0
				minimum[id] = mini(int(minimum.get(id, 100)), int(minimum[room.id]) + next_combat)
		check(int(minimum[30]) >= 4, "every possible boss path requires four battles")
	director.show_map()
	await capture("long_map")
	for element in ["evac", "douse", "clearance", "brace"]:
		var card := {"name":"Test", "type":"response", "element":element, "cost":3, "attack":2, "health":3}
		var first: Dictionary = director.upgraded_definition(card)
		var second: Dictionary = director.upgraded_definition(first)
		check(director.upgrade_level(second) == 2 and not director.can_upgrade(second), "two-upgrade cap")
		check(director.upgraded_definition(second) == second and card.name == "Test", "max upgrade and preview preserve source")
		check(first.has("on_play_draw") or first.has("on_hit") or first.has("modifiers"), "unit upgrades grant unique effects")
		if element == "brace":
			fixture()
			var armored = make_card(second, game._response_slots()[0])
			check(armored.has_modifier("armored") and second.thorns == 1, "brace upgrade becomes armored with retaliation")
	var trained_brace: Dictionary = director.upgraded_definition(definition("shelter_brace"))
	check(trained_brace.armor_value == 2, "existing armor improves instead of being replaced")
	var spell: Dictionary = director.upgraded_definition(director.upgraded_definition(definition("rally")))
	check(spell.cost == 0 and spell.utility_power == 1, "spell upgrades reduce cost then improve effect")
	fixture()
	var ally = make_card(definition("momentum_team"), game._response_slots()[0])
	var rally = make_card(spell)
	check(game.try_utility(rally, game._response_slots()[3]), "upgraded spell opens choice")
	game.complete_utility_choice(ally)
	check(ally.statuses.strength == 3, "upgraded rally grants three strength")
	var target = make_card({"name":"Wall", "type":"disaster", "element":"earthquake", "cost":0, "attack":1, "health":30}, game._threat_slots()[0])
	check(game.attack_strikes(ally, target) == 2, "self strength threshold enables double attack")
	game.resolve_attack(ally, target, true)
	check(target.card_data.health == 22, "double strike executes both attacks")
	fixture()
	var hunter = make_card(definition("toxin_hunter"), game._response_slots()[0])
	target = make_card({"name":"Wall", "type":"disaster", "element":"typhoon", "cost":0, "attack":1, "health":30}, game._threat_slots()[0])
	target.add_status("burn", 1)
	target.add_status("poison", 1)
	check(game.attack_strikes(hunter, target) == 1, "below threshold only one strike")
	target.add_status("bleed", 1)
	check(game.attack_strikes(hunter, target) == 2, "mixed harmful stacks count toward threshold")
	hunter.add_status("bleed", 2)
	game.resolve_attack(hunter, target, true)
	check(target.card_data.health == 26 and hunter.card_data.health == 1, "bleed is paid after each strike")
	fixture()
	var seeker = make_card(definition("heat_seeker"), game._response_slots()[0])
	target = make_card({"name":"Fire", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":30}, game._threat_slots()[0])
	target.add_status("burn", 3)
	check(game._calc_damage(seeker, target).dmg == 10, "conditional attack bonus respects effectiveness")
	check(game.conditional_attack_bonus(seeker, null) == 0, "target conditions do not trigger on open lanes")
	check(director.shop_price(definition("heavy_loader")) > director.shop_price(definition("quick_dash")), "strong shop cards cost more")
	fixture()
	game.encounter_kind = "boss"
	var army: Array = []
	for i in range(4): army.append(make_card({"name":"Formation", "type":"disaster", "element":"flood", "cost":0, "attack":3, "health":5}, game._threat_slots()[i]))
	var evo := {"name":"Apex", "type":"disaster", "element":"flood", "cost":3, "attack":7, "health":8}
	check(game.best_evolution_plan(army, [evo]).is_empty(), "AI preserves valuable numerical advantage")
	evo.cost = 1
	evo.attack = 6
	check(not game.best_evolution_plan(army, [evo]).is_empty(), "AI still makes profitable evolutions")
	game.player_hp = 5
	evo.cost = 3
	evo.modifier = "piercing"
	check(not game.best_evolution_plan(army, [evo]).is_empty(), "AI accepts a sacrifice trade that immediately wins")
	fixture()
	director.battle_active = false
	director.current = 3
	director.collection.clear()
	director.collection.append(director.upgraded_definition(definition("hazmat_team")))
	director.collection.append(director.upgraded_definition(definition("shelter_brace")))
	director.show_upgrade_preview(0)
	await capture("unique_upgrade")
	director.shop_key = ""
	director.coins = 150
	director.show_shop()
	await capture("priced_shop")
	director.show_character_preview(1)
	for child in director.content.get_children():
		if child is Button and child.text == "Begin run": child.pressed.emit()
	check(director.selected_character == 1 and game.player_run_buffs.has("marshal"), "actual character selection button starts its deck")
	director.restart_scene()
	await process_frame
	await process_frame
	game = current_scene
	director = game.run_director
	check(director.selected_character == 1 and game.player_run_buffs.has("marshal") and director.collection == director.character_deck(1), "restart retains selected character and starter perk")
	game.start_encounter(director.character_deck(0), "elite", 1, 0)
	check(game.enemy_max_hp == 24 and game.enemy_deck.size() + game.enemy_hand.size() == 21 and game.enemy_evolution_deck.size() == 14, "elite health and deck reductions")
	# Avoid launching a second encounter while the first coinflip coroutine is active.
	print("PASS: 300 exhaustive route checks, four starter characters/perks, two-tier unique upgrades, powered spells, conditional bonuses/double strikes/bleed, priced shops, board-preserving and lethal AI, reduced encounter size")
	quit(0)
