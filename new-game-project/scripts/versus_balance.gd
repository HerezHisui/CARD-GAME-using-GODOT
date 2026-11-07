extends RefCounted
## Local human Versus overrides. Source card data and other modes remain unchanged.

const OVERRIDES := {
	"alarm_sweep": {"blast_damage": 1},
	"ember": {"tension_cost": 1}, "tremor": {"tension_cost": 1},
	"rising_tide": {"tension_cost": 1}, "gust": {"tension_cost": 1},
	"toxic_runoff": {"tension_cost": 1}, "crosswind": {"tension_cost": 1},
	"warm_front": {"tension_cost": 1}, "fracture_hunter": {"tension_cost": 1},
	"red_tape": {"tension_cost": 1}, "cinder_cloud": {"tension_cost": 2},
	"glass_quake": {"tension_cost": 2}, "pressure_front": {"tension_cost": 2},
	"blocked_exit": {"tension_cost": 2}, "quick_dash": {"relocation_attack": 1},
	"needle_team": {"element": "clearance"}, "lane_marshal": {"attack": 2},
	"rescue_crane": {"cost": 3}, "scout": {"cost": 1},
}
const THRESHOLDS := {
	"ash_predator": 2, "venom_surge": 1, "fracture_hunter": 2,
	"heat_seeker": 1, "last_responder": 1, "containment_lance": 2,
	# Discord fix: 3 combined stacks on the lane target almost never survive the round-end decay.
	"toxin_hunter": 2,
}
const ORDINARY_BASES := {"ember": "fire", "tremor": "earthquake", "rising_tide": "flood", "gust": "typhoon"}

static func enabled(game: Node) -> bool:
	if game.encounter_kind != "versus" or not game.disaster_is_human: return false
	return requested(game)

static func requested(game: Node) -> bool:
	if game.lan_remote_prep or game.lan_remote_disaster: return false
	if game.balance_patch_override is bool: return game.balance_patch_override
	return preload("res://scripts/versus_match.gd").BALANCE_PATCH

static func card(definition: Dictionary, active: bool) -> Dictionary:
	var result := definition.duplicate(true)
	if active:
		var id := str(result.get("id", ""))
		result.merge(OVERRIDES.get(id, {}), true)
		if id in THRESHOLDS and result.has("condition"): result.condition.threshold = THRESHOLDS[id]
	return result

static func tension_cap(round_number: int) -> int:
	return 3 if round_number <= 2 else (4 if round_number <= 5 else 5)

static func matching_barrier(definition: Dictionary, materials: Array) -> int:
	if int(definition.get("cost", 0)) < 2: return 0
	var matching := 0
	for material: Dictionary in materials:
		var id := str(material.get("id", ""))
		if id in ORDINARY_BASES and ORDINARY_BASES[id] == definition.get("element", ""):
			matching += 1
	return 1 if matching >= 2 else 0
