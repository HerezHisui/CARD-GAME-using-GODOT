extends "res://tests/oct18_card_logic_smoke.gd"

func effect_consistency() -> void:
	fixture()
	var ally := unit("response", 0)
	var other := unit("response", 1)
	game.resolve_single_strike(ally, other, true)
	check(other.card_data.health == 8 and game.enemy_hp == 40, "Response cannot attack Response")
	var a: String = director.card_rules({"element":"evac", "modifier":"piercing"})
	var b: String = director.card_rules({"element":"evac", "modifiers":["piercing"]})
	check(a == b, "primary and added modifiers share effect text")
	check("Starts with 2 Strength" in director.card_rules({"element":"brace", "strength":2}),
		"starting Strength is described")

func future_adaptations() -> void:
	fixture()
	var deployed := unit("response", 0)
	var held := unit()
	game.add_global_buff(true, "glass")
	check(deployed.max_health == 8 and deployed.effective_attack() == 2,
		"deployed units skip both Glass Cannon effects")
	check(held.max_health == 7 and held.effective_attack() == 4, "hand units receive future deployment effects")
	var future := unit("response", 1)
	check(future.max_health == 7 and future.effective_attack() == 4, "new units receive both effects")
	game.add_global_buff(true, "glass")
	check(deployed.max_health == 8 and deployed.effective_attack() == 2, "repeated picks preserve original units")
	check(future.max_health == 7 and future.effective_attack() == 4, "later deployed units skip later picks only")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(deployed.card_data))
	check(game.buffs_for(saved).strength == 0, "exemptions survive JSON serialization")
	game.add_global_buff(true, "health")
	check(deployed.max_health == 9, "positive health adaptations still affect existing units")
	game.add_global_buff(false, "glass")
	check(deployed.effective_attack() == 2, "opposing adaptations do not alter exemptions")

func double_strikes() -> void:
	fixture()
	var attacker := unit("response", 0, {"condition":{"status":"burn", "threshold":3, "strikes":2}})
	var blocker := unit("disaster", 0, {"health":1})
	blocker.add_status("burn", 3)
	game.resolve_attack(attacker, blocker, true)
	check(not blocker.is_alive() and game.enemy_hp == 38, "second strike hits hero after first kills blocker")
	fixture()
	attacker = unit("response", 0, {"strength":2, "modifier":"sluggish",
		"condition":{"subject":"self", "status":"strength", "threshold":2, "strikes":2}})
	blocker = unit("disaster", 1, {"health":20})
	game.resolve_attack(attacker, blocker, true)
	check(blocker.card_data.health == 12 and game.enemy_hp == 40,
		"both strikes hit a surviving redirected target even with Sluggish")
	check(not attacker.can_attack(2), "Sluggish still rests on the next round")

func status_synergy() -> void:
	fixture()
	var attacker := unit("response", 0, director.catalog_card("containment_lance"))
	var blocker := unit("disaster", 0)
	blocker.statuses = {"burn":1, "poison":1, "strength":8}
	check(game.conditional_attack_bonus(attacker, blocker) == 0, "positive statuses do not count toward threshold")
	blocker.statuses.bleed = 1
	check(game.conditional_attack_bonus(attacker, blocker) == 2, "three mixed negative stacks grant bonus")
	check(game.conditional_attack_bonus(attacker, null) == 0, "status synergy does not buff hero damage on open lanes")
	attacker.card_data = director.catalog_card("last_responder")
	blocker.statuses = {"bleed":2}
	check(game.conditional_attack_bonus(attacker, blocker) == 2, "Last Responder rewards Bleed support")
	check(int(director.catalog_card("hazmat_team").cost) == 2, "Hazmat Team is an affordable Poison enabler")

func elite_themes() -> void:
	for specialty in range(4):
		fixture()
		game.start_encounter(director.character_deck(0), "elite", 2, specialty)
		var favored: String = ["fire", "earthquake", "flood", "typhoon"][specialty]
		var cards: Array = game.enemy_deck + game.enemy_hand + game.enemy_evolution_deck
		check(cards.all(func(card): return card.element == favored), "elite reserves share their encounter type")
		check(game.enemy_evolution_deck.size() == 13, "themed elites keep thirteen evolution choices")
		var enabler: String = ["cinder_cloud", "glass_quake", "toxic_runoff", "pressure_front"][specialty]
		check(cards.any(func(card): return card.id == enabler), "elite contains its status or Strength enabler")

func upgrade_pacing() -> void:
	for element in ["evac", "douse", "clearance", "brace"]:
		var base := {"name":"Upgrade test", "element":element, "cost":2, "attack":1, "health":2}
		var first: Dictionary = director.upgraded_definition(base)
		var second: Dictionary = director.upgraded_definition(first)
		check(not first.has("on_hit") and not first.has("modifiers") and not first.has("on_play_draw"),
			"first upgrade adds no mechanic to a basic unit")
		check(second.has("on_hit") or second.has("modifiers") or second.has("on_play_draw"),
			"second upgrade unlocks the deferred mechanic")
	var steam: Dictionary = director.upgraded_definition(director.catalog_card("steam_team"))
	check(int(steam.on_hit.burn) == 4, "existing Burn may improve at first upgrade")
	var shelter: Dictionary = director.upgraded_definition(director.catalog_card("shelter_brace"))
	check(int(shelter.armor_value) == 2, "existing Armor may improve at first upgrade")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	effect_consistency()
	future_adaptations()
	double_strikes()
	status_synergy()
	elite_themes()
	upgrade_pacing()
	game.clear_battle()
	print("OCT18 BALANCE: %d failures" % failures)
	quit(1 if failures else 0)
