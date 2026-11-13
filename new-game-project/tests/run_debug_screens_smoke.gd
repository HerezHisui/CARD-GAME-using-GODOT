# Covers: Debug screens moved to run_debug.gd give the same screens and results as before the move.
extends SceneTree

# Captured on the original director code, before the move (perf-clean M3).
const ORIGINAL_SHA256 := "fac1c101462337eb3828f3a6cc86e89e4176ff5431cbbd81df291594d806a4ab"

var game: Node
var director: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

## Every control on the screen: name, class, text or value, and whether it is off.
func controls(node: Node, out: Array) -> Array:
	for child in node.get_children():
		if child is Button: out.append([str(child.name), child.get_class(), child.text, child.disabled])
		elif child is SpinBox: out.append([str(child.name), child.min_value, child.max_value, child.value, child.editable])
		elif child is Label: out.append([str(child.name), child.text])
		controls(child, out)
	return out

func battle() -> void:
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.set_process(false)
	game.add_card_to_hand({"name":"Hand fixture", "type":"response", "element":"evac", "cost":1, "attack":2, "health":5})

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.new_run()
	battle()
	var results: Array = []
	# Wrong password, then cancel.
	director.show_debug()
	results.append([director.screen, controls(director.modal, [])])
	var password: LineEdit = director.content.get_node("DebugPassword")
	password.text = "wrong"
	password.text_submitted.emit(password.text)
	results.append([director.screen, director.content.get_node("PasswordError").text])
	director.cancel_debug_password()
	results.append([director.screen, director.modal.visible])
	check(not director.modal.visible, "cancel closes the password screen")
	# Right password opens the value screen.
	director.show_debug()
	password = director.content.get_node("DebugPassword")
	password.text = "*****"
	password.text_submitted.emit(password.text)
	check(director.screen == "debug", "right password opens the debug values")
	results.append([director.screen, controls(director.modal, [])])
	# Set a status on the hand card, then apply new values.
	var row: Node = director.content.get_node("StatusRow")
	row.get_node("Status").select(2)
	row.get_node("Amount").value = 3
	row.get_node("SetStatusButton").pressed.emit()
	results.append([game.get_hand_cards()[0].statuses])
	director.content.get_node("Values/coins").value = 77
	director.content.get_node("Values/player_hp").value = 9
	director.content.get_node("Values/energy_cap").value = 4
	director.content.get_node("Values/preparedness").value = 9
	director.content.get_node("Values/plans").value = 2
	director.content.get_node("ApplyButton").pressed.emit()
	results.append([director.coins, game.player_hp, game.energy_cap, game.preparedness, game.plans.tokens,
		director.screen, director.modal.visible])
	check(director.coins == 77 and game.preparedness == 4, "values apply and energy stays under its cap")
	# Enter the floor 2 boss from the debug screen.
	battle()
	director.show_debug()
	director._open_debug("*****")
	check(director.debug_enter_boss(2), "boss shortcut works from the debug screen")
	results.append([director.floor_number, director.encounter, director.battle_active, director.screen,
		director.current == int(director.rooms.back().id)])
	var digest := JSON.stringify(results, "", true).sha256_text()
	print("run_debug_screens_smoke digest " + digest)
	check(digest == ORIGINAL_SHA256, "results match the code before the move")
	print("run_debug_screens_smoke: %d checks, %d failures" % [checks, failures])
	paused = false
	if failures > 0:
		quit(1)
		return
	print("PASS: debug screens match the original director code")
	quit(0)
