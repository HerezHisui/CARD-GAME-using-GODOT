extends RefCounted

const SORT_KEYS := ["name", "element", "cost", "attack", "health", "modifier", "acquired"]

static func sorted_indices(cards: Array, key_index: int, descending: bool) -> Array:
	var indices: Array = range(cards.size())
	var key: String = SORT_KEYS[key_index]
	indices.sort_custom(func(a: int, b: int) -> bool:
		var left: Variant = cards[a].get(key, "")
		var right: Variant = cards[b].get(key, "")
		var comparison := 0
		if key == "acquired":
			left = int(cards[a].get(key, a))
			right = int(cards[b].get(key, b))
			comparison = -1 if int(left) > int(right) else (1 if int(left) < int(right) else 0)
		elif key in ["cost", "attack", "health"]:
			comparison = -1 if int(left) < int(right) else (1 if int(left) > int(right) else 0)
		else:
			comparison = str(left).naturalnocasecmp_to(str(right))
		if comparison == 0: return a < b
		return comparison > 0 if descending else comparison < 0
	)
	return indices

static func shop_price(card: Dictionary) -> int:
	var power := int(card.get("cost", 0)) + int(card.get("attack", 0)) + int(card.get("health", 1))
	power += int(card.get("strength", 0)) + int(card.get("leech", 0))
	if card.has("condition"): power += 3
	for amount in card.get("on_hit", {}).values(): power += int(amount)
	if card.get("modifier", "") == "sluggish": power -= 3
	elif card.get("modifier", "") != "": power += 2
	if card.get("effect", "") in ["draw", "rally_all", "heal_all"]: power += 2
	return 20 if power <= 5 else (30 if power <= 9 else (40 if power <= 13 else 50))

static func upgrade_level(card: Dictionary) -> int:
	return int(card.get("upgrades", str(card.get("name", "")).count("+")))

static func can_upgrade(card: Dictionary, max_upgrades: int) -> bool:
	return upgrade_level(card) < max_upgrades
