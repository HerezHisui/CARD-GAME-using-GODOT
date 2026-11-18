extends RefCounted
## Who sits at each seat of the table: the room's figure at the far seat, the chosen leader at the near seat.
## The rows live in data/seat_figures.json. Constants and static functions only.

## Off until Simple has played it. Tests turn it on with game.seat_figures_override.
const SEAT_FIGURES_ENABLED := false
const DATA_PATH := "res://data/seat_figures.json"
const StandeeFigure = preload("res://scripts/standee_figure.gd")
## The JSON, read once on first use.
static var data: Dictionary = {}

static func table() -> Dictionary:
	if data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: data = parsed
	return data

## Never in Versus. A Dictionary override turns it on; else the flag decides.
static func on(game: Node) -> bool:
	if game.encounter_kind == "versus": return false
	if game.seat_figures_override is Dictionary: return true
	return SEAT_FIGURES_ENABLED

## The room row to read: the floor 3 boss room is "warden", else the encounter kind.
static func room(game: Node) -> String:
	if is_instance_valid(game.final_boss): return "warden"
	return game.encounter_kind

## The figure id for the far seat. "janitor" when off or when the room has no row.
static func far_id(game: Node) -> String:
	if not on(game): return "janitor"
	var override: Dictionary = game.seat_figures_override if game.seat_figures_override is Dictionary else {}
	if override.has("far"): return str(override.far)
	var row: Variant = table().get("rooms", {}).get(room(game))
	if row is Dictionary and row.has("figure"): return str(row.figure)
	return "janitor"

## The figure id for the near seat: the chosen leader. "" when off or when the row has no "leader" key.
static func near_id(game: Node) -> String:
	if not on(game): return ""
	var override: Dictionary = game.seat_figures_override if game.seat_figures_override is Dictionary else {}
	if override.has("near"): return str(override.near)
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
