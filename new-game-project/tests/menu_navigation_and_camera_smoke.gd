# Covers: Menu navigation, shop and rest controls, camera views, and view persistence.
extends SceneTree
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func buttons() -> Array:
	return director.content.find_children("*", "Button", true, false)

func has_button(fragment: String) -> bool:
	return buttons().any(func(b): return fragment in b.text)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/notes5_" + name + ".png")

func key(code: Key, echo_event := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo_event
	game._unhandled_key_input(event)

func unit(lane: int, side: String) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":"fixture", "name":"Quick Dash" if side == "response" else "Cinder Cloud", "type":side, "element":"evac" if side == "response" else "fire", "cost":1, "attack":2, "health":4})
	card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	return card

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	director = game.run_director
	director.persistence.discard()
	director.show_title()
	check(not buttons().any(func(b): return b.text == "How to play"), "obsolete help entry removed")
	director.start_character(0)
	await process_frame
	check(not game.visible, "world is hidden outside battle")
	check(director.modal.offset_left == 0 and director.modal.offset_right == 0 and director.modal.offset_bottom == 0, "map fills screen below navigation")
	director.toggle_map()
	check(director.screen == "map" and director.modal.visible, "M keeps map open between encounters")
	director.show_menu()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	director._input(escape)
	check(director.screen == "map", "Esc closes the between-room menu back to map")
	await capture("map")
	director.show_deck()
	check(not has_button("Graveyards"), "no graveyard access outside battle")
	director.show_graveyard()
	check(director.screen == "deck", "direct graveyard request outside battle is ignored")
	director.close_modal()
	check(director.screen == "map", "collection closes back to map")
	game.player_hp = 19
	director.coins = 200
	director.show_shop()
	director._process(0)
	check(director.root.get_child(0).visible
		and director.modal.offset_top >= director.root.get_child(0).offset_bottom,
		"shop leaves the status header and navigation visible above its modal")
	check(has_button("+1 HP · -15 supplies") and has_button("Destroy 1 card · -30 supplies"), "shop shows actual healing and explicit removal cost")
	await capture("shop")
	director.buy_heal()
	check(game.player_hp == 20 and director.coins == 185, "first aid preserves its real price and caps healing")
	check(buttons().any(func(b): return "+0 HP" in b.text and b.disabled), "full-health aid cannot waste supplies")
	director.show_rest()
	check(has_button("Leave infirmary") and has_button("Destroy 1 card · free"), "rest has a free removal label and an exit")
	check(buttons().any(func(b): return "+0 HP" in b.text and b.disabled), "full-health rest is disabled")
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	paused = false
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	for lane in 4:
		unit(lane, "response")
		unit(lane, "disaster")
	await create_timer(0.7).timeout
	check(game.visible, "battle makes world visible")
	director.show_deck()
	check(not has_button("Graveyards"), "graveyard has its own compact HUD button instead of a deck tab")
	director.show_graveyard()
	check(director.content.get_child(0).text == "GRAVEYARD", "battle graveyard opens")
	director.close_modal()
	director.toggle_map()
	check(director.screen == "map", "M opens battle map")
	director.toggle_map()
	check(not director.modal.visible and director.screen == "", "M closes battle map")
	game.set_view(game.View.DESK)
	await create_timer(0.65).timeout
	await capture("table")
	key(KEY_S)
	check(game.view_mode == game.View.WIDE, "S selects room view from default")
	var before: float = game.camera.fov
	await create_timer(0.22).timeout
	check(game.camera.fov > before and game.camera.fov < game.WIDE_VIEW.fov, "FOV blends through intermediate values")
	await create_timer(0.45).timeout
	check(game.camera.position.is_equal_approx(Vector3(0, 0, game.WIDE_VIEW.dist)), "room transition reaches its target")
	await capture("room")
	key(KEY_S)
	check(game.view_mode == game.View.WIDE, "room is the lower camera limit")
	key(KEY_W, true)
	check(game.view_mode == game.View.WIDE, "held key repeats do not skip a view")
	key(KEY_W)
	check(game.view_mode == game.View.DESK, "W returns to table")
	await create_timer(0.12).timeout
	key(KEY_W)
	await create_timer(0.65).timeout
	check(game.view_mode == game.View.BOARD and game.in_board_view, "rapid W presses reach overhead without competing tweens")
	check(game.get_node("CameraPivot").rotation_degrees.is_equal_approx(game.BOARD_VIEW.rot), "overhead ends facing straight down")
	check(is_equal_approx(game.camera.fov, game.BOARD_VIEW.fov), "FOV reaches overhead target")
	await capture("overhead")
	key(KEY_W)
	check(game.view_mode == game.View.BOARD, "overhead is upper camera limit")
	game._set_phase(game.Phase.COMBAT)
	key(KEY_S)
	check(game.view_mode == game.View.BOARD, "combat blocks manual camera changes")
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.set_view(game.View.WIDE)
	await create_timer(0.65).timeout
	check(director.persistence.checkpoint() and director.persistence.resume(), "room-view battle checkpoint restores")
	check(game.view_mode == game.View.WIDE and is_equal_approx(game.camera.fov, game.WIDE_VIEW.fov), "Continue preserves the third camera state")
	await create_timer(0.65).timeout
	var card = game._get_card_in_slot(game._response_slots()[0])
	check(is_equal_approx(card.scale.x, game.BOARD_SCALE), "deployed cards retain their smaller world scale after Continue")
	check(is_equal_approx(game._response_slots()[0].scale.x, game.BOARD_SCALE), "lane colliders scale with the board")
	check(not game.has_node("Table"), "obsolete board reference model is removed")
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	await game._combat()
	check(game.view_mode == game.View.WIDE, "combat restores room view after its overhead animation")
	game._set_phase(game.Phase.PLAYER_PLAY)
	var legacy: Dictionary = director.persistence.read_save()
	legacy.game.erase("view_mode")
	legacy.game.in_board_view = true
	var save := FileAccess.open(director.persistence.save_path(), FileAccess.WRITE)
	save.store_string(JSON.stringify(legacy))
	save.close()
	check(director.persistence.resume() and game.view_mode == game.View.BOARD, "older two-view saves migrate to overhead")
	director.battle_active = false
	director.show_map()
	check(not game.visible, "returning to map hides battle geometry")
	# Also inspect the real encounter with both held-card displays, not just fixtures.
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.start_encounter(director.collection, "battle", 1, 0)
	await create_timer(2.5).timeout
	check(game.get_hand_cards().all(func(held): return is_equal_approx(held.scale.x, game.HAND_SCALE)), "live hand uses compact screen-space scale")
	await capture("live_encounter")
	director.persistence.discard()
	if failures:
		quit(1)
		return
	print("PASS: full-screen map, battle-only graveyards, explicit actual costs, rest exit, removed help entry, three eased camera views, interruption, clamps and view persistence")
	quit(0)
