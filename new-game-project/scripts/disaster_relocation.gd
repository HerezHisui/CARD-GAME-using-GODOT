extends RefCounted
## The host owns a human Crosswind choice. Client messages only name lanes in that choice.
const Sfx = preload("res://scripts/sfx_call.gd")
var game: Node
var source: Node
var encounter := -1
var choice := 0

func _init(owner_game: Node) -> void:
	game = owner_game

func reset() -> void:
	source = null
	encounter = -1
	if is_instance_valid(game.run_director) and game.run_director.screen == "disaster_relocation":
		game.run_director.close_modal()

func _allies() -> Array:
	var lanes: Array = []
	var slots: Array = game._threat_slots()
	for lane in slots.size():
		var card = game._get_card_in_slot(slots[lane])
		if is_instance_valid(card) and card != source and card.is_alive(): lanes.append(lane)
	return lanes

func _destinations() -> Array:
	var lanes: Array = []
	var slots: Array = game._threat_slots()
	for lane in slots.size():
		if game._get_card_in_slot(slots[lane]) == null: lanes.append(lane)
	return lanes

func pending() -> bool:
	if source == null: return false
	if not is_instance_valid(source) or source.is_queued_for_deletion():
		reset()
		return false
	if encounter != game.encounter_serial or game.phase != game.Phase.ENEMY \
			or game.encounter_kind != "versus" or not game.disaster_is_human:
		reset()
		return false
	if source.current_slot not in game._threat_slots() or not source.is_alive() \
			or game._get_card_in_slot(source.current_slot) != source \
			or _allies().is_empty() or _destinations().is_empty():
		reset()
		return false
	return true

func begin(card: Node) -> void:
	reset()
	source = card
	encounter = game.encounter_serial
	choice += 1
	pending()

func view() -> Dictionary:
	if not pending(): return {}
	return {"choice": choice, "encounter": encounter, "source": game._threat_slots().find(source.current_slot),
		"allies": _allies(), "destinations": _destinations()}

func pick(msg: Dictionary) -> Dictionary:
	if not pending(): return {"ok": false, "reason": "no_relocation"}
	for field in ["encounter", "choice", "ally", "lane"]:
		if typeof(msg.get(field)) != TYPE_INT: return {"ok": false, "reason": "bad_message"}
	if msg.encounter != encounter or msg.choice != choice:
		return {"ok": false, "reason": "stale_relocation"}
	if game.disaster_actions.busy: return {"ok": false, "reason": "busy"}
	if msg.ally not in _allies() or msg.lane not in _destinations():
		return {"ok": false, "reason": "bad_lane"}
	var slots: Array = game._threat_slots()
	var ally: Node = game._get_card_in_slot(slots[msg.ally])
	# Same move step as a Preparedness relocation. The AI Crosswind plays the same sound.
	game.apply_relocation(ally, slots[msg.lane], source)
	Sfx.play("relocation")
	game.log_event("Crosswind moves %s to lane %d." % [ally.card_data.name, msg.lane + 1])
	reset()
	return {"ok": true, "reason": ""}

func refresh_local() -> void:
	if not pending() or game.lan_remote_disaster or game.disaster_actions.busy: return
	if game.run_director.screen == "": show_local()

func show_local(ally: int = -1) -> void:
	if not pending() or game.lan_remote_disaster: return
	var director: Node = game.run_director
	if ally not in _allies(): ally = -1
	var title := "CROSSWIND: CHOOSE AN ALLY" if ally < 0 else "CROSSWIND: CHOOSE AN EMPTY LANE"
	director.reset_panel(title, "Move another Disaster card. No extra Tension or action cost.", "disaster_relocation")
	var lanes: Array = _allies() if ally < 0 else _destinations()
	for lane in lanes:
		var card: Node = game._get_card_in_slot(game._threat_slots()[lane])
		var text := "Lane %d" % (lane + 1)
		if card != null: text += " · " + str(card.card_data.name)
		director.button(text, _local_pick.bind(lane, ally, choice, encounter), director.content)
	game.get_tree().paused = false

func _local_pick(lane: int, ally: int, expected_choice: int, expected_encounter: int) -> void:
	if not pending() or choice != expected_choice or encounter != expected_encounter: return
	if ally < 0:
		if lane in _allies(): show_local(lane)
		return
	var result := pick({"ally": ally, "lane": lane, "choice": expected_choice, "encounter": expected_encounter})
	if not result.ok: show_local()
