extends RefCounted
## Detached battle data. Live scenes remain authoritative during the migration.

var sides: Dictionary = {}
var cards: Dictionary = {}
var lanes: Dictionary = {"response": ["", "", "", ""], "disaster": ["", "", "", ""]}
var zones: Dictionary = {
	"response": {"hand": [], "draw": [], "evolution": [], "graveyard": []},
	"disaster": {"hand": [], "draw": [], "evolution": [], "graveyard": []},
}
var round_number := 1
var phase := 0
var first_side := "response"
var encounter_kind := "battle"
var floor_number := 1
var actions_used := -1
var adapted_round := 0
var result := ""
var coin: Dictionary = {"result": -1, "pick": -1}
var pending_choice: Dictionary = {}
var plans: Dictionary = {}
var boss: Dictionary = {}
var battle_log: Array = []
var graveyard_serial := 0
var next_card_id := 1
var rng_state := ""
var run_rng_state := ""

const FIELDS := [
	"sides", "cards", "lanes", "zones", "round_number", "phase", "first_side", "encounter_kind",
	"floor_number", "actions_used", "adapted_round", "result", "coin", "pending_choice", "plans", "boss",
	"battle_log", "graveyard_serial", "next_card_id", "rng_state", "run_rng_state",
]

func add_card(definition: Dictionary, runtime: Dictionary = {}) -> String:
	assert(is_plain_data(definition) and is_plain_data(runtime), "Card data must be serializable")
	var id := "card_%d" % next_card_id
	next_card_id += 1
	cards[id] = {"definition": copy_data(definition), "runtime": copy_data(runtime)}
	return id

func to_dict() -> Dictionary:
	var snapshot: Dictionary = {}
	for field in FIELDS:
		var value: Variant = get(field)
		assert(is_plain_data(value), "Battle state must contain only serializable data")
		snapshot[field] = copy_data(value)
	return snapshot

func load_snapshot(snapshot: Dictionary) -> void:
	assert(is_plain_data(snapshot), "Snapshot must contain only serializable data")
	for field in FIELDS:
		if not snapshot.has(field):
			continue
		var value: Variant = snapshot[field]
		var existing: Variant = get(field)
		if existing is int:
			set(field, int(value))
		else:
			set(field, copy_data(value))

static func copy_data(value: Variant) -> Variant:
	# JSON uses string keys and parses numbers as floats; canonicalize integral values on both sides.
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = copy_data(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(copy_data(item))
		return result
	if value is StringName:
		return str(value)
	if value is float and value == floor(value):
		return int(value)
	return value

static func is_plain_data(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName or key is int) or not is_plain_data(value[key]):
				return false
		return true
	if value is Array:
		for item in value:
			if not is_plain_data(item):
				return false
		return true
	return value == null or value is bool or value is int or value is float or value is String or value is StringName
