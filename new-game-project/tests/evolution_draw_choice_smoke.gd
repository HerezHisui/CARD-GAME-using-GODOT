extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	expect(game.evolution_choice.enabled(), "Local human Versus enables evolution choice by default")
	game.set("evolution_draw_choice_override", true)
	game.enemy_evolution_deck.assign([
		{"id": "a", "name": "A", "type": "disaster", "cost": 1},
		{"id": "b", "name": "B", "type": "disaster", "cost": 2},
		{"id": "c", "name": "C", "type": "disaster", "cost": 3}])
	game.enemy_draw_evolutions(1)
	expect(game.enemy_hand.is_empty(), "Enabled draw never enters main hand")
	expect(game.enemy_evolution_deck.size() == 3, "Offer consumes no deck entry")
	var choice: RefCounted = game.evolution_choice
	expect(choice.offer.size() == 3, "Three candidates")
	var candidate: Dictionary = choice.offer[0]
	expect(not choice.pick("forged", choice.offer_id, game.encounter_serial), "Forged ID refused")
	expect(not choice.pick(candidate.id, choice.offer_id + 1, game.encounter_serial), "Stale offer refused")
	expect(choice.pick(candidate.id, choice.offer_id, game.encounter_serial), "Candidate accepted")
	expect(choice.held.size() == 1 and game.enemy_evolution_deck.size() == 2, "Exactly one consumed")
	expect(not choice.pick(candidate.id, choice.offer_id, game.encounter_serial), "Replay refused")
	game.enemy_draw_evolutions(1)
	expect(choice.offer.size() == 2, "Small deck offers both entries")
	candidate = choice.offer[0]
	choice.pick(candidate.id, choice.offer_id, game.encounter_serial)
	game.enemy_draw_evolutions(1)
	expect(choice.offer.is_empty() and game.enemy_evolution_deck.size() == 1, "Cap skips without consuming")
	expect("Evolution draw skipped, 2 held" in game.battle_log[-1], "Skip note recorded")
	var targets: Array = game.held_evolution_targets()
	expect(targets.size() == 2 and not targets[0].has("definition"), "Target addresses hide definitions")
	var value: Dictionary = choice.definition(targets[0].id)
	game.increase_cost(value)
	expect(value.cost == value.tax_original + 1, "Held tax uses existing cost rules")
	game.turn += 2
	game.expire_tax(value)
	expect(not value.has("tax_original"), "Held tax expires")
	value.locked_until = game.turn + 2
	expect(game.is_sealed(value), "Held seal uses existing expiry")
	game.turn += 2
	expect(not game.is_sealed(value), "Held seal expires")
	# LAN now follows LAN_EVOLUTION_PICKS (ships true). Switch it off to check the legacy path.
	game.lan_evolution_picks_override = false
	game.set_seats("remote", "local")
	expect(not choice.enabled(), "LAN host Disaster uses legacy behavior")
	game.set_seats("local", "remote")
	expect(not choice.enabled(), "LAN remote Disaster uses legacy behavior")
	game.lan_evolution_picks_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	expect(choice.held.is_empty() and choice.offer.is_empty(), "Reset clears private zones")
	game.enemy_evolution_deck.clear()
	game.enemy_draw_evolutions(1)
	expect(choice.offer.is_empty(), "Empty deck has no offer")
	game.enemy_evolution_deck.assign([{"id": "same", "name": "Same", "cost": 1},
		{"id": "same", "name": "Same", "cost": 1}])
	game.enemy_draw_evolutions(1)
	expect(choice.offer.size() == 2 and choice.offer[0].id != choice.offer[1].id, "Duplicate copies have IDs")
	var unchosen: Dictionary = choice.offer[1].definition
	candidate = choice.offer[0]
	choice.pick(candidate.id, choice.offer_id, game.encounter_serial)
	expect(is_same(game.enemy_evolution_deck[0], unchosen), "Unchosen physical copy stays unchanged")
	game.enemy_draw_evolutions(1)
	expect(choice.offer.size() == 1, "One-card deck has one candidate")
	game.clear_battle()
	game.encounter_kind = "battle"
	expect(not choice.enabled(), "Singleplayer remains legacy")
	game.queue_free()
	await process_frame
	print("%s: evolution_draw_choice_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
