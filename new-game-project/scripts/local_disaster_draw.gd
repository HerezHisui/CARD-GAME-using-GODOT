extends RefCounted
## Optional local human Disaster draw gate. LAN and AI always retain automatic draws.
var game: Node
var waiting := false
var serial := -1

func _init(owner_game: Node) -> void:
	game = owner_game

func enabled() -> bool:
	if not is_instance_valid(game): return false
	return preload("res://scripts/versus_match.gd").DISASTER_DRAW_BUTTON \
		and game.encounter_kind == "versus" and game.disaster_is_human \
		and not game.lan_remote_prep and not game.lan_remote_disaster

func resolve() -> bool:
	if not enabled() or not game.run_director.battle_active or game.phase == game.Phase.GAME_OVER: return false
	if game.enemy_hand.size() >= 6 or game.enemy_deck.all(func(card): return game.is_sealed(card)): return true
	if maxi(0, 1 + game.buff_value(false, "draw")) == 0: return true
	var encounter: int = game.encounter_serial
	serial = encounter
	waiting = true
	game.disaster_actions.busy = true
	game.disaster_waiting = true
	game._set_phase(game.Phase.ENEMY, "Draw a Disaster card from the deck")
	game.presentation.remind_to_draw(true)
	while waiting:
		if not is_instance_valid(game): return false
		if encounter != game.encounter_serial or game.phase == game.Phase.GAME_OVER: break
		await game.get_tree().process_frame
	if not is_instance_valid(game) or encounter != game.encounter_serial: return false
	cancel()
	return game.phase != game.Phase.GAME_OVER

func draw() -> void:
	if not waiting or not enabled() or serial != game.encounter_serial or game.phase != game.Phase.ENEMY: return
	var director: Node = game.run_director
	if director.modal.visible or director.privacy_screen.visible or game.get_tree().paused: return
	waiting = false
	game.get_node("HUD/Root/DeckDrawButton").disabled = true
	game.presentation.remind_to_draw(false)
	game.enemy_draw_cards(maxi(0, 1 + game.buff_value(false, "draw")))

func refresh_button() -> void:
	if not waiting: return
	var director: Node = game.run_director
	var button: Button = game.get_node("HUD/Root/DeckDrawButton")
	button.disabled = director.modal.visible or director.privacy_screen.visible
	button.get_node("DeckCountLabel").text = str(game.enemy_deck.size())

func cancel() -> void:
	if not waiting: return
	waiting = false
	game.disaster_waiting = false
	game.disaster_actions.busy = false
	game.presentation.remind_to_draw(false)
	game.get_node("HUD/Root/DeckDrawButton").disabled = true
