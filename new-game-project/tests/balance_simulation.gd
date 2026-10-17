extends SceneTree
const SimGame = preload("res://tests/balance_sim_game.gd")
const VARIANTS := ["baseline", "opening", "ramp", "triage", "combined"]
var game: Node
var policy := RandomNumberGenerator.new()
var results := []
func _initialize() -> void: call_deferred("run")

func run() -> void:
	Engine.time_scale = 100.0
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	game.set_script(SimGame)
	root.add_child(game)
	current_scene = game
	var director = game.run_director
	director.persistence.enabled = false
	director.persistence.set_process(false)
	game.set_process(false)
	var variants = ["baseline"] if "--baseline" in OS.get_cmdline_user_args() else VARIANTS
	if "--triage-paths" in OS.get_cmdline_user_args():
		for variant in ["baseline", "combined"]:
			for route in 4:
				var hp := 20
				for node in 5:
					await battle(variant, route * 5 + node, hp)
					var entry: Dictionary = results.back()
					entry.route = route + 1
					entry.node = node + 1
					hp = int(entry.hp_after_triage)
					if not entry.win: break
		var triage_file = FileAccess.open("res://tests/artifacts/balance_triage_results.json", FileAccess.WRITE)
		triage_file.store_string(JSON.stringify({"samples":results}, "  "))
		triage_file.close()
		print("PASS: %d carried-HP encounters across eight five-node routes" % results.size())
		quit()
		return
	for variant in variants:
		for sample in 20:
			await battle(variant, sample)
		print("Completed ", variant, ": 20 encounters")
	var path = "res://tests/artifacts/balance_baseline_recheck.json" if variants.size() == 1 else "res://tests/artifacts/balance_floor1_results.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed_start":17102600, "variants":variants, "samples":results}, "  "))
	file.close()
	print("PASS: %d simulated encounters; raw results: %s" % [variants.size() * 20, path])
	quit()

func battle(variant: String, sample: int, starting_hp: int = 20) -> void:
	paused = false
	game.clear_battle()
	await process_frame
	var director = game.run_director
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	director.run_active = true
	director.floor_number = 1
	director.encounter = "battle"
	director.collection = director.character_deck(0)
	director.rng.seed = 17102600 + sample
	game.player_run_buffs = {"cadet":1}
	game.enemy_run_buffs.clear()
	game.player_hp = starting_hp
	game.smooth_opening = variant in ["opening", "combined"]
	game.action_ramp = variant in ["ramp", "combined"]
	game.victory_triage = variant in ["triage", "combined"]
	game.combat_hp_final = starting_hp
	game.victory_healing = 0
	game.won = false
	game.outcome = "timeout"
	game.early_hits = [0, 0]
	game.early_damage = [0, 0]
	game.damage_by_card.clear()
	game.incoming_total = 0
	policy.seed = 991700 + sample
	seed(17102600 + sample)
	game.start_encounter(director.collection, "battle", 1, sample % 4)
	var first = game.player_first
	var frames = 0
	var played_round = 0
	while game.phase != game.Phase.GAME_OVER and game.turn <= 40 and frames < 30000:
		frames += 1
		if director.screen == "buff":
			var options = director.buff_choices
			var chosen = options[policy.randi_range(0, options.size() - 1)]
			for buff in options:
				if buff.id in ["health", "strength", "energy", "draw"]:
					chosen = buff
					break
			director.select_buff(chosen.id)
		elif game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY] and played_round != game.turn:
			played_round = game.turn
			if game.phase == game.Phase.PLAYER_DRAW: game._on_draw_button_pressed()
			await process_frame
			play_turn()
			game._on_end_turn_pressed()
		await process_frame
	var entry = {"variant":variant, "sample":sample + 1, "seed":17102600 + sample, "specialty":sample % 4, "player_first":first, "win":game.won, "outcome":game.outcome, "rounds":game.turn, "hp_start":starting_hp, "hp_lost":starting_hp - game.combat_hp_final, "net_hp_lost":starting_hp - game.player_hp, "hp_after_triage":game.player_hp, "victory_healing":game.victory_healing, "incoming_total":game.incoming_total, "early_hits":game.early_hits.duplicate(), "early_damage":game.early_damage.duplicate(), "opening_blocker":game.opening_blocker, "player_buffs":game.player_buffs.duplicate(), "enemy_buffs":game.enemy_buffs.duplicate(), "damage_by_card":game.damage_by_card.duplicate()}
	results.append(entry)
	if game.outcome == "timeout":
		push_error("Simulation timed out: " + str(entry))
		quit(1)

func play_turn() -> void:
	for action in 4:
		var empty = game._response_slots().filter(func(slot): return game._get_card_in_slot(slot) == null)
		var affordable = game.get_hand_cards().filter(func(card): return not card.card_data.get("utility", false) and not game.is_sealed(card.card_data) and int(card.card_data.cost) <= game.preparedness)
		if empty.is_empty() or affordable.is_empty(): break
		var card = affordable[policy.randi_range(0, affordable.size() - 1)]
		var lane = empty[policy.randi_range(0, empty.size() - 1)]
		var occupied = empty.filter(func(slot): return game._get_card_in_slot(game._threat_slots()[game._response_slots().find(slot)]) != null)
		if not occupied.is_empty() and policy.randf() < 0.75: lane = occupied[policy.randi_range(0, occupied.size() - 1)]
		card.place_on_slot(lane)
		game.on_card_played(card)
		if not game.board_input.action.is_empty(): game.board_input.cancel()
	var allies = game._response_slots().map(func(slot): return game._get_card_in_slot(slot)).filter(func(card): return card != null and card.is_alive())
	if not allies.is_empty() and policy.randf() < 0.5 and game.plans.can_arm():
		game.plans.arm("brace" if policy.randf() < 0.5 else "coordinate", [allies[policy.randi_range(0, allies.size() - 1)]])
