# Covers: the Versus-only HUD look (versus_hud.gd): clutter hidden, Energy and Tension pips, the deck list,
# the CLOSED map sign, the Out of Tension note and the glowing End turn. Singleplayer must look the same.
# Headless: it checks nodes and numbers, not how things look.
extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

func frames(count: int = 3) -> void:
	for i in count: await process_frame

func run() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	var director: Node = game.run_director
	var hud: Node = director.versus_hud
	var supplies: CanvasItem = game.get_node("HUD/TopBar/SuppliesLabel")
	var mark: Label = game._player_hp_ui.get_node("HealthMark")
	expect(hud != null and not hud.active, "Versus HUD: off before a match")
	# Singleplayer: nothing changes.
	game.clear_battle()
	game.encounter_kind = "battle"
	director.battle_active = true
	await frames()
	expect(not hud.active, "Singleplayer: the Versus HUD stays off")
	expect(game._view_forward_btn.visible and game._view_back_btn.visible, "Singleplayer: W and S buttons stay")
	expect(supplies.visible and mark.text == "+", "Singleplayer: Supplies and the plus mark stay")
	director.battle_active = false
	# A Versus match.
	director.start_versus_match()
	director.screen = ""
	game.versus_hand_hidden = false
	await frames()
	expect(hud.active, "Versus HUD: on during a match")
	expect(not game._view_forward_btn.visible and not game._view_back_btn.visible, "Versus HUD: W and S buttons are hidden")
	expect(not supplies.visible and not game.get_node("HUD/TopBar/SuppliesIcon").visible, "Versus HUD: no Supplies counter")
	var enemy_mark: Label = game._enemy_hp_ui.get_node("HealthMark")
	expect(mark.text == "" and enemy_mark.text == "", "Versus HUD: no tag before the sides are known")
	expect(hud.energy_plate.visible and hud.tension_plate.visible, "Versus HUD: Energy and Tension plates show")
	var old_gauges := [director.prep.get_parent(), director.threat.get_parent()]
	expect(is_zero_approx(old_gauges[0].modulate.a) and is_zero_approx(old_gauges[1].modulate.a),
		"Versus HUD: the old gauges are clear")
	# P1 / P2 tags and the turn plate.
	director.versus_match.player1_side = "disaster"
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 4
	await frames()
	expect(mark.text == "P2" and enemy_mark.text == "P1", "Versus HUD: P1 and P2 tags follow the sides")
	expect(hud.turn_plate.visible and hud.round_label.text == "ROUND 4" and hud.side_label.text == "P2  PREPAREDNESS",
		"Versus HUD: the turn plate names the round and the side")
	game._set_phase(game.Phase.ENEMY)
	await frames()
	expect(hud.side_label.text == "P1  DISASTER", "Versus HUD: the turn plate follows the Disaster turn")
	expect(hud.energy_plate.modulate.a < 1.0 and is_equal_approx(hud.tension_plate.modulate.a, 1.0),
		"Versus HUD: the side that is not playing is dimmed")
	game._set_phase(game.Phase.SETUP)
	await frames()
	expect(not hud.turn_plate.visible, "Versus HUD: no turn plate before round 1")
	# The Deck button lists the real deck.
	expect(hud.deck_cards().size() == 24, "Deck: Preparedness shows its 24 cards")
	game.disaster_seat_on = true
	expect(hud.deck_cards().size() == 30 and hud.deck_title() == "DISASTER DECK",
		"Deck: the Disaster seat shows 24 cards and 6 evolutions")
	game.disaster_seat_on = false
	game.versus_hand_hidden = true
	director.show_deck()
	expect(director.screen != "deck", "Deck: it stays shut while the hands are hidden for the coin flip")
	game.versus_hand_hidden = false
	director.show_deck()
	await frames()
	expect(director.screen == "deck" and director.content.get_node("Tabs/DeckButton").text == "Cards (24)",
		"Deck: the Deck button opens the 24 Preparedness cards")
	director.close_modal()
	await frames()
	# The map is closed.
	director.toggle_map()
	await frames()
	var closed: Node = director.content.find_child("ClosedLabel", true, false)
	expect(director.screen == "map" and closed != null and closed.text == "CLOSED", "Map: Versus shows the CLOSED sign")
	director.toggle_map()
	await frames()
	expect(director.screen == "" and not director.modal.visible, "Map: the same button closes the sign")
	# Out of Tension.
	expect(director.DISASTER_REASONS.action_limit != hud.OUT_OF_TENSION
		and director.DISASTER_REASONS.action_limit == "Action limit reached. End your turn.",
		"Action limit: distinct from Out of Tension")
	expect(director.DISASTER_REASONS.no_tension == hud.OUT_OF_TENSION, "Out of Tension: no_tension uses the note")
	expect(director.DISASTER_REASONS.no_tension == "Not enough Tension.", "Out of Tension: the cost reason is unchanged")
	game.disaster_seat._refuse(null, hud.OUT_OF_TENSION)
	expect(hud.note.visible and hud.note_head.text == "OUT OF TENSION", "Out of Tension: a refused action shows the note")
	# End turn glows once the seated Disaster has no Tension.
	game.disaster_seat_on = true
	game.tension = 3
	await frames()
	expect(hud.pulse_tween == null, "End turn: no glow while there is Tension")
	game.tension = 0
	await frames()
	expect(hud.pulse_tween != null and hud.pulse_tween.is_valid(), "End turn: glows when the Disaster has no Tension")
	game.tension = 2
	await frames()
	expect(hud.pulse_tween == null and game._end_turn_btn.self_modulate == Color.WHITE,
		"End turn: the glow stops and the colour is back")
	game.disaster_seat_on = false
	# After the match everything is back.
	director.battle_active = false
	await frames()
	expect(not hud.active, "After the match: the Versus HUD is off")
	expect(game._view_forward_btn.visible and supplies.visible and mark.text == "+",
		"After the match: W, S, Supplies and the plus mark are back")
	expect(is_equal_approx(director.prep.get_parent().modulate.a, 1.0), "After the match: the old gauges are back")
	expect(not hud.note.visible, "After the match: the note is gone")
	game.clear_battle()
	director.get_tree().paused = false
	if failures > 0:
		push_error("versus_hud_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: versus_hud_smoke (%d checks)" % checks)
	quit(0)
