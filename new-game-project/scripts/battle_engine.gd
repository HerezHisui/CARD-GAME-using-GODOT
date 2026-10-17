extends RefCounted
## Read-only rules. Inputs contain plain data supplied by the scene adapters.
const Rules = preload("res://scripts/battle_rules.gd")

const TYPE_CHART := {
	# Response attacking Disaster
	"evac": {"earthquake": 2.0, "flood": 0.5},
	"douse": {"fire": 2.0, "typhoon": 0.5},
	"clearance": {"flood": 2.0, "earthquake": 0.5},
	"brace": {"typhoon": 2.0, "fire": 0.5},
	# Disaster attacking Response
	"flood": {"evac": 2.0, "clearance": 0.5},
	"earthquake": {"clearance": 2.0, "evac": 0.5},
	"typhoon": {"douse": 2.0, "brace": 0.5},
	"fire": {"brace": 2.0, "douse": 0.5},
}

static func overclock_stacks(context: Dictionary, response: bool) -> int:
	var side: Dictionary = context["response" if response else "disaster"]
	return int(side.buffs.get("overclock", 0)) + int(side.run_buffs.get("overclock", 0))

static func buffs_for(context: Dictionary, definition: Dictionary) -> Dictionary:
	var side: Dictionary = context["response" if definition.get("type", "response") == "response" else "disaster"]
	return Rules.totals(side.buffs, side.run_buffs)

static func buff_value(context: Dictionary, response: bool, id: String) -> int:
	return int(buffs_for(context, {"type": "response" if response else "disaster"}).get(id, 0))

static func resource_growth(context: Dictionary, response: bool) -> int:
	return maxi(1, 1 + buff_value(context, response, "energy") - overclock_stacks(context, response))

static func incoming_damage(context: Dictionary, response: bool, amount: int) -> int:
	return ceili(amount * (1.0 + 0.5 * buff_value(context, response, "damage_taken")))

static func is_sealed(definition: Dictionary, round_number: int) -> bool:
	return int(definition.get("locked_until", 0)) > round_number

static func definition_has_modifier(definition: Dictionary, modifier: String) -> bool:
	return definition.get("modifier", "") == modifier or modifier in definition.get("modifiers", [])

static func has_modifier(context: Dictionary, card: Dictionary, mod_name: String) -> bool:
	var key := mod_name.to_lower()
	return key in card.modifiers or (not card.preview_only and key in ["piercing", "sluggish"]
		and int(buffs_for(context, card.card_data).get(key, 0)) > 0)

static func synergy_bonus(context: Dictionary, card: Dictionary) -> int:
	for ally in card.neighbors:
		if int(ally.get("health", 0)) > 0 and ally.element == card.card_data.element:
			return 1 + int(buffs_for(context, card.card_data).get("synergy", 0))
	return 0

static func attack_bonus(context: Dictionary, card: Dictionary) -> int:
	var buffs := buffs_for(context, card.card_data)
	var isolation := int(buffs.get("isolation", 0)) if card.on_board and synergy_bonus(context, card) == 0 else 0
	return int(buffs.get("strength", 0)) - isolation

static func effective_attack(context: Dictionary, card: Dictionary) -> int:
	if card.preview_only and card.card_data.has("preview_attack"):
		return int(card.card_data.preview_attack)
	var bonus := 0 if card.preview_only else attack_bonus(context, card)
	return maxi(0, int(card.card_data.get("attack", 0)) + int(card.statuses.get("strength", 0))
		+ int(card.plan_attack_bonus) + bonus)

static func adjusted_damage(context: Dictionary, card: Dictionary, amount: int) -> int:
	if has_modifier(context, card, "armored"):
		amount = maxi(1, amount - int(card.card_data.get("armor_value", 1)))
	if has_modifier(context, card, "fragile"):
		amount += 1
	return incoming_damage(context, card.card_data.type == "response", amount)

static func can_attack(context: Dictionary, card: Dictionary, round_number: int) -> bool:
	return int(card.card_data.get("health", 0)) > 0 and (not has_modifier(context, card, "sluggish")
		or int(card.last_attack_turn) < 0 or round_number - int(card.last_attack_turn) >= 2)

static func status_stacks(values: Variant, status: String) -> int:
	if values == null:
		return 0
	if status != "any":
		return int(values.get(status, 0))
	return int(values.get("burn", 0)) + int(values.get("poison", 0)) + int(values.get("bleed", 0))

static func condition_met(condition: Dictionary, source: Variant, target: Variant) -> bool:
	if condition.is_empty():
		return false
	var subject: Variant = source if condition.get("subject", "target") == "self" else target
	return subject != null and status_stacks(subject, str(condition.get("status", "any"))) >= int(
		condition.get("threshold", 3))

static func conditional_attack_bonus(attacker: Dictionary, defender: Variant) -> int:
	var condition: Dictionary = attacker.card_data.get("condition", {})
	var target: Variant = null if defender == null else defender.statuses
	var amount := int(condition.get("bonus", 0)) if condition_met(condition, attacker.statuses, target) else 0
	if defender != null and status_stacks(target, "any") >= 3:
		amount += int(attacker.card_data.get("status_bonus", 0))
	return amount

static func attack_strikes(attacker: Dictionary, defender: Variant) -> int:
	var condition: Dictionary = attacker.card_data.get("condition", {})
	var target: Variant = null if defender == null else defender.statuses
	return 2 if condition_met(condition, attacker.statuses, target) and int(condition.get("strikes", 1)) > 1 else 1

static func calc_damage(context: Dictionary, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var base := effective_attack(context, attacker) + conditional_attack_bonus(attacker, defender)
	var atk_elem: String = attacker.card_data.get("element", "")
	var def_elem: String = defender.card_data.get("element", "")
	var mult: float = TYPE_CHART.get(atk_elem, {}).get(def_elem, 1.0)
	var damage := maxi(1, int(base * mult)) + synergy_bonus(context, attacker)
	if has_modifier(context, attacker, "rampaging") and (
		(attacker.card_data.type == "response") != bool(context.player_first)):
		damage += 1
	return {"dmg": damage, "mult": mult}
