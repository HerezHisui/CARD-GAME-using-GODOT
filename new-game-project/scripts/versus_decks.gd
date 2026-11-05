extends RefCounted
## Versus deck rules: card pools, deck checks and one preset per side. Static functions only.
## A deck is {"main": Array of card ids, "evolutions": Array of card ids, "tactics": Array of tactic ids}.
## Open rule: the "finisher" rule is not checked yet.

const BattleRules = preload("res://scripts/battle_rules.gd")
const ContingencyRules = preload("res://scripts/contingency_rules.gd")

const SIDE_PREP := "preparedness"
const SIDE_DISASTER := "disaster"
const MAIN_SIZE := 24
const EVOLUTION_SIZE := 6
const MAX_COPIES := 2
const PREP_FILES := ["res://data/starter_deck.json", "res://data/response_expansion.json"]
const DISASTER_FILES := ["res://data/disaster_deck.json", "res://data/disaster_expansion.json"]

## Same two cards as run_director.gd (_ready, catalog). Keep them in sync.
const PREP_UTILITIES := [
	{"id":"supply_cache", "name":"Supply Cache", "type":"response", "element":"clearance",
		"cost":2, "effect":"draw", "utility":true},
	{"id":"emergency_exit", "name":"Emergency Exit", "type":"response", "element":"evac",
		"cost":1, "effect":"move", "utility":true},
]

const PREP_PRESET_MAIN := [
	"quick_dash", "fire_drill", "evacuation", "fire_truck", "debris_clearance", "shelter_brace",
]
const PREP_PRESET_EXTRA := [
	"needle_team", "heavy_loader", "steam_team", "shard_barrier", "hazmat_team", "runner",
	"captain", "lane_marshal", "field_medic", "rescue_vamp", "tutor", "scout",
]
const DISASTER_PRESET_MAIN := [
	"ember", "tremor", "rising_tide", "gust", "cinder_cloud", "glass_quake",
	"toxic_runoff", "pressure_front", "crosswind", "fracture_hunter", "blocked_exit", "red_tape",
]
const DISASTER_PRESET_EVOLUTIONS := ["wildfire", "fissure", "flash_flood", "gale_force", "inferno", "tsunami"]

# =================================================================== POOLS
## Read one card json file into a list of definitions (no count, utility stats removed).
static func _load_file(path: String) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array: return cards
	for def: Dictionary in parsed:
		var card: Dictionary = def.duplicate()
		card.erase("count")
		BattleRules.remove_utility_stats(card)
		cards.append(card)
	return cards

## Card definitions a side may use, as {"base": {id: def}, "evolutions": {id: def}, "spells": {id: def}}.
## Preparedness has only "base". Disaster splits the way start_encounter does: cost > 0 is an evolution,
## cost 0 is a base card, and a utility base card is a spell.
static func pool(side: String) -> Dictionary:
	var result := {"base": {}, "evolutions": {}, "spells": {}}
	if side == SIDE_PREP:
		for path: String in PREP_FILES:
			for card in _load_file(path): result.base[card.id] = card
		for utility: Dictionary in PREP_UTILITIES: result.base[utility.id] = utility.duplicate()
	elif side == SIDE_DISASTER:
		for path: String in DISASTER_FILES:
			for card in _load_file(path):
				if int(card.get("cost", 0)) > 0: result.evolutions[card.id] = card
				elif card.get("utility", false): result.spells[card.id] = card
				else: result.base[card.id] = card
	return result

# =================================================================== RULES
## Count how many times each id appears in a list.
static func _count_ids(ids: Array) -> Dictionary:
	var counts := {}
	for id in ids: counts[id] = int(counts.get(id, 0)) + 1
	return counts

## Check one pile of ids: known ids only and at most MAX_COPIES of each.
static func _check_pile(ids: Array, allowed: Dictionary, label: String, errors: Array[String]) -> void:
	var counts := _count_ids(ids)
	for id in counts:
		if not allowed.has(id):
			errors.append("Unknown card id '%s' in %s" % [id, label])
		elif counts[id] > MAX_COPIES:
			errors.append("Card '%s' has %d copies in %s, max is %d" % [id, counts[id], label, MAX_COPIES])

## Brace plus exactly 2 other contingencies from contingency_rules.
static func _check_tactics(tactics: Array, errors: Array[String]) -> void:
	var known: Array[String] = []
	for tactic: Dictionary in ContingencyRules.TACTICS: known.append(tactic.id)
	if tactics.size() != 3:
		errors.append("Tactics need Brace plus exactly 2 others, has %d" % tactics.size())
	if "brace" not in tactics:
		errors.append("Tactics must include Brace")
	if _count_ids(tactics).size() != tactics.size():
		errors.append("Tactics must not repeat")
	for id in tactics:
		if id not in known: errors.append("Unknown tactic id '%s'" % id)

## Returns {"ok": bool, "errors": Array[String]}.
static func validate(side: String, deck: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var cards := pool(side)
	var main: Array = deck.get("main", [])
	if main.size() != MAIN_SIZE:
		errors.append("Main deck has %d cards, needs exactly %d" % [main.size(), MAIN_SIZE])
	if side == SIDE_PREP:
		_check_pile(main, cards.base, "main deck", errors)
		_check_tactics(deck.get("tactics", []), errors)
	elif side == SIDE_DISASTER:
		var allowed: Dictionary = cards.base.duplicate()
		allowed.merge(cards.spells)
		_check_pile(main, allowed, "main deck", errors)
		var evolutions: Array = deck.get("evolutions", [])
		if evolutions.size() != EVOLUTION_SIZE:
			errors.append("Evolution pile has %d cards, needs exactly %d" % [evolutions.size(), EVOLUTION_SIZE])
		_check_pile(evolutions, cards.evolutions, "evolution pile", errors)
	else:
		errors.append("Unknown side '%s'" % side)
	return {"ok": errors.is_empty(), "errors": errors}

# =================================================================== PRESETS
## One legal deck per side. Passes validate().
static func preset(side: String) -> Dictionary:
	var main: Array[String] = []
	if side == SIDE_PREP:
		for id: String in PREP_PRESET_MAIN: main.append_array([id, id])
		main.append_array(PREP_PRESET_EXTRA)
		return {"main": main, "evolutions": [], "tactics": ["brace", "coordinate", "medicine"]}
	if side == SIDE_DISASTER:
		for id: String in DISASTER_PRESET_MAIN: main.append_array([id, id])
		var evolutions: Array[String] = []
		evolutions.assign(DISASTER_PRESET_EVOLUTIONS)
		return {"main": main, "evolutions": evolutions, "tactics": []}
	return {}

# =================================================================== SAVED DECKS
## Custom decks file. Not the run save. Tests set their own path.
static var save_path := "user://versus_decks.cfg"

## The saved custom deck for a side. Missing file, broken file or a bad deck gives preset(side).
static func load_custom(side: String) -> Dictionary:
	var file := ConfigFile.new()
	if file.load(save_path) != OK: return preset(side)
	if not file.has_section_key("deck", side): return preset(side)
	var value: Variant = file.get_value("deck", side)
	if not value is Dictionary: return preset(side)
	var deck: Dictionary = value
	# A pile that is not an Array would break validate(), so check the shape first.
	for key: String in ["main", "evolutions", "tactics"]:
		if not deck.get(key, []) is Array: return preset(side)
	if not validate(side, deck).ok: return preset(side)
	return deck

## Save one side's custom deck. The other side's deck in the file stays.
static func save_custom(side: String, deck: Dictionary) -> void:
	var file := ConfigFile.new()
	if file.load(save_path) != OK: file = ConfigFile.new()
	file.set_value("deck", side, deck)
	file.save(save_path)
