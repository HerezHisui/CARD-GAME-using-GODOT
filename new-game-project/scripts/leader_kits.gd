extends RefCounted
## Leader kits: data only. A kit replaces Plans for one leader's singleplayer runs.
## The rules for each "does" verb live in contingency_rules.gd.

# Robin's kit stays off until it has been played. Tests turn it on with game.leader_kit_override.
const ROBIN_ENABLED := false
# Sage's kit stays off until it has been played.
const SAGE_ENABLED := false
# Kai's kit stays off until it has been played.
const KAI_ENABLED := false

const KITS := {
	"robin": {
		"name": "AID KIT", "charge": "Aid", "cap": 2, "bank": "standard", "save_once": true,
		# Supplies at the start of a run.
		"supplies": 30,
		"subtitle": "Save 2 unused energy at End Turn for 1 Aid. Aid goes to your weakest unit.",
		"reward_title": "NEW AID", "reward_subtitle": "Add one to your kit for this run.",
		"start": ["patch_up", "cover"],
		"effects": [
			{"id":"patch_up", "name":"Patch Up", "cost":1, "does":"heal", "amount":3, "target":"weakest",
				"when":"now", "description":"Heal your weakest unit 3."},
			{"id":"cover", "name":"Cover", "cost":1, "does":"guard", "amount":2, "target":"weakest",
				"when":"combat", "description":"Your weakest unit blocks 2 from the next hit."},
			{"id":"clean_up", "name":"Clean Up", "cost":1, "does":"cleanse", "amount":3, "target":"weakest_status",
				"when":"now", "description":"Clear all statuses from one unit. Heal it 3."},
			{"id":"rescue", "name":"Rescue", "cost":2, "does":"recover", "amount":1, "target":"none",
				"when":"now", "description":"Take back your last destroyed unit. It goes to your hand."},
			{"id":"safe_room", "name":"Safe Room", "cost":1, "does":"hero_block", "amount":3, "target":"none",
				"when":"combat", "description":"Your HP blocks 3 this fight."},
		],
	},
	"sage": {
		"name": "THE LAB", "charge": "Sample", "cap": 2, "bank": "standard",
		# Supplies at the start of a run.
		"supplies": 40,
		# Eureka: Burn, Poison and Bleed on one enemy unit clear and deal this much, armor ignored.
		"eureka": 6,
		"subtitle": "Save 2 unused energy at End Turn for 1 Sample. Burn + Poison + Bleed on one enemy = Eureka.",
		"reward_title": "NEW EXPERIMENT", "reward_subtitle": "Add one to your kit for this run.",
		"start": ["nick", "drip"],
		"effects": [
			{"id":"nick", "name":"Nick", "cost":1, "does":"status", "status":"bleed", "amount":2, "target":"enemy",
				"when":"now", "description":"Give one enemy 2 Bleed."},
			{"id":"drip", "name":"Drip", "cost":1, "does":"status", "status":"poison", "amount":2, "target":"enemy",
				"when":"now", "description":"Give one enemy 2 Poison."},
			{"id":"spark", "name":"Spark", "cost":1, "does":"status", "status":"burn", "amount":2, "target":"enemy",
				"when":"now", "description":"Give one enemy 2 Burn."},
			{"id":"fume_hood", "name":"Fume Hood", "cost":1, "does":"hero_block", "amount":3, "target":"none",
				"when":"combat", "description":"Your HP blocks 3 this fight."},
			{"id":"lab_notes", "name":"Lab Notes", "cost":1, "does":"draw", "amount":1, "target":"none",
				"when":"combat", "description":"Draw 1 when the fight starts."},
		],
	},
	"kai": {
		"name": "THE DRILL", "charge": "Tempo", "cap": 3, "bank": "none",
		# Supplies at the start of a run.
		"supplies": 35,
		# Tempo for each of your units that changes lane.
		"tempo_on_move": 1,
		"subtitle": "Each unit that changes lane gives 1 Tempo. Unused energy is not saved.",
		"reward_title": "NEW FORMATION", "reward_subtitle": "Add one to your kit for this run.",
		"start": ["fall_in", "double_time"],
		"effects": [
			{"id":"fall_in", "name":"Fall In", "cost":0, "does":"move", "amount":1, "target":"ally_to_lane",
				"when":"now", "description":"Move one unit to an empty lane."},
			{"id":"double_time", "name":"Double Time", "cost":2, "does":"energy", "amount":2, "target":"none",
				"when":"now", "description":"Get 2 energy back."},
			{"id":"lane_swap", "name":"Lane Swap", "cost":1, "does":"swap", "amount":0, "target":"two_allies",
				"when":"now", "description":"Two neighbours trade lanes."},
			{"id":"rally", "name":"Rally", "cost":2, "does":"attack_adjacent", "amount":1, "target":"ally",
				"when":"combat", "description":"One unit and its neighbours get +1 attack this fight."},
			{"id":"duck", "name":"Duck", "cost":1, "does":"extract", "amount":0, "target":"ally_to_lane",
				"when":"combat", "description":"One unit dodges a killing hit into an empty lane."},
		],
	},
}

## The kit by id, or {} when there is none.
static func kit(id: String) -> Dictionary:
	return KITS.get(id, {})

## One effect row of a kit, or {}.
static func effect(kit_id: String, effect_id: String) -> Dictionary:
	for row in kit(kit_id).get("effects", []):
		if row.id == effect_id: return row
	return {}

## A String override picks that leader (tests only). Otherwise the leader's own flag decides.
static func leader_on(leader: String, override: Variant) -> bool:
	if override is String: return leader == override
	if leader == "robin": return ROBIN_ENABLED
	if leader == "sage": return SAGE_ENABLED
	if leader == "kai": return KAI_ENABLED
	return false
