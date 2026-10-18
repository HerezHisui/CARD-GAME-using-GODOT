extends SceneTree
var failures := 0
var game: Node
var director: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func mouse(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.new_run()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.set_process(false)
	game.add_card_to_hand(director.collection[0])
	var card: Node = game.get_hand_cards()[0]
	await process_frame
	await process_frame
	var initial_energy: int = game.preparedness
	var point := Vector2(600, 650)
	mouse(true, point)
	await process_frame
	card._start_drag()
	director.begin_inspect_hold(card, true)
	await create_timer(0.45).timeout
	check(director.screen == "inspect" and paused, "stationary hold inspects a hand card")
	await inspection_layout_checks()
	check(card.in_hand and not card.is_dragging and card.get_parent() == game.hand_parent(), "inspection restores the hand without deploying")
	check(game.preparedness == initial_energy and game.get_hand_cards().size() == 1, "hand inspection spends no energy or cards")
	mouse(false, point)
	await process_frame
	check(director.modal.visible and paused, "releasing a hand inspection keeps it latched")
	click_key(KEY_ESCAPE)
	check(not director.modal.visible and not paused, "Escape closes latched inspection without opening Pause")

	mouse(true, point)
	await process_frame
	card._start_drag()
	director.begin_inspect_hold(card, true)
	var motion := InputEventMouseMotion.new()
	motion.position = point + Vector2(100, 0)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await create_timer(0.45).timeout
	check(not director.modal.visible and card.is_dragging, "moving a held card keeps normal dragging")
	card.cancel_hand_drag()
	mouse(false, motion.position)
	await process_frame

	director.show_debug()
	check(director.screen == "debug_password", "direct debug access is gated")
	var password: LineEdit = director.content.get_node("DebugPassword")
	check(password.secret, "password is masked")
	for wrong in ["", "****", "******", " *****", "***** ", "wrong"]:
		password.text = wrong
		password.text_submitted.emit(wrong)
		check(director.screen == "debug_password" and director.content.find_children("*", "SpinBox", true, false).is_empty(), "wrong password cannot expose controls")
	password.text = "*****"
	password.text_submitted.emit(password.text)
	check(director.screen == "debug", "exact password unlocks debug")
	var inputs: Array = director.content.find_children("*", "SpinBox", true, false)
	inputs[-1].value = 5
	for button in director.content.find_children("*", "Button", true, false):
		if button.text == "Set status": button.pressed.emit()
	check(card.statuses.get("strength", 0) == 5 and card._atk_label.text == str(card.effective_attack()), "debug status edits update the live attack badge")
	inputs[-1].value = 0
	for button in director.content.find_children("*", "Button", true, false):
		if button.text == "Set status": button.pressed.emit()
	check(not card.statuses.has("strength"), "zero removes the chosen debug status")
	director.close_modal()
	var baseline := game.find_children("*", "SubViewport", true, false).size()
	for i in 3:
		director.show_deck()
		await process_frame
		await process_frame
		check(game.find_children("*", "SubViewport", true, false).size() <= baseline + director.collection.size(), "reopening a deck does not accumulate previews")
		director.close_modal()
	director.show_menu()
	await process_frame
	await process_frame
	check(game.find_children("*", "SubViewport", true, false).size() == baseline, "replacing the catalog frees its preview viewports")
	await catalog_input_checks()
	await input_playtest()
	director.persistence.discard()
	print("UI INTERACTIONS: %d failures" % failures)
	quit(1 if failures else 0)

func click_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func hand_point(card: Node) -> Vector2:
	var polygon: PackedVector2Array = game.hand_card_polygon(card, false)
	return (polygon[0] + polygon[1]) * 0.5 + Vector2(0, 15)

func input_playtest() -> void:
	paused = false
	game.clear_battle()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game._apply_view(game.DESK_VIEW)
	game.player_hp = 20
	game.enemy_hp = 20
	game.preparedness = 10
	game.energy_cap = 10
	var definition: Dictionary = director.catalog.filter(func(c): return c.id == "quick_dash")[0].duplicate(true)
	game.add_card_to_hand(definition)
	await create_timer(0.4).timeout
	var card: Node = game.get_hand_cards()[0]
	var point := hand_point(card)
	motion(point)
	mouse(true, point)
	await create_timer(0.1).timeout
	mouse(false, point)
	await process_frame
	check(not director.modal.visible and card.in_hand, "quick click does not inspect or spend a card")
	await create_timer(0.3).timeout
	point = hand_point(card)
	motion(point)
	mouse(true, point)
	await create_timer(0.32).timeout
	check(director.screen == "inspect", "actual hand input opens inspection after one hold")
	mouse(false, point)
	await process_frame
	check(director.screen == "inspect" and paused, "actual opening release leaves inspection latched")
	mouse(true, Vector2(10, 100))
	mouse(false, Vector2(10, 100))
	await process_frame
	check(not director.modal.visible and card.in_hand and not card.is_dragging, "backdrop dismissal does not play the inspected card")
	await create_timer(0.3).timeout
	point = hand_point(card)
	motion(point)
	mouse(true, point)
	motion(point + Vector2(100, 0))
	motion(point)
	await create_timer(0.32).timeout
	check(not director.modal.visible, "pointer excursion cancels hold even when returning")
	card.cancel_hand_drag()
	mouse(false, point)
	await create_timer(0.3).timeout
	point = hand_point(card)
	mouse(true, point)
	await process_frame
	var destination: Vector2 = game.camera.unproject_position(game._response_slots()[0].global_position)
	motion(destination)
	await create_timer(0.30).timeout
	mouse(false, destination)
	await create_timer(0.4).timeout
	check(not card.in_hand and card.current_slot == game._response_slots()[0], "real drag/release plays into a lane")
	check(game.preparedness == 9, "deployment pays cost exactly once")
	await create_timer(0.3).timeout
	point = game.camera.unproject_position(card.global_position)
	motion(point)
	mouse(true, point)
	await create_timer(0.34).timeout
	mouse(false, point)
	await process_frame
	check(director.screen == "inspect", "board hold also latches after release")
	click_key(KEY_ESCAPE)

	var selected := []
	director.choose_card("TEST UTILITY PICK", [definition], func(value): selected.append(value); director.close_modal(), director.close_modal)
	await create_timer(0.3).timeout
	var choose: Button = director.content.find_children("*", "Button", true, false).filter(func(b): return b.text == "Choose")[0]
	# Scroll the compact picker so the real button receives the click.
	choose.grab_focus()
	await create_timer(0.2).timeout
	var rect := choose.get_global_rect()
	mouse(true, rect.get_center())
	mouse(false, rect.get_center())
	await process_frame
	check(selected.size() == 1 and not director.modal.visible, "utility selection receives one actual click")
	click_key(KEY_F3)
	check(director.screen == "debug_password", "F3 requires authentication every time")
	click_key(KEY_ESCAPE)
	check(not director.modal.visible, "password Escape returns to battle")
	director.show_menu()
	var debug_button: Button = director.content.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Debug values"))[0]
	debug_button.pressed.emit()
	check(director.screen == "debug_password", "Pause debug button uses same gate")
	click_key(KEY_ESCAPE)
	check(director.screen == "menu", "password cancel returns to Pause")
	director.close_modal()
	game.enemy_deck.assign([{"name":"Quiet threat", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":1}])
	game.tension = 3
	game.tension_cap = 3
	game.turn = 1
	var end: Button = game.get_node("HUD/Root/EndTurnButton")
	await create_timer(0.3).timeout
	mouse(true, end.get_global_rect().get_center())
	mouse(false, end.get_global_rect().get_center())
	for i in 150:
		if game.turn >= 2 or game.phase == game.Phase.GAME_OVER: break
		await create_timer(0.1).timeout
	check(game.turn >= 2 or game.phase == game.Phase.GAME_OVER, "input playtest resolves enemy actions and reaches next turn/result")
	director.show_title()
	director.confirm_abandon()
	click_key(KEY_ESCAPE)
	check(director.screen == "title", "abandon confirmation Escape returns to title")
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	director.confirm_title()
	click_key(KEY_ESCAPE)
	check(not director.modal.visible and not paused, "return confirmation Escape resumes battle")


func inspection_layout_checks() -> void:
	var dossier: Control = director.inspection_dossier
	var title: Label = dossier.get_node("InspectTitle")
	check(title.text == title.text.to_upper() and title.get_theme_font_size("font_size") == 34,
		"inspection uses a large uppercase title")
	var tabs := dossier.get_node("InspectTabs").get_children()
	check(tabs.map(func(tab): return tab.text) == ["Summary", "Status", "Effects"], "inspection has three tabs")
	check(tabs[0].button_pressed, "inspection starts on Summary")
	var active: StyleBoxFlat = tabs[0].get_theme_stylebox("pressed")
	check(active.border_color == Color("e59538") and active.border_width_top == 2,
		"active inspection tab has an orange outline")
	var details: RichTextLabel = dossier.get_node("DossierText")
	check(details.get_theme_font_size("normal_font_size") == 18
		and details.get_theme_font_size("bold_font_size") == 18, "dossier body text uses 18-point fonts")
	var summary := details.text
	for index in [1, 2, 0]:
		tabs[index].button_pressed = true
		tabs[index].pressed.emit()
		check(not details.text.is_empty(), "each inspection tab shows details")
	check(details.text == summary, "returning to Summary restores card details")
	var original_size := root.size
	root.size = Vector2i(1280, 800)
	await process_frame
	var panel_rect: Rect2 = dossier.get_parent().get_global_rect()
	check(root.get_visible_rect().encloses(panel_rect), "dossier panel fits the 1280x800 window")
	check(panel_rect.encloses(details.get_global_rect()), "dossier text stays inside its panel")
	for tab in tabs:
		check(panel_rect.encloses(tab.get_global_rect()), "inspection tabs stay inside their panel")
	# Restore the input fixture's coordinate scale before injecting mouse events.
	root.size = original_size
	await process_frame
	mouse(true, tabs[1].get_global_rect().get_center())
	mouse(false, tabs[1].get_global_rect().get_center())
	check(tabs[1].button_pressed and details.text != summary, "a real click switches inspection tabs")
	var face_rect: Rect2 = director.inspected_face.get_global_rect()
	var panel: Control = dossier.get_parent()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	# The dossier must take precedence even if a preview hitbox overlaps its tabs.
	director.inspected_face.global_position = panel.global_position
	director.inspected_face.size = panel.size
	for tab in tabs:
		press.position = tab.get_global_rect().get_center()
		press.global_position = press.position
		director._input(press)
		check(dossier.is_visible_in_tree(), "synthetic tab presses cannot dismiss the dossier")
	press.position = panel.get_global_rect().position + Vector2(2, 2)
	press.global_position = press.position
	director._input(press)
	check(dossier.is_visible_in_tree(), "dossier panel padding also keeps inspection open")
	director.inspected_face.global_position = face_rect.position
	director.inspected_face.size = face_rect.size
	var row: HBoxContainer = director.inspected_face.get_parent().get_parent()
	check(row.get_child(0) == dossier.get_parent(), "inspection places details before the card preview")

func catalog_input_checks() -> void:
	director.close_modal()
	director.show_deck()
	await create_timer(0.3).timeout
	var face: TextureRect = director.content.find_children("*", "TextureRect", true, false).filter(func(node): return node.get_parent() is AspectRatioContainer)[0]
	var point := face.get_global_rect().get_center()
	for close_with_key in [false, true]:
		mouse(true, point)
		await create_timer(0.32).timeout
		mouse(false, point)
		await process_frame
		check(director.root.has_node("CatalogInspection"), "catalog hold remains open after release")
		await inspection_layout_checks()
		if close_with_key: click_key(KEY_ESCAPE)
		else:
			var center: Vector2 = director.inspected_face.get_global_rect().get_center()
			mouse(true, center)
			mouse(false, center)
		await process_frame
		check(not director.root.has_node("CatalogInspection") and director.screen == "deck", "catalog dismissal restores deck without selecting a card")
	director.close_modal()
