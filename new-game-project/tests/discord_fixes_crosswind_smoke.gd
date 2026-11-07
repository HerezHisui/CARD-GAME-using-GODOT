# Covers: Crosswind moves an ally with the same move step as a Preparedness relocation (Discord fix, item 3).
# game_3d_manager.apply_relocation does the move for both sides. Each side stays on its own lanes.
extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func fixture() -> void:
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_waiting = true
	game.set_seats("local", "remote")
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()
	game._set_phase(game.Phase.ENEMY)
	game.tension = 6
	game.disaster_actions.begin_turn()

func unit(id: String, lane: int, side: String) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": id, "name": id, "type": side, "element": "fire" if side == "disaster" else "evac",
		"cost": 0, "attack": 1, "health": 3})
	var slots: Array = game._threat_slots() if side == "disaster" else game._response_slots()
	card.place_on_slot(slots[lane])
	return card

func pick(ally: int, lane: int) -> Dictionary:
	var choice: Dictionary = game.disaster_relocation.view()
	return game.disaster_relocation.pick({"choice": choice.get("choice", -1),
		"encounter": choice.get("encounter", -1), "ally": ally, "lane": lane})

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.presentation.automated_choice = 0
	fixture()
	var ally := unit("Ally", 0, "disaster")
	var data: Dictionary = Decks.pool("disaster").base.crosswind.duplicate(true)
	game.enemy_hand.assign([data])
	var played: Dictionary = await game.disaster_actions.play_base(data, game._threat_slots()[1])
	expect(played.ok and game.disaster_relocation.pending(), "Crosswind opens its move choice")
	await frames()
	var before: int = game.battle_log.size()
	expect(not pick(0, 1).ok, "an occupied lane is refused")
	var result := pick(0, 3)
	expect(result.ok and ally.current_slot == game._threat_slots()[3], "the ally moves to the empty lane")
	expect(not game.disaster_relocation.pending(), "the choice is used once")
	if before < 300:
		var lines: Array = game.battle_log.slice(before)
		expect(lines.any(func(line): return "Relocated Ally" in str(line)), "the shared move step logged the move")
	# The shared step keeps each side on its own lanes.
	var helper := unit("Helper", 0, "response")
	game.apply_relocation(helper, game._response_slots()[2], null)
	expect(helper.current_slot == game._response_slots()[2], "a Preparedness relocation still works")
	if game.balance_enabled():
		game.apply_relocation(ally, game._response_slots()[3], null)
		expect(ally.current_slot == game._threat_slots()[3], "a Disaster card never moves onto a Response lane")
		game.apply_relocation(helper, game._threat_slots()[2], null)
		expect(helper.current_slot == game._response_slots()[2], "a Response card never moves onto a threat lane")
	game.clear_battle()
	if failures > 0:
		push_error("discord_fixes_crosswind_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: discord_fixes_crosswind_smoke (%d checks)" % checks)
	quit(0)
