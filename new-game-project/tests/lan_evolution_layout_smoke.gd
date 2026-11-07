extends SceneTree

# Player 2 evolution offer: centered tiles, Choose buttons at the tile bottoms.
class RecordingLink:
	extends "res://scripts/lan_session.gd"
	func request_action(_msg) -> void:
		pass

const View = preload("res://scripts/lan_view.gd")
const Decks = preload("res://scripts/versus_decks.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 8) -> void:
	for i in count: await process_frame

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func check_row(label: String, row: Control) -> void:
	var tiles := row.get_children()
	expect(tiles.size() == 3, label + " shows three tiles")
	if tiles.is_empty(): return
	var left: float = tiles[0].get_global_rect().position.x
	var right: float = tiles[-1].get_global_rect().end.x
	var row_rect := row.get_global_rect()
	expect(absf((left - row_rect.position.x) - (row_rect.end.x - right)) <= 2.0, label + " tiles are centered")
	for tile in tiles:
		var gap: float = tile.get_global_rect().end.y - tile.get_node("Box/ActionButton").get_global_rect().end.y
		expect(gap <= 24.0, label + " Choose sits at the tile bottom (gap %s)" % gap)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	var versus: Node = preload("res://scripts/versus_match.gd").new()
	game.run_director.add_child(versus)
	game.run_director.versus_match = versus
	versus.setup(game.run_director)
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.lan_evolution_picks_override = true
	game.set_seats("local", "remote")
	game.phase = game.Phase.SETUP
	game.turn = 1
	game.tension = 6
	game.disaster_waiting = true
	game.run_director.close_modal()
	game.run_director.battle_active = false
	game.disaster_actions.begin_turn()
	var pool: Dictionary = Decks.pool("disaster")
	game.enemy_evolution_deck.assign([pool.evolutions.wildfire.duplicate(true),
		pool.evolutions.worldbreaker.duplicate(true), pool.evolutions.wildfire.duplicate(true)])
	game.enemy_hand.assign([pool.base.ember.duplicate(true)])
	game.enemy_draw_evolutions(1)
	game.run_director.close_modal()
	var link := RecordingLink.new()
	root.add_child(link)
	var panel: Control = preload("res://scripts/lan_client_panel.gd").new()
	root.add_child(panel)
	panel.setup_evolutions(game.run_director)
	link.attach_panel(panel)
	link.push_view(View.build(game))
	await frames(20)
	check_row("P2 offer", panel.evolution_choices)
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: lan_evolution_layout_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
