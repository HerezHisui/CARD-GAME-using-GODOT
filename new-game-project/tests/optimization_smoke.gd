extends SceneTree
## Verifies bounded face polling without delaying direct combat/status updates.
class CountingCard extends "res://scripts/card_3d.gd":
	var signature_checks := 0
	func current_face_signature() -> int:
		signature_checks += 1
		return super.current_face_signature()

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func run() -> void:
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var card = load("res://scenes/card_3d.tscn").instantiate()
	card.set_script(CountingCard)
	game.add_child(card)
	card.preview_only = true
	card.setup({"id":"audit", "name":"Audit", "type":"response", "element":"evac", "cost":1, "attack":2, "health":4})
	card.set_process(false)
	card.signature_checks = 0
	for i in 120: card._process(1.0 / 120.0)
	check(card.signature_checks <= 11, "one second of 120Hz frames performs at most 11 fallback checks")
	card.add_status("strength", 3)
	check(card._atk_label.text == "5", "explicit status application updates the card immediately")
	card.statuses.strength = 7
	card._process(0.1)
	check(card._atk_label.text == "9", "external state changes reach the face within the bounded fallback interval")
	var display = game.opponent_hand
	game.enemy_hand.clear()
	game.enemy_hand.append({"id":"a", "locked_until":99})
	game.enemy_hand.append({"id":"b"})
	display.refresh()
	var original = display.get_child(0)
	game.enemy_hand[0].locked_until = 0
	display.refresh()
	check(display.get_child(0) == original, "sealing changes do not rebuild identical face-down cards")
	game.enemy_hand.pop_back()
	display.refresh()
	check(display.get_child_count() == 1, "opponent draw/discard counts remain correct")
	card.queue_free()
	await process_frame
	if failures: quit(1)
	else:
		print("PASS: bounded face work, immediate status feedback, external-state refresh, stable opponent backs and live hand counts")
		quit()
