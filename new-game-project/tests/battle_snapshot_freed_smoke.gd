extends SceneTree
## A freed card in an armed Plan must not break the snapshot, and a failed LAN view must be sent again.
const Snapshot = preload("res://scripts/battle_snapshot.gd")

# A session whose first view build fails, like the freed-card error did on the host.
class FailOnceLink:
	extends "res://scripts/lan_session.gd"
	var sends := 0
	func send_view() -> void:
		sends += 1
		if sends == 1:
			view_failed = true

var failures := 0
var checks := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func lane_unit(id: String, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": id, "name": id, "type": "response", "element": "evac", "cost": 1, "attack": 2, "health": 8})
	card.in_hand = false
	card.current_slot = game._response_slots()[lane]
	return card

func arm(targets: Array) -> void:
	game.plans.armed = {
		"kind": "extract", "triggered": false, "targets": targets, "destination": game._response_slots()[3],
	}

func snapshot_fixture() -> void:
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	var first: Node = lane_unit("first", 0)
	var second: Node = lane_unit("second", 1)
	arm([first, second])
	var state: RefCounted = Snapshot.new().capture(game)
	var ids: Array = [state.lanes.response[0], state.lanes.response[1]]
	check(state.plans.armed.targets == ids, "valid Plan keeps both targets in order")
	first.remove_from_group("cards")
	first.free()
	arm([game.plans.armed.targets[0], second])
	state = Snapshot.new().capture(game)
	check(state != null, "capture finishes with a freed Plan target")
	if state == null:
		return
	var live: String = state.lanes.response[1]
	check(state.plans.armed.targets == [live], "freed target skipped, live target kept")
	check(state.cards[live].definition.id == "second", "kept target is the live card")
	check(state.plans.armed.destination == {"side": "response", "lane": 3}, "Plan destination unchanged")

func resend_fixture() -> void:
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	var link := FailOnceLink.new()
	link.game = game
	link.is_host = true
	link.disaster_peer = 2
	root.add_child(link)
	await frames(1)
	await frames(1)
	check(link.sends >= 2, "failed view is sent again on the next frame")
	check(link.was_phase == int(game.phase), "phase is stored only after the resend worked")
	var sends: int = link.sends
	await frames(3)
	check(link.sends == sends, "no repeat send once the view went out")
	var real := preload("res://scripts/lan_session.gd").new()
	real._push_built_view(2, {})
	check(real.view_failed, "empty view is not pushed")
	real.view_failed = false
	real._push_built_view(2, null)
	check(real.view_failed, "broken view is not pushed")
	real.free()
	link.queue_free()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	snapshot_fixture()
	await resend_fixture()
	game.clear_battle()
	await process_frame
	print("%s: battle_snapshot_freed_smoke.gd (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(1 if failures else 0)
