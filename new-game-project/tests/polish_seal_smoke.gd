extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: " + text)

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.clear_battle()
	game.encounter_kind = "versus"
	game.turn = 1
	game.add_card_to_hand({"id": "sealed", "name": "Quick Dash", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 3, "locked_until": 3})
	var card: Node = game.get_hand_cards()[0]
	var banner: Label = card._vp.get_child(0).get_node_or_null("SealBanner")
	expect(banner != null, "sealed hand has a banner")
	if banner != null:
		var artwork := Rect2(18, 72, 228, 144)
		expect(not Rect2(banner.position, banner.size).intersects(artwork), "banner stays outside artwork")
		expect(banner.visible and banner.text == "SEALED · 2 ROUNDS", "hand duration is visible")
		expect(card.sealed_drop_message() == "SEALED - wait 2 rounds.", "sealed drop provides a refusal message")
		expect("Cannot play" in banner.tooltip_text, "banner explains play restriction")
		expect(card._status_row.has_node("Sealed"), "existing lock icon stays")
		var director: Node = game.run_director
		expect(director.has_method("_refresh_seal_tooltip"), "3D hover has a HUD tooltip")
		if director.has_method("_refresh_seal_tooltip"):
			director.battle_active = true
			director.modal.hide()
			director.privacy_screen.hide()
			game.hovered_hand_card = card
			director._refresh_seal_tooltip()
			expect(director.seal_tooltip.visible and "Cannot play" in director.seal_tooltip.text,
				"hover explanation is rendered outside the card viewport")
		expect("Cannot play" in game.run_director.card_rules(card.card_data), "inspection explains seal")
		game.turn = 2
		await create_timer(0.2).timeout
		expect(banner.text == "SEALED · 1 ROUND", "countdown refreshes without changing locked_until")
		game.turn = 3
		card._refresh_face()
		expect(not banner.visible, "expired hand banner clears")
		expect(card.sealed_drop_message().is_empty(), "expired seal no longer refuses a drop")
		card.card_data.seal_round = 3
		card._refresh_face()
		expect(banner.visible and "SEALED" in banner.text, "active field seal has banner")
		expect("Attacks are allowed" in banner.tooltip_text, "field seal keeps accurate restriction")
		card.card_data.seal_round = 4
		card._refresh_face()
		expect("NEXT" in banner.text, "pending field seal is distinct")
		game.encounter_kind = "battle"
		card._refresh_face()
		expect(not banner.visible, "singleplayer presentation remains unchanged")
		card.preview_only = true
		card._refresh_face()
		expect(not banner.visible, "preview-only card safely omits manager-dependent banner")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("%s: polish_seal_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
