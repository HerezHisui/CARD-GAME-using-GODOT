extends SceneTree
## Menu redesign: room, catalog, popup and end-screen styles, focus and navigation.
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

## Opens a screen and waits for the deferred style call.
func open(screen: Callable, in_battle: bool = false) -> void:
	director.close_modal()
	director.screen = ""
	director.battle_active = in_battle
	director.run_active = true
	screen.call()
	await process_frame
	await process_frame

func buttons() -> Array:
	return director.content.find_children("*", "Button", true, false)

## Every restyled button keeps a bronze look when hovered while pressed and when focused.
func all_styled(message: String) -> void:
	var list := buttons()
	check(not list.is_empty(), message + " has buttons")
	for b: Button in list:
		check(b.has_theme_stylebox_override("hover_pressed") and b.has_theme_stylebox_override("focus"),
			message + " button styled: " + b.text)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await process_frame
	director.new_run()
	director.coins = 100
	game.player_hp = 12

	await open(director.show_rest)
	check(director.content.has_node("RoomHeading"), "rest has an icon heading")
	all_styled("rest")
	director.content.get_node("LeaveButton").pressed.emit()
	await process_frame
	check(director.screen == "map", "leaving the infirmary returns to the map")

	director.coins = 0
	await open(director.show_shop)
	all_styled("broke shop")
	var buy: Button = director.content.find_child("ActionButton", true, false)
	check(buy != null and buy.disabled, "unaffordable card stays disabled")
	check(buy != null and buy.tooltip_text.is_empty(), "no tooltip repeating the price")
	director.coins = 100

	director.current = 0
	director.rooms[0]["event"] = "science"
	director.event_key = ""
	await open(director.show_event)
	check(director.content.has_node("Center/Box/RoomHeading"), "event heading styled inside its centered box")

	await open(director.show_deck)
	check(director.content.has_node("CatalogHeading"), "deck has a catalog heading")
	all_styled("deck")
	var was_descending: bool = director.deck_descending
	director.reverse_sort(false)
	check(director.content.has_node("Cards") and director.content.has_node("SortRow"), "order toggle keeps the deck grid")
	var order: Button = director.content.get_node("SortRow/OrderButton")
	check(order.text.begins_with("Ascending" if was_descending else "Descending"), "order button shows new order")
	director.deck_descending = was_descending

	# Two screens in one frame: the first screen's style must not land on the second.
	await open(func(): director.show_upgrade(); director.show_upgrade_preview(0))
	var heading: Label = director.content.get_node_or_null("CatalogHeading")
	check(heading != null and heading.text == "UPGRADE PREVIEW", "stale workshop style skipped")

	await open(director.confirm_title, true)
	all_styled("confirm")
	var focused := root.gui_get_focus_owner() as Button
	check(focused != null and focused.text == "Keep playing", "confirmation focuses the safe answer")

	await open(director.show_run_victory)
	check(director.content.has_node("ResultIcon"), "victory notice has an icon")
	focused = root.gui_get_focus_owner() as Button
	check(focused != null and focused.name == "ReturnButton", "victory focuses its first action")

	await open(func(): director.battle_finished(false), true)
	check(director.screen == "result" and director.content.has_node("ResultIcon"), "defeat notice styled")
	var summary: Label = director.content.get_child(2) as Label
	check(summary != null and "floor 1" in summary.text, "defeat shows the floor reached")

	print("MENU STYLE: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
