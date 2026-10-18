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
	{"id":"glass", "name":"Glass Cannon", "description":"Future units gain +2 attack, but -1 maximum health. Deployed units are unchanged. This battle only."},
	{"id":"overclock", "name":"Overclock", "description":"Gain 2 capacity now and +1 extra capacity growth each round (2 total normally), but take 50% more damage (rounded up)."},
	{"id":"blood_pact", "name":"Blood Pact", "description":"Units gain 2 Strength. At combat end, each deployed unit that did not kill a card this combat dies. Hero hits and resting do not count."},
	{"id":"patient", "name":"Patient Formation", "description":"All units regenerate 2 each round, but become Sluggish."},
	{"id":"toxic_ward", "name":"Toxic Ward", "description":"Apply 2 extra Poison stacks, but all your units lose 1 attack."},
	{"id":"formation", "name":"Close Ranks", "description":"Matching adjacent units deal 2 extra damage. Isolated deployed units lose 1 attack."},
	{"id":"spines", "name":"Bristling Defense", "description":"Future units retaliate for 1 fixed damage after surviving a block, but lose 1 maximum health. Deployed units are unchanged."},
	{"id":"precision", "name":"Piercing Formation", "description":"All units gain Piercing, but lose 1 attack."}
]
const RUN_BUFFS := [
	{"id":"beacon", "name":"Signal Beacon", "description":"PERMANENT: draw 1 extra card in normal draw phases."},
	{"id":"bulwark", "name":"School Bulwark", "description":"PERMANENT: units gain 2 maximum health, but lose 1 attack."},
	{"id":"glass", "name":"Bold Strategy", "description":"PERMANENT: future units gain 2 attack, but lose 1 maximum health. Deployed units are unchanged."},
	{"id":"field_school", "name":"Field School", "description":"PERMANENT: +1 resources and +1 normal draw. Future units lose 1 maximum health; deployed units are unchanged."},
	{"id":"hazard_manual", "name":"Hazard Manual", "description":"PERMANENT: apply +2 Burn, +1 Poison, +1 Bleed, but lose 1 resource capacity."},
	{"id":"formation", "name":"Buddy System", "description":"PERMANENT: matching neighbors deal 2 extra damage; isolated deployed units lose 1 attack."},
	{"id":"medical", "name":"Infirmary Network", "description":"PERMANENT: heal your side's health by 1 each round, but units lose 1 attack."},
	{"id":"spines", "name":"Jagged Barricades", "description":"PERMANENT: future units retaliate for 1 fixed damage after surviving a block, but lose 1 maximum health. Deployed units are unchanged."}
]
const CHARACTER_BUFFS := [
	{"id":"drill_tactics", "name":"Rooftop Preparation"},
	{"id":"cadet", "name":"Student Training"}, {"id":"marshal", "name":"Route Formation"},
	{"id":"chemist", "name":"Chemical Expertise"}, {"id":"warden", "name":"Barricade Doctrine"}
]
const BONUSES := {
	"cadet":{"health":1}, "marshal":{"synergy":1},
	"chemist":{"burn":1, "poison":1, "health":-1}, "warden":{"thorns":1},
	"glass":{"strength":2, "health":-1}, "overclock":{"energy":2, "damage_taken":1},
	"blood_pact":{"strength":2, "kill_or_die":1}, "patient":{"regen":2, "sluggish":1},
	"toxic_ward":{"poison":2, "strength":-1}, "formation":{"synergy":2, "isolation":1},
	"spines":{"thorns":1, "health":-1}, "precision":{"piercing":1, "strength":-1},
	"beacon":{"draw":1}, "bulwark":{"health":2, "strength":-1},
	"field_school":{"energy":1, "draw":1, "health":-1},
	"hazard_manual":{"burn":1, "poison":1, "bleed":1, "energy":-1},
	"medical":{"hero_regen":1, "strength":-1}, "drill_tactics":{"plan_start":1, "energy":-1}
}

static func totals(battle: Dictionary, permanent: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for source in [battle, permanent]:
		for id in source:
			var effects: Dictionary = BONUSES.get(id, {id:1})
			for effect in effects: result[effect] = int(result.get(effect, 0)) + int(effects[effect]) * int(source[id])
	return result
const EFFECTS := {
	"delay":"Deadweight: spend the listed energy to discard this card. No other effect.",
	"blast":"Deal 2 fixed damage to every enemy unit, bypassing Taunt. Armor and barriers still apply.",
	"barrier":"All deployed allies gain 2 Barrier. Your health pool also gains 2 Barrier. Blocks attack damage, not periodic statuses.",
	"herb":"Remove Bleed from all deployed allies and heal each by 1.",
	"tablet":"Remove Healing Reduced from all deployed allies and heal each by 2.",
	"draw":"Draw extra cards, up to the hand limit.",
	"move":"Drag a deployed ally onto an empty Response slot.",
	"tutor":"Choose an unlocked card from your draw pile and put it into your hand.",
	"seal":"Choose a card currently in the opposing hand. Seal it for this round and the next: it cannot be played. Draw piles and deployed units cannot be sealed.",
	"scout":"Reveal the Janitor's hand for the rest of this encounter. Inspect it again through the deck viewer.",
	"tax":"Choose an opposing hand card, including a held evolution. Response energy cost +1; Disaster sacrifice cost +1, or base-card tension cost +1. Expires after this round and the next; repeated taxes cap at +2.",
	"rally":"Choose a deployed ally. It gains 2 Strength (+2 attack) for this encounter.",
	"cleanse":"Choose a deployed ally. Heal 3 and remove Burn, Poison, and Bleed.",
	"recover":"Return a destroyed Response unit from your graveyard to your hand. It must be played again at its normal cost. Temporary statuses and taxes are cleared. Each unit can be recovered once per battle.",
	"grave_guard":"On play: gain 1 Barrier per destroyed allied unit still in your graveyard, up to 2."
}
const EFFECT_LABELS := {"delay":"Discard deadweight", "blast":"Area damage", "barrier":"Protect formation", "herb":"Clear Bleed", "tablet":"Restore healing", "draw":"Draw cards", "move":"Relocate ally", "tutor":"Search draw pile", "seal":"Seal card", "scout":"Reveal hand", "tax":"Raise cost", "rally":"Gain Strength", "cleanse":"Heal and cleanse", "recover":"Recover a unit", "grave_guard":"Graveyard protection"}

static func modifier_text(card: Dictionary, modifier: String) -> String:
	var descriptions := {
		"armored":"Armored: reduce ordinary damage by %d (minimum 1). Stops Piercing hero damage; Piercing ignores this armor reduction." % int(card.get("armor_value", 1)),
		"fragile":"Fragile: take 1 extra ordinary damage.",
		"regenerating":"Regenerating: heal 1 at upkeep.",
		"rampaging":"Rampaging: +1 unit damage when attacking second.",
		"fierce":"Fierce: +2 direct hero damage.",
		"piercing":"Piercing: ignore a blocker's armor reduction and also hit opposing health, unless the blocker is Armored. Barriers still apply.",
		"sluggish":"Sluggish: attacks immediately, then rests every other round."
	}
	return str(descriptions.get(modifier, modifier.capitalize()))

static func special_text(card: Dictionary) -> String:
	var parts: PackedStringArray = []
	if int(card.get("strength", 0)) > 0: parts.append("Starts with %d Strength." % int(card.strength))
	if card.get("recovered", false): parts.append("Recovered: this unit cannot be recovered again this battle.")
	if card.get("on_sacrifice", "") == "draw": parts.append("When sacrificed: draw 1 Disaster card.")
	if card.get("on_sacrifice", "") == "burn": parts.append("When sacrificed: apply 2 Burn to the opposing lane card.")
	if card.get("type", "response") == "disaster" and int(card.get("cost", 0)) >= 3:
		parts.append("On evolution: gain %d Barrier and draw 1." % (3 if int(card.cost) >= 4 else 2))
		if int(card.cost) >= 4: parts.append("On evolution: deal 1 fixed damage to each enemy unit.")
	if int(card.get("move_heal", 0)) > 0: parts.append("Relocated ally heals %d." % int(card.move_heal))
	if card.get("ignore_taunt", false): parts.append("Ignore Taunt: strike your lane target through a guardian.")
	if card.get("curse", false): parts.append("Pay 1 HP when cast or at round end; casting draws 1 card.")
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
			"blast": parts.append("Deal %d to all enemy units." % (2 + power))
			"barrier": parts.append("Grant %d Barrier to allies and your health pool." % (2 + power))
			"herb": parts.append("Remove Bleed and heal each ally %d." % (1 + power))
			"tablet": parts.append("Restore healing and heal each ally %d." % (2 + power))
	if int(card.get("refund_energy", 0)) > 0: parts.append("Refund %d energy after casting." % int(card.refund_energy))
	if card.has("condition"):
		var trigger: Dictionary = card.condition
		var who := "Self" if trigger.get("subject", "target") == "self" else "Target"
		var status := "harmful status" if trigger.get("status", "any") == "any" else str(trigger.status).capitalize()
		var reward := "attack twice" if int(trigger.get("strikes", 1)) > 1 else "+%d attack" % int(trigger.get("bonus", 0))
		parts.append("%s has %d+ %s stacks: %s." % [who, int(trigger.get("threshold", 3)), status, reward])
	return "\n".join(parts)
