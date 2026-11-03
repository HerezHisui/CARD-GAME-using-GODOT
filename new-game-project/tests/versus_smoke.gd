# Covers: Versus deck rules (versus_decks.gd): presets, deck size, copies, evolutions, tactics, unknown ids.
extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

# A deck must fail and the error list must not be empty.
func rejects(side: String, deck: Dictionary, label: String) -> void:
	var result: Dictionary = Decks.validate(side, deck)
	expect(not result.ok and not result.errors.is_empty(), label)

func run() -> void:
	var prep: Dictionary = Decks.preset(Decks.SIDE_PREP)
	var disaster: Dictionary = Decks.preset(Decks.SIDE_DISASTER)
	var prep_result: Dictionary = Decks.validate(Decks.SIDE_PREP, prep)
	var disaster_result: Dictionary = Decks.validate(Decks.SIDE_DISASTER, disaster)
	expect(prep_result.ok, "Preparedness preset passes: " + str(prep_result.errors))
	expect(disaster_result.ok, "Disaster preset passes: " + str(disaster_result.errors))
	check_pools()
	check_prep_failures(prep)
	check_disaster_failures(disaster)
	if failures > 0:
		push_error("versus_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: versus_smoke (%d checks)" % checks)
	quit(0)

func check_pools() -> void:
	var prep_pool: Dictionary = Decks.pool(Decks.SIDE_PREP)
	var disaster_pool: Dictionary = Decks.pool(Decks.SIDE_DISASTER)
	expect(prep_pool.base.has("supply_cache") and prep_pool.base.has("emergency_exit"), "Prep pool has utilities")
	expect(prep_pool.base.has("quick_dash") and prep_pool.base.has("needle_team"), "Prep pool has json cards")
	expect(disaster_pool.base.has("ember") and disaster_pool.base.has("cinder_cloud"), "Disaster base cards")
	expect(disaster_pool.evolutions.has("wildfire") and disaster_pool.evolutions.has("worldbreaker"), "Evolutions")
	expect(disaster_pool.spells.has("blocked_exit") and disaster_pool.spells.has("red_tape"), "Disaster spells")

func check_prep_failures(prep: Dictionary) -> void:
	var short: Dictionary = prep.duplicate(true)
	short.main.pop_back()
	rejects(Decks.SIDE_PREP, short, "Preparedness with 23 cards fails")
	var long_deck: Dictionary = prep.duplicate(true)
	long_deck.main.append("herb")
	rejects(Decks.SIDE_PREP, long_deck, "Preparedness with 25 cards fails")
	var triple: Dictionary = prep.duplicate(true)
	triple.main[triple.main.size() - 1] = "quick_dash"
	triple.main[triple.main.size() - 2] = "quick_dash"
	rejects(Decks.SIDE_PREP, triple, "Preparedness with 3 copies fails")
	var few_tactics: Dictionary = prep.duplicate(true)
	few_tactics.tactics = ["brace", "coordinate"]
	rejects(Decks.SIDE_PREP, few_tactics, "Preparedness with 2 tactics fails")
	var many_tactics: Dictionary = prep.duplicate(true)
	many_tactics.tactics = ["brace", "coordinate", "medicine", "supply"]
	rejects(Decks.SIDE_PREP, many_tactics, "Preparedness with 4 tactics fails")
	var no_brace: Dictionary = prep.duplicate(true)
	no_brace.tactics = ["coordinate", "medicine", "supply"]
	rejects(Decks.SIDE_PREP, no_brace, "Preparedness without Brace fails")
	var unknown: Dictionary = prep.duplicate(true)
	unknown.main[0] = "not_a_card"
	rejects(Decks.SIDE_PREP, unknown, "Preparedness with unknown card id fails")

func check_disaster_failures(disaster: Dictionary) -> void:
	var short: Dictionary = disaster.duplicate(true)
	short.main.pop_back()
	rejects(Decks.SIDE_DISASTER, short, "Disaster with 23 cards fails")
	var long_deck: Dictionary = disaster.duplicate(true)
	long_deck.main.append("gust")
	rejects(Decks.SIDE_DISASTER, long_deck, "Disaster with 25 cards fails")
	var triple: Dictionary = disaster.duplicate(true)
	triple.main[triple.main.size() - 1] = "ember"
	triple.main[triple.main.size() - 2] = "ember"
	rejects(Decks.SIDE_DISASTER, triple, "Disaster with 3 copies fails")
	var five: Dictionary = disaster.duplicate(true)
	five.evolutions.pop_back()
	rejects(Decks.SIDE_DISASTER, five, "Disaster with 5 evolutions fails")
	var seven: Dictionary = disaster.duplicate(true)
	seven.evolutions.append("worldbreaker")
	rejects(Decks.SIDE_DISASTER, seven, "Disaster with 7 evolutions fails")
	var unknown: Dictionary = disaster.duplicate(true)
	unknown.main[0] = "not_a_card"
	rejects(Decks.SIDE_DISASTER, unknown, "Disaster with unknown card id fails")
	var unknown_evolution: Dictionary = disaster.duplicate(true)
	unknown_evolution.evolutions[0] = "not_a_card"
	rejects(Decks.SIDE_DISASTER, unknown_evolution, "Disaster with unknown evolution id fails")
