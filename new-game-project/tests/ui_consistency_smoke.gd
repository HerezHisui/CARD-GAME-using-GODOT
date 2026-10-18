extends SceneTree
const UI = preload("res://scripts/ui_theme.gd")
var game: Node
var director: Node
var failures := 0
var captures := 0
var target_size := Vector2i(1440, 900)
var evidence: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--viewport="):
			var width := int(argument.get_slice("=", 1))
			target_size = Vector2i(width, 800 if width == 1280 else (932 if width == 1906 else 900))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func capture(name: String) -> void:
	root.size = target_size
	await create_timer(0.4).timeout
	check(root.size == target_size, name + " retains requested viewport size")
	check(director.root.theme == UI.get_theme(), name + " uses shared theme")
	check(game.get_node("HUD/Root").theme == UI.get_theme(), name + " HUD shares the theme")
	if director.modal.visible:
		if director.compact_layout:
			var rect: Rect2 = director.modal.get_global_rect()
			check(absf(rect.size.x - 420) < 2, name + " compact width is 420")
			check(director.content.get_global_rect().end.x <= director.modal_scroll.get_global_rect().end.x + 1, name + " compact content fits without horizontal clipping")
			check(rect.get_center().distance_to(root.get_visible_rect().size / 2) < 2, name + " compact panel is centered")
		check(director.modal.get_global_rect().end.x <= root.get_visible_rect().size.x + 2, name + " panel fits horizontally")
		check(director.modal.get_global_rect().end.y <= root.get_visible_rect().size.y + 2, name + " panel fits vertically")
		for control in director.content.find_children("*", "Control", true, false):
			if control is Button and control.is_visible_in_tree():
				check(control.get_global_rect().end.x <= root.get_visible_rect().size.x + 2, name + " button fits horizontally: " + control.text)
				if not control.get_parent() is ScrollContainer and not _inside_scroll(control):
					check(control.get_global_rect().end.y <= root.get_visible_rect().size.y + 2, name + " button fits vertically: " + control.text)
	for face in director.root.find_children("*", "TextureRect", true, false):
		if face.is_visible_in_tree() and face.get_parent() is AspectRatioContainer and face.size.y > 0:
			check(absf(face.size.x / face.size.y - float(director.CardFace.FACE_W) / director.CardFace.FACE_H) < 0.02, name + " card aspect ratio")
	for viewport in director.root.find_children("*", "SubViewport", true, false):
		var heading = viewport.get_child(0).get_node_or_null("CardName")
		if heading:
			check(heading.position.x + heading.size.x <= director.CardFace.FACE_W - 9, name + " card name stays inside its frame")
			check(heading.get_line_count() <= 2 and heading.get_minimum_size().y <= heading.size.y + 1, name + " full card name fits its header")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var artifact := name if name.ends_with("_%d" % target_size.x) else name + "_%d" % target_size.x
		var path := "res://tests/artifacts/ui_" + artifact + ".png"
		var pixels := root.get_texture().get_image()
		check(pixels.get_size() == target_size, name + " capture has the requested pixel dimensions")
		pixels.save_png(path)
		evidence.append({"screen": name, "path": path, "pixels": [pixels.get_width(), pixels.get_height()]})
	captures += 1

func _inside_scroll(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != director.modal and parent != null:
		if parent is ScrollContainer: return true
		parent = parent.get_parent()
	return false

func battle() -> void:
	paused = false
	if is_instance_valid(director.saved_content): director.saved_content.queue_free()
	director.saved_content = null
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)

func review_overlays(suffix: String) -> void:
	battle()
	await capture("battle_" + suffix)
	check(game.get_node("HUD/Root/DeckDrawButton").is_visible_in_tree(), "draw remains visible")
	check(game.get_node("HUD/Root/EndTurnButton").is_visible_in_tree(), "end turn remains visible")
	check(director.dashboard.get_parent() == game.get_node("HUD/Root"), "dashboard draws behind scene buttons")
	var draw := game.get_node("HUD/Root/DeckDrawButton")
	var end_turn := game.get_node("HUD/Root/EndTurnButton")
	check(not draw.get_global_rect().intersects(end_turn.get_global_rect()), "draw and end turn do not overlap")
	check(not director.graveyard_button.get_global_rect().intersects(draw.get_global_rect()), "graveyard and draw do not overlap")
	director.show_menu()
	await capture("pause_" + suffix)
	battle()
	director.confirm_title()
	await capture("return_confirm_" + suffix)
	battle()
	director.choose_card("RECOVER A RESPONSE", director.collection, func(_card): pass, director.close_modal)
	await capture("target_" + suffix)
	battle()
	director.intel_revealed = false
	director.choose_enemy_hand(game.enemy_hand, func(_card): pass, director.close_modal)
	await capture("hidden_hand_" + suffix)
	battle()
	director.show_intel()
	await capture("intel_" + suffix)
	battle()
	director.choose_slot(game._response_slots(), func(_slot): pass, director.close_modal)
	await capture("lanes_" + suffix)
	battle()
	var original_turn: int = game.turn
	game.turn = 5
	director.show_buff_choices()
	await capture("adaptation_" + suffix)
	game.turn = original_turn
	paused = false
	director.battle_active = false
	director.show_rewards()
	await capture("rewards_" + suffix)
	director.show_rewards(0)
	await capture("reward_dossier_" + suffix)
	director.show_shop()
	await capture("shop_" + suffix)
	director.show_upgrade()
	await capture("workshop_" + suffix)
	director.show_upgrade_preview(0)
	await capture("comparator_" + suffix)
	director.show_remove_cards("shop")
	director.preview_remove(0)
	await capture("remove_confirm_" + suffix)
	director.show_rest()
	await capture("infirmary_" + suffix)
	director.show_event()
	await capture("event_" + suffix)
	for event_type in director.EVENT_TYPES:
		if event_type == "locked": continue
		director.event_key = ""
		director.rooms[director.current].event = event_type
		director.show_event()
		await capture("event_" + event_type + "_" + suffix)
	director.show_contingency_reward("floor")
	await capture("boss_reward_" + suffix)
	director.show_floor_buffs()
	await capture("floor_reward_" + suffix)
	director.show_run_victory()
	await capture("victory_" + suffix)
	director.run_active = true
	director.screen = "map"
	director.persistence.checkpoint()
	check(director.persistence.has_run(), "Continue review has a real saved run")
	director.show_title()
	await capture("continue_" + suffix)
	director.confirm_abandon()
	await capture("abandon_confirm_" + suffix)

func run() -> void:
	root.size = target_size
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.discard()
	director.show_title()
	await capture("title")
	director.show_characters()
	await capture("characters")
	director.show_character_preview(0)
	await capture("starter")
	director.new_run()
	await capture("map")
	game.presentation.automated_choice = 0
	director.visit(0)
	await capture("battle_entry")
	await create_timer(0.85).timeout
	await capture("coin")
	for i in 100:
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: break
		await create_timer(0.1).timeout
	if game.phase == game.Phase.PLAYER_DRAW:
		game._on_draw_button_pressed()
	await create_timer(1.0).timeout
	await capture("battle")
	await polish_checks()
	for viewport_size in [target_size]:
		root.size = viewport_size
		await process_frame
		battle()
		director.show_deck()
		await capture("deck_%d" % viewport_size.x)
		var grid = director.content.get_node("Cards").get_child(0)
		check(grid.columns >= 4, "desktop deck uses available width")
		for card in grid.find_children("*", "SubViewport", true, false):
			check(card.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "catalog previews render on demand")
		battle()
		director.show_graveyard()
		await capture("graveyard_%d" % viewport_size.x)
		battle()
		director.show_map()
		await capture("map_%d" % viewport_size.x)
		battle()
		director.show_debug()
		await capture("password_%d" % viewport_size.x)
		unlock_debug()
		await capture("debug_%d" % viewport_size.x)
		await review_overlays(str(viewport_size.x))
	root.size = target_size
	battle()
	director.show_plans()
	await capture("plans")
	battle()
	director.show_debug()
	unlock_debug()
	await capture("debug")
	battle()
	director.show_menu()
	await capture("menu")
	battle()
	battle()
	var card = game.get_hand_cards()[0]
	game.hand.erase(card)
	card.reparent(game, true)
	card.place_on_slot(game._response_slots()[0])
	director.inspect_board_card(card)
	await capture("inspection")
	battle()
	card.add_status("burn", 4)
	card.add_status("strength", 2)
	card.add_status("barrier", 2)
	card.add_status("poison", 3)
	card.add_status("bleed", 2)
	card.add_status("healing_reduced", 2)
	card.add_status("unknown_test", 1)
	await capture("status_feedback")
	director.inspect_board_card(card)
	await capture("inspection_statuses")
	check(not director.inspection_dossier.get_node("DossierText").text.contains("BADGE LEGEND"), "inspection omits generic badge legend")
	for badge in card._status_row.find_children("*", "Label", true, false):
		check(not badge.get_global_rect().intersects(Rect2(18, 72, 228, 144)), "active status strip stays outside artwork")
	battle()
	director.show_deck()
	var face = director.content.find_children("*", "TextureRect", true, false).filter(func(node): return node.get_parent() is AspectRatioContainer)[0]
	var first_index: int = director.sorted_indices(director.collection, director.deck_sort, director.deck_descending)[0]
	director.show_catalog_inspection(director.collection[first_index], face.texture)
	await capture("catalog_inspection")
	director.root.get_node("CatalogInspection").queue_free()
	await process_frame
	var picker = director.content.find_children("*", "OptionButton", true, false)[0]
	var popup: PopupMenu = picker.get_popup()
	popup.popup(Rect2i(Vector2i(picker.global_position + Vector2(0, picker.size.y)), Vector2i(250, 260)))
	await capture("sort_popup")
	check(popup.get_theme_color("font_color") == UI.TEXT, "native sort popup inherits the shared theme")
	popup.hide()
	battle()
	game.record_graveyard(card, "Destroyed")
	director.show_graveyard()
	await capture("graveyard_populated")
	battle()
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	await capture("boss_intent")
	game.final_boss.queue_free()
	game.final_boss = null
	director.show_buff_choices()
	await capture("buffs")
	paused = false
	director.battle_active = false
	director.show_rewards()
	await capture("rewards")
	director.show_shop()
	await capture("shop")
	director.show_upgrade()
	await capture("upgrade")
	director.show_upgrade_preview(0)
	await capture("upgrade_preview")
	director.show_remove_cards("shop")
	await capture("remove")
	director.show_rest()
	await capture("rest")
	director.show_event()
	await capture("event")
	director.show_floor_buffs()
	await capture("floor_buffs")
	director.show_run_victory()
	await capture("victory")
	director.battle_active = true
	director.battle_finished(false)
	await capture("defeat")
	director.reset_panel("CONTROL STATES", "Shared styles for primary actions, focus, selection and unavailable actions.", "deck")
	var states := HBoxContainer.new()
	director.content.add_child(states)
	director.button("Normal", Callable(), states)
	var primary: Button = director.button("Primary", Callable(), states)
	primary.theme_type_variation = "PrimaryButton"
	var pressed: Button = director.button("Pressed", Callable(), states)
	pressed.toggle_mode = true
	pressed.button_pressed = true
	director.button("Disabled", Callable(), states).disabled = true
	director.button("Keyboard focus", Callable(), states).grab_focus()
	await capture("control_states")
	battle()
	for buff in director.Rules.BUFFS:
		game.player_buffs[buff.id] = 1
		game.enemy_buffs[buff.id] = 1
	director.show_menu()
	await capture("long_buff_menu")
	director.reset_panel("AFFINITY FRAMES", "Each element keeps its own label, icon color and frame accent.", "deck")
	var affinity_scroll := ScrollContainer.new()
	affinity_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	director.content.add_child(affinity_scroll)
	var affinity_grid := GridContainer.new()
	affinity_scroll.add_child(affinity_grid)
	director.fit_card_grid(affinity_grid, affinity_scroll)
	for element in UI.AFFINITIES:
		director._card_tile({"name":element.capitalize(), "element":element, "type":"disaster" if element in ["fire", "flood", "earthquake", "typhoon"] else "response", "cost":1, "attack":2, "health":3}, affinity_grid)
	await capture("affinities")
	director.persistence.discard()
	var manifest := FileAccess.open("res://tests/artifacts/ui_audit_%d.json" % target_size.x, FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"viewport": [target_size.x, target_size.y], "captures": captures, "failures": failures, "evidence": evidence}, "\t"))
	print("UI AUDIT: %d screen captures, %d failures" % [captures, failures])
	quit(1 if failures else 0)

func unlock_debug(owner_director: Node = null) -> void:
	var owner: Node = owner_director if owner_director != null else game.run_director
	check(owner.screen == "debug_password", "debug requires password dialog")
	var field: LineEdit = owner.content.get_node("DebugPassword")
	check(field.secret, "debug password is masked")
	field.text = "*****"
	field.text_submitted.emit(field.text)

func mouse(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func polish_checks() -> void:
	battle()
	game._apply_view(game.DESK_VIEW)
	await create_timer(0.3).timeout
	check(director.prep.get_parent().get_child(2).text == "Deck %d" % game.deck.size(), "HUD keeps Deck without Hand readout")
	director.show_deck()
	await capture("deck_navigation")
	var buttons: Array = director.content.find_children("*", "Button", true, false)
	check(not buttons.any(func(b): return b.text.begins_with("Hand") or b.text == "On board" or b.text.begins_with("Draw pile") or b.text == "Janitor hand"), "browser has only Deck and Response Graveyard views")
	check(buttons.any(func(b): return b.text == "Response Graveyard"), "browser retains Response Graveyard")
	battle()
	var originals: Array = game.get_hand_cards().map(func(c): return c.card_data.duplicate(true))
	for count in [1, 4, 8]:
		for card in game.get_hand_cards():
			game.hand.erase(card)
			card.queue_free()
		await process_frame
		for i in count: game.add_card_to_hand(director.collection[i % director.collection.size()])
		await create_timer(0.3).timeout
		for index in [0, floori(count / 2.0), count - 1]:
			var card: Node = game.get_hand_cards()[index]
			card.set_hand_hover(true)
			await capture("hover_%d_%d" % [count, index])
			card.set_hand_hover(false)
			await create_timer(0.16).timeout
	for card in game.get_hand_cards():
		game.hand.erase(card)
		card.queue_free()
	await process_frame
	for definition in originals: game.add_card_to_hand(definition)
	await create_timer(0.3).timeout
	var hand_card: Node = game.get_hand_cards().back()
	var polygon: PackedVector2Array = game.hand_card_polygon(hand_card, false)
	var point := (polygon[0] + polygon[1]) * 0.5 + Vector2(0, 15)
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(root.get_final_transform() * point)
		await create_timer(0.12).timeout
	mouse(true, point)
	check(game.dragged_hand_card == hand_card, "rendered input targets the intended hand card")
	for frame in 20:
		if director.screen == "inspect": break
		await create_timer(0.05).timeout
	mouse(false, point)
	await process_frame
	check(director.screen == "inspect", "rendered hand inspection remains latched after release")
	if director.screen == "inspect": check(director.inspected_face.texture == hand_card._vp.get_texture(), "rendered latch inspects the intended card")
	await capture("latched_hand_inspection")
	director.dismiss_inspection()
	battle()
	director.show_debug()
	await capture("password_empty")
	var password: LineEdit = director.content.get_node("DebugPassword")
	password.text = "******"
	password.text_submitted.emit(password.text)
	check(director.screen == "debug_password", "six asterisks are rejected")
	await capture("password_error")
	unlock_debug()
	await capture("password_unlocked_debug")
	var cancel: Button = director.content.find_children("*", "Button", true, false).filter(func(b): return b.text == "Cancel")[0]
	cancel.grab_focus()
	await capture("debug_footer")
	check(director.modal_scroll.get_global_rect().encloses(cancel.get_global_rect()), "debug footer is reachable by scrolling")
	battle()
	var cards := [
		{"name":"Base Disaster", "type":"disaster", "element":"fire", "cost":0, "attack":2, "health":3},
		{"name":"Evolved Disaster", "type":"disaster", "element":"flood", "cost":2, "attack":5, "health":6},
		{"name":"Upgraded Response", "type":"response", "element":"brace", "cost":1, "attack":3, "health":4, "upgrades":2},
		{"name":"Once Upgraded", "type":"response", "element":"evac", "cost":1, "attack":2, "health":3, "upgrades":1},
		{"name":"Supply Utility", "type":"response", "element":"clearance", "cost":1, "attack":0, "health":1, "utility":true, "effect":"draw"}
	]
	director.reset_panel("CARD BADGES", "Costs, upgrades, type and utility labels.", "deck")
	var grid := GridContainer.new()
	grid.columns = 5 if target_size.x > 1440 else 4
	director.content.add_child(grid)
	for definition in cards: director._card_tile(definition, grid)
	await capture("clear_card_badges")
	for preview in director.content.find_children("*", "Area3D", true, false):
		var art := Rect2(18, 72, director.CardFace.FACE_W - 36, 144)
		for text_label in preview._vp.get_child(0).find_children("*", "Label", true, false):
			check(not text_label.get_global_rect().intersects(art), "artwork window is clear: %s at %s" % [text_label.text, text_label.get_global_rect()])
		director.show_catalog_inspection(preview.card_data, preview._vp.get_texture())
		var dossier: String = director.inspection_dossier.get_node("DossierText").text
		check(not dossier.contains("BADGE LEGEND") and not dossier.contains("No temporary Plan effect") and not dossier.contains("CURRENT STATUSES"), "clean previews omit tutorials and empty effect sections")
		check(dossier.contains("PERMANENT UPGRADES  %d / 2" % director.upgrade_level(preview.card_data)), "upgrade details stay in dossier")
		var sacrifice: bool = preview.card_data.type == "disaster" and int(preview.card_data.cost) > 0
		check(preview._cost_caption.text == ("SAC" if sacrifice else ""), "corner badge labels sacrifices without COST text")
		if sacrifice: check(dossier.contains("SAC: %d allied units" % int(preview.card_data.cost)), "dossier explains sacrifice requirement")
		elif preview.card_data.type == "disaster": check(dossier.contains("Cost: 1 Tension"), "dossier explains base Tension cost")
		else: check(dossier.contains("Cost: %d energy" % int(preview.card_data.cost)), "dossier shows energy cost")
		director.dismiss_inspection()
		await process_frame
	battle()
