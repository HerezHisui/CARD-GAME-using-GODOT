extends SceneTree
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func definition(id: String) -> Dictionary:
	for item in director.catalog:
		if item.id == id: return item.duplicate(true)
	assert(false, "missing " + id)
	return {}

func card(data: Dictionary, slot: Node3D = null) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup(data)
	if slot:
		result.in_hand = false
		result.current_slot = slot
		result.global_position = slot.global_position + Vector3(0, 0.02, 0)
		result._set_overlay(false)
	else:
		result.reparent(game.hand_parent())
		game.hand.append(result)
		game.arrange_hand_centered()
	return result

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
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	check(game.has_node("SchoolEnvironment/SuppliedClassroom/OriginalRoom") and game.has_node("SchoolEnvironment/OpponentPosition"), "current supplied classroom and opponent position are retained")
	director.show_characters()
	check(director.CHARACTERS[0].name == "Steve · Student", "starter renamed Steve")
	var locked := 0
	for child in director.content.find_children("*", "Button", true, false):
		if child.disabled and child.get_parent().get_child(1).text.contains("AVAILABLE SOON"): locked += 1
	check(locked == 3, "three club leaders disabled and marked soon")
	await capture("steve_selection")
	director.start_character(1)
	check(director.screen == "characters", "disabled club cannot launch a run")
	director.start_character(0)
	check(director.collection.size() == 12 and game.player_run_buffs.has("cadet"), "Steve keeps starter and original perk")
	director.floor_number = 2
	director.current = 3
	director.show_shop()
	check(director.shop_stock.any(func(item): return item.id == "barrier") and director.shop_stock.any(func(item): return item.id == "alarm_sweep"), "boss preparation cards guaranteed in later shops")
	await capture("boss_prep_shop")
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 1
	game.energy_cap = 10
	game.preparedness = 10
	game.enemy_max_hp = 34
	game.enemy_hp = 34
	game.player_hp = 20
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	var boss: Node = game.final_boss
	var friendly := {"name":"Response", "type":"response", "element":"brace", "cost":1, "attack":1, "health":10}
	var ally = card(friendly, game._response_slots()[0])
	var punished = card(friendly, game._response_slots()[1])
	var third = card(friendly, game._response_slots()[2])
	check(boss.intent().contains("Blade Rush"), "first phase announced")
	await capture("final_boss_phase_one")
	boss.resolve_intent()
	check(ally.statuses.bleed == 1 and punished.card_data.health == 7 and punished.statuses.healing_reduced == 2, "first pattern applies announced damage and statuses")
	punished.heal(2)
	check(punished.card_data.health == 8, "healing reduction halves healing")
	var tablet = card(definition("tablet"))
	check(game.try_utility(tablet, game._response_slots()[3]), "tablet can be cast")
	check(not punished.statuses.has("healing_reduced") and punished.card_data.health == 10, "tablet clears debuff before healing")
	var herb = card(definition("herb"))
	game.try_utility(herb, game._response_slots()[3])
	check(not ally.statuses.has("bleed"), "herb removes Bleed")
	var barrier = card(definition("barrier"))
	game.try_utility(barrier, game._response_slots()[3])
	var hp: int = ally.card_data.health
	ally.take_damage(2)
	check(ally.card_data.health == hp and int(ally.statuses.barrier) == 0, "unit barrier absorbs and is spent")
	game._damage_side(true, 2)
	check(game.player_hp == 20 and game.player_barrier == 0, "hero barrier absorbs and is spent")
	game._damage_side(false, 100)
	check(game.enemy_hp == 17 and boss.stage == 2 and not boss.pulse_resolved, "large hit clamps to halfway and warns before transition")
	game._damage_side(false, 5)
	check(game.enemy_hp == 17, "pillar phase shields boss health")
	boss.last_resolved_round = -1
	boss.resolve_intent()
	check(not boss.pulse_resolved, "transition does not surprise player in same round")
	game.turn = 2
	boss.resolve_intent()
	check(boss.pillars().size() == 2 and boss.guardian() != null and ally.card_data.health == hp - 1, "telegraphed pulse then summons two pillars and guardian")
	var pillar = boss.pillars()[0]
	check(boss.redirect_target(ally, pillar) == boss.guardian(), "guardian redirects ordinary pillar attacks")
	var lance = card(definition("containment_lance"))
	check(boss.redirect_target(lance, pillar) == pillar, "ignore taunt reaches pillar")
	game.turn = 3
	boss.prepare_round()
	check(game.get_hand_cards().any(func(unit): return unit.card_data.get("curse", false)), "pillar phase creates temporary curse")
	var echo = game.get_hand_cards().filter(func(unit): return unit.card_data.get("curse", false))[0]
	game.deck.append(definition("quick_dash"))
	game.try_utility(echo, game._response_slots()[3])
	check(game.player_hp == 19 and game.player_graveyard.any(func(item): return item.id == "static_echo"), "curse casting costs HP and enters graveyard")
	await capture("final_boss_pillars")
	var before: int = pillar.card_data.health
	var sweep = card(definition("alarm_sweep"))
	game.try_utility(sweep, game._response_slots()[3])
	check(pillar.card_data.health == before - 2, "AoE bypasses guardian")
	var first = boss.pillars()[0]
	first.take_damage(99)
	check(boss.stage == 2, "one remaining pillar keeps shield active")
	var last = boss.pillars()[0]
	last.take_damage(99)
	check(boss.stage == 3 and game.player_graveyard.any(func(item): return item.graveyard_reason == "Pillar recoil"), "last pillar breaks shield with bounded discard")
	game.turn = 4
	game.add_card_to_hand(definition("fire_drill"))
	boss.prepare_round()
	check((game.get_hand_cards().any(func(unit): return game.is_sealed(unit.card_data)) or game.deck.any(func(item): return game.is_sealed(item))), "final phase excludes a card temporarily")
	boss.resolve_intent()
	check(int(ally.statuses.get("bleed", 0)) > 0, "final phase applies Bleed")
	await capture("final_boss_phase_three")
	director.floor_number = 3
	director.encounter = "boss"
	game._damage_side(false, 100)
	game._check_game_over()
	check(director.screen == "contingency_reward" and game.phase == game.Phase.GAME_OVER, "final boss awards a contingency")
	director.select_contingency_reward(director.buff_choices[0].id)
	check(director.screen == "victory", "final boss ends three-floor run")
	await capture("run_victory")
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.start_encounter(director.collection, "boss", 3, 0)
	for i in 100:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	check(is_instance_valid(game.final_boss) and game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY], "actual final encounter starts through coinflip and does not count empty enemy reserve as victory")
	await capture("final_boss_live")
	game._on_draw_button_pressed()
	if game.phase == game.Phase.PLAYER_DRAW and not game.deck.is_empty():
		game.complete_draw_choice(game.deck[0])
	game.player_hp = 1
	var lethal_curse = card({"name":"Static Echo", "type":"response", "element":"douse", "cost":0, "attack":0, "health":1, "utility":true, "effect":"draw", "draw_count":1, "curse":true})
	game.try_utility(lethal_curse, game._response_slots()[3])
	check(game.phase == game.Phase.GAME_OVER and director.screen == "result", "lethal curse payment ends battle immediately")
	if failures > 0:
		quit(1)
		return
	print("PASS: Steve/locked clubs, native 3D room, guaranteed prep, predictable boss phases/damage/shield/taunt, counter cards/barriers/healing, curses/recoil/sealing, final victory")
	quit(0)
