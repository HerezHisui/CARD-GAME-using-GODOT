extends RefCounted
## Shared card label text for the LAN client and Preparedness panels.


# Name plus attack and health, or "-" for an empty lane.
static func card_text(view: Dictionary, id: String) -> String:
	if id == "" or not view.cards.has(id):
		return "-"
	var definition: Dictionary = view.cards[id].definition
	if definition.get("utility", false):
		return str(definition.get("name", "?"))
	return "%s %d/%d" % [definition.get("name", "?"), definition.get("attack", 0), definition.get("health", 0)]
