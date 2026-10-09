extends RefCounted
## Shared descriptions and balanced buff offers for both sides.
const BUFF_INTERVAL := 5
const BUFFS := [
	{"id":"strength", "name":"Stronger Together", "description":"All your units gain +1 attack for this battle."},
	{"id":"health", "name":"Reinforced Formation", "description":"All your units gain +1 maximum health and heal 1. Future units also benefit."},
	{"id":"energy", "name":"Resource Surge", "description":"Response: extra energy cap and growth. Disaster: extra tension and one extra action (max 5)."},
	{"id":"burn", "name":"Fuel the Flames", "description":"Your cards apply 2 extra Burn stacks whenever they inflict Burn."},
	{"id":"poison", "name":"Toxic Pressure", "description":"Your cards apply 1 extra Poison stack whenever they inflict Poison."},
	{"id":"bleed", "name":"Deep Cuts", "description":"Your cards apply 1 extra Bleed stack whenever they inflict Bleed."},
	{"id":"draw", "name":"Rapid Logistics", "description":"Draw 1 extra card in each normal draw phase, up to the hand limit."},
	{"id":"glass", "name":"Glass Cannon", "description":"+2 attack to all units, but -1 maximum health. This battle only."},
	{"id":"overclock", "name":"Overclock", "description":"+2 resource capacity/growth, but draw 1 fewer card in normal draw phases."},
	{"id":"blood_pact", "name":"Blood Pact", "description":"+3 attack, but all units gain 2 Bleed when you choose this and when they enter."},
	{"id":"patient", "name":"Patient Formation", "description":"All units regenerate 2 each round, but become Sluggish."},
	{"id":"toxic_ward", "name":"Toxic Ward", "description":"Apply 2 extra Poison stacks, but all your units lose 1 attack."},
	{"id":"formation", "name":"Close Ranks", "description":"Matching adjacent units deal 2 extra damage. Isolated deployed units lose 1 attack."},
	{"id":"spines", "name":"Bristling Defense", "description":"Surviving blockers retaliate for 1 fixed damage, but all units lose 1 maximum health."},
	{"id":"precision", "name":"Piercing Formation", "description":"All units gain Piercing, but lose 1 attack."}
]
const RUN_BUFFS := [
	{"id":"beacon", "name":"Signal Beacon", "description":"PERMANENT: draw 1 extra card in normal draw phases."},
	{"id":"bulwark", "name":"School Bulwark", "description":"PERMANENT: units gain 2 maximum health, but lose 1 attack."},
	{"id":"glass", "name":"Bold Strategy", "description":"PERMANENT: units gain 2 attack, but lose 1 maximum health."},
	{"id":"field_school", "name":"Field School", "description":"PERMANENT: +1 resources and +1 normal draw, but units lose 1 maximum health."},
	{"id":"hazard_manual", "name":"Hazard Manual", "description":"PERMANENT: apply +2 Burn, +1 Poison, +1 Bleed, but lose 1 resource capacity."},
	{"id":"formation", "name":"Buddy System", "description":"PERMANENT: matching neighbors deal 2 extra damage; isolated deployed units lose 1 attack."},
	{"id":"medical", "name":"Infirmary Network", "description":"PERMANENT: heal your side's health by 1 each round, but units lose 1 attack."},
	{"id":"spines", "name":"Jagged Barricades", "description":"PERMANENT: surviving blockers retaliate for 1 fixed damage, but units lose 1 maximum health."}
]
const CHARACTER_BUFFS := [
	{"id":"cadet", "name":"Cadet Training"}, {"id":"marshal", "name":"Route Formation"},
	{"id":"chemist", "name":"Chemical Expertise"}, {"id":"warden", "name":"Barricade Doctrine"}
]
const BONUSES := {
	"cadet":{"health":1}, "marshal":{"synergy":1},
	"chemist":{"burn":1, "poison":1, "health":-1}, "warden":{"thorns":1},
	"glass":{"strength":2, "health":-1}, "overclock":{"energy":2, "draw":-1},
	"blood_pact":{"strength":3, "self_bleed":2}, "patient":{"regen":2, "sluggish":1},
	"toxic_ward":{"poison":2, "strength":-1}, "formation":{"synergy":2, "isolation":1},
	"spines":{"thorns":1, "health":-1}, "precision":{"piercing":1, "strength":-1},
	"beacon":{"draw":1}, "bulwark":{"health":2, "strength":-1},
	"field_school":{"energy":1, "draw":1, "health":-1},
	"hazard_manual":{"burn":1, "poison":1, "bleed":1, "energy":-1},
	"medical":{"hero_regen":1, "strength":-1}
}

static func totals(battle: Dictionary, permanent: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for source in [battle, permanent]:
		for id in source:
			var effects: Dictionary = BONUSES.get(id, {id:1})
			for effect in effects: result[effect] = int(result.get(effect, 0)) + int(effects[effect]) * int(source[id])
	return result
const EFFECTS := {
	"draw":"Draw extra cards, up to the hand limit.",
	"move":"Move the nearest deployed ally to the empty slot you target.",
	"tutor":"Choose an unlocked card from your draw pile and put it into your hand.",
	"seal":"Choose an opposing draw-pile, evolution, or hand card. Seal it for this round and the next: it cannot be drawn or played.",
	"scout":"Reveal the Janitor's hand for the rest of this encounter. Inspect it again through the deck viewer.",
	"tax":"Choose an opposing hand or evolution card. Response energy cost +1; Disaster sacrifice cost +1, or base-card tension cost +1. Lasts this encounter.",
	"rally":"Choose a deployed ally. It gains 2 Strength (+2 attack) for this encounter.",
	"cleanse":"Choose a deployed ally. Heal 3 and remove Burn, Poison, and Bleed."
}
const EFFECT_LABELS := {"draw":"Draw cards", "move":"Relocate ally", "tutor":"Search draw pile", "seal":"Seal card", "scout":"Reveal hand", "tax":"Raise cost", "rally":"Gain Strength", "cleanse":"Heal and cleanse"}

static func special_text(card: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(card.get("armor_value", 1)) > 1: parts.append("Armor: reduce attack damage by %d (minimum 1)." % int(card.armor_value))
	if int(card.get("on_play_draw", 0)) > 0: parts.append("On play: draw %d extra." % int(card.on_play_draw))
	if int(card.get("thorns", 0)) > 0: parts.append("Surviving blocks retaliate for %d." % int(card.thorns))
	if int(card.get("status_bonus", 0)) > 0: parts.append("+%d attack vs targets with 3+ harmful status stacks." % int(card.status_bonus))
	if int(card.get("utility_power", 0)) > 0:
		var power := int(card.utility_power)
		match str(card.get("effect", "")):
			"draw": parts.append("Draw %d total." % (2 + power))
			"seal": parts.append("Seal for %d rounds." % (2 + power))
			"tax": parts.append("Raise cost by %d." % (1 + power))
			"rally": parts.append("Grant %d Strength." % (2 + power))
			"cleanse": parts.append("Cleanse and heal %d." % (3 + 2 * power))
	if int(card.get("refund_energy", 0)) > 0: parts.append("Refund %d energy after casting." % int(card.refund_energy))
	if card.has("condition"):
		var trigger: Dictionary = card.condition
		var who := "Self" if trigger.get("subject", "target") == "self" else "Target"
		var status := "harmful status" if trigger.get("status", "any") == "any" else str(trigger.status).capitalize()
		var reward := "attack twice" if int(trigger.get("strikes", 1)) > 1 else "+%d attack" % int(trigger.get("bonus", 0))
		parts.append("%s has %d+ %s stacks: %s." % [who, int(trigger.get("threshold", 3)), status, reward])
	return "\n".join(parts)
