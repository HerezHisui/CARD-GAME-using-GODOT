extends RefCounted
## Who sits at each seat of the table: the room's figure at the far seat, the chosen leader at the near seat.
## The rows live in data/seat_figures.json. Constants and static functions only.

## Off until Simple has played it. Tests turn it on with game.seat_figures_override.
const SEAT_FIGURES_ENABLED := false
const DATA_PATH := "res://data/seat_figures.json"
const StandeeFigure = preload("res://scripts/standee_figure.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")
## The JSON, read once on first use.
static var data: Dictionary = {}

static func table() -> Dictionary:
	if data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: data = parsed
	return data

## A Dictionary override turns it on; else the flag decides.
## Versus has its own flag: the override needs "versus": true there, else VersusMatch.SEAT_FIGURES_VERSUS decides.
static func on(game: Node) -> bool:
	if game.encounter_kind == "versus":
		var override: Variant = game.seat_figures_override
		if override is Dictionary and override.get("versus", false) == true: return true
		return VersusMatch.SEAT_FIGURES_VERSUS
	if game.seat_figures_override is Dictionary: return true
	return SEAT_FIGURES_ENABLED

## Versus: the figure the player on this side picked. "" before the pick.
static func versus_figure(game: Node, side: String) -> String:
	var director: Node = game.run_director
	if not is_instance_valid(director) or not is_instance_valid(director.versus_match): return ""
	return director.versus_match.figure_for(side)

## The room row to read: the floor 3 boss room is "warden", else the encounter kind.
static func room(game: Node) -> String:
	if is_instance_valid(game.final_boss): return "warden"
	return game.encounter_kind

## The figure id for the far seat. "janitor" when off or when the room has no row.
static func far_id(game: Node) -> String:
	if not on(game): return "janitor"
	var override: Dictionary = game.seat_figures_override if game.seat_figures_override is Dictionary else {}
	if override.has("far"): return str(override.far)
	# Versus: the Disaster player's boss. None picked yet: the Janitor, as today.
	if game.encounter_kind == "versus":
		var boss := versus_figure(game, VersusMatch.VersusDecks.SIDE_DISASTER)
		return boss if boss != "" else "janitor"
	var row: Variant = table().get("rooms", {}).get(room(game))
	if row is Dictionary and row.has("figure"): return str(row.figure)
	return "janitor"

## The figure id for the near seat: the chosen leader. "" when off or when the row has no "leader" key.
static func near_id(game: Node) -> String:
	if not on(game): return ""
	var override: Dictionary = game.seat_figures_override if game.seat_figures_override is Dictionary else {}
	if override.has("near"): return str(override.near)
	# Versus: the Preparedness player's leader.
	if game.encounter_kind == "versus": return versus_figure(game, VersusMatch.VersusDecks.SIDE_PREP)
	var director: Node = game.run_director
	if not is_instance_valid(director): return ""
	var row: Dictionary = director.CHARACTERS[director.selected_character]
	return str(row.get("leader", ""))

## True when the id can be built: the kept Janitor model, or a standee with a cut-out.
static func usable(id: String) -> bool:
	return id == "janitor" or StandeeFigure.CUTS.has(id)

## Where the figure holds the card fan, in the standee's own units (x from the centre, y up from the centre).
## Vector2.INF when the figure has no "hand" row: the fan then stays where the Janitor holds it.
static func hand(id: String) -> Vector2:
	var row: Variant = table().get("figures", {}).get(id)
	if row is Dictionary and row.get("hand") is Array and row.hand.size() == 2:
		return Vector2(float(row.hand[0]), float(row.hand[1]))
	return Vector2.INF
