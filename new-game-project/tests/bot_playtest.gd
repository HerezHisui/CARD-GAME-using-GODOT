extends SceneTree

var game: Node
var director: Node

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.selected_character = 0
	director.new_run()
	Engine.time_scale = 10.0
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.start_encounter(director.collection, "battle", 1, 0)
	var turns := 0
	while turns < 30:
		if not await wait_for_player():
			break
		turns += 1
		print("BOT turn %d, hand %d, energy %d, hp %d vs %d" % [
			turns, game.get_hand_cards().size(), game.preparedness, game.player_hp, game.enemy_hp])
		play_cards()
		await game._on_end_turn_pressed()
	var won: bool = game.phase == game.Phase.GAME_OVER and game.enemy_hp <= 0
	print("BOT RESULT: won=%s turns=%d phase=%d" % [won, turns, game.phase])
	quit()

func wait_for_player() -> bool:
	for i in range(1200):
		if game.phase == game.Phase.GAME_OVER:
			return false
		if game.phase == game.Phase.PLAYER_PLAY or game.phase == game.Phase.PLAYER_DRAW:
			return true
		await process_frame
	print("BOT STUCK: never reached the player's turn, phase=%d" % game.phase)
	return false

func play_cards() -> void:
	for card in game.get_hand_cards().duplicate():
		if card.card_data.get("utility", false): continue
		if not game.try_play_card(card): continue
		for slot in game._response_slots():
			if game._get_card_in_slot(slot) == null:
				card.place_on_slot(slot)
				game.on_card_played(card)
				break
