extends Node
## Only stable decisions and player turns are checkpointed; animation coroutines are never serialized.
const PATH := "user://unfinished_run_v1.json"
const DIRECTOR_FIELDS := ["collection", "acquisition_serial", "reward_stock", "rooms", "cleared", "current", "coins", "floor_number", "run_seed", "selected_character", "encounter", "battle_active", "buff_choices", "intel_revealed", "unlock_after", "event_key", "event_type", "event_cards", "event_resolved", "shop_key", "shop_stock", "shop_purchased", "deck_sort", "upgrade_sort", "deck_descending", "upgrade_descending"]
const GAME_FIELDS := ["deck", "enemy_deck", "enemy_evolution_deck", "enemy_hand", "player_graveyard", "graveyard_serial", "turn", "player_first", "energy_cap", "preparedness", "tension_cap", "tension", "player_hp", "enemy_hp", "enemy_max_hp", "player_buffs", "enemy_buffs", "player_run_buffs", "enemy_run_buffs", "encounter_kind", "player_barrier", "plan_hero_barrier", "adapted_round", "battle_log", "in_board_view", "view_mode", "coin_result", "coin_pick"]
const CARD_FIELDS := ["max_health", "statuses", "modifiers", "last_attack_turn", "planned_guard", "plan_attack_bonus", "plan_ignore_taunt", "base_definition"]
const BOSS_FIELDS := ["stage", "changed_round", "pillars_spawned", "pulse_resolved", "last_resolved_round", "last_prepared_round"]
var director: Node
var clock := 0.0
var restoring := false
var last_json := ""
var enabled := true

func setup(owner_director: Node) -> void:
	director = owner_director
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Regression runs use a disposable path, never the player's real save.
	for argument in OS.get_cmdline_args():
		if argument.contains("tests/"): enabled = false

func save_path() -> String: return PATH if enabled else "user://test_unfinished_run_%d.json" % hash(OS.get_cmdline_args())

func _process(delta: float) -> void:
	if not enabled: return
	clock += delta
	if clock >= 1.0:
		clock = 0
		checkpoint()

func read_save() -> Dictionary:
	if not FileAccess.file_exists(save_path()): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1: return {}
	if not parsed.get("director", {}).get("collection", []) is Array or parsed.director.collection.size() < 5: return {}
	return normalize(parsed)

func has_run() -> bool: return not read_save().is_empty()

func discard() -> void:
	last_json = ""
	if FileAccess.file_exists(save_path()): DirAccess.remove_absolute(save_path())

func normalize(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(normalize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = normalize(value[key])
		return result
	return value

func fields(node: Node, keys: Array) -> Dictionary:
	var result := {}
	for key in keys: result[key] = node.get(key)
	return result

func apply_fields(node: Node, data: Dictionary, keys: Array) -> void:
	for key in keys:
		if not data.has(key): continue
		if node.get(key) is Array: node.get(key).assign(data[key])
		else: node.set(key, data[key])

func checkpoint() -> bool:
	if restoring or not director.run_active: return false
	var game: Node = director.game
	if director._dragging() or not game.board_input.action.is_empty() or is_instance_valid(game.pending_utility): return false
	var destination: String = director.screen
	if director.battle_active:
		if destination not in ["buff", "coin"] and game.phase not in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]: return false
		if destination not in ["buff", "coin"]: destination = "battle"
	elif destination not in ["map", "shop", "event", "upgrade", "reward", "contingency_reward", "floor_buff"]:
		return false
	var cards: Array = []
	for card in game.get_hand_cards():
		cards.append({"data":card.card_data, "runtime":fields(card, CARD_FIELDS), "side":"hand", "lane":-1})
	for side in ["response", "disaster"]:
		var slots: Array = game._response_slots() if side == "response" else game._threat_slots()
		for i in slots.size():
			var card = game._get_card_in_slot(slots[i])
			if card and card.is_alive(): cards.append({"data":card.card_data, "runtime":fields(card, CARD_FIELDS), "side":side, "lane":i})
	var armed := {}
	if not game.plans.armed.is_empty():
		armed = {"kind":game.plans.armed.kind, "triggered":game.plans.armed.triggered, "targets":[], "destination":game._response_slots().find(game.plans.armed.destination)}
		for card in game.plans.armed.targets:
			if not game.plans.eligible(card): return false
			armed.targets.append(game._response_slots().find(card.current_slot))
	var snapshot := {"version":1, "screen":destination, "director":fields(director, DIRECTOR_FIELDS), "rng":str(director.rng.state), "game":fields(game, GAME_FIELDS), "phase":int(game.phase), "cards":cards, "enemy_caption":game._enemy_hp_ui.get_node("Caption").text, "plans":fields(game.plans, ["tokens", "auto_save", "saved_round", "committed_round", "unlocked"]), "armed":armed, "boss":fields(game.final_boss, BOSS_FIELDS) if is_instance_valid(game.final_boss) else {}}
	var encoded := JSON.stringify(snapshot)
	if encoded == last_json: return true
	var file := FileAccess.open(save_path() + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(encoded)
	file.close()
	if DirAccess.rename_absolute(save_path() + ".tmp", save_path()) != OK: return false
	last_json = encoded
	return true

func resume() -> bool:
	var snapshot := read_save()
	if snapshot.is_empty(): return false
	restoring = true
	var game: Node = director.game
	game.get_tree().paused = false
	game.clear_battle()
	apply_fields(director, snapshot.director, DIRECTOR_FIELDS)
	director.run_active = true
	director.rng.state = int(snapshot.rng)
	apply_fields(game, snapshot.game, GAME_FIELDS)
	game.player_hp = clampi(game.player_hp, 0, game.hero_max_hp())
	apply_fields(game.plans, snapshot.plans, ["tokens", "auto_save", "saved_round", "committed_round", "unlocked"])
	for entry in snapshot.cards:
		var card = game.Card3DScene.instantiate()
		game.add_child(card)
		card.add_to_group("cards")
		card.setup(entry.data)
		card.card_data = entry.data.duplicate(true)
		apply_fields(card, entry.runtime, CARD_FIELDS)
		if not entry.runtime.has("base_definition"):
			card.base_definition = entry.data.duplicate(true)
			if not card.card_data.get("utility", false): card.base_definition.health = maxi(1, card.max_health - int(game.buffs_for(card.card_data).get("health", 0)))
		if entry.side == "hand":
			card.reparent(game.hand_parent())
			game.hand.append(card)
		else:
			var slots: Array = game._response_slots() if entry.side == "response" else game._threat_slots()
			card.place_on_slot(slots[int(entry.lane)])
		card._refresh_face()
	game.arrange_hand_centered()
	if not snapshot.boss.is_empty():
		game.final_boss = preload("res://scripts/final_boss.gd").new()
		game.add_child(game.final_boss)
		game.final_boss.game = game
		apply_fields(game.final_boss, snapshot.boss, BOSS_FIELDS)
	game.plans.armed.clear()
	if not snapshot.armed.is_empty():
		var targets: Array = []
		for lane in snapshot.armed.targets: targets.append(game._get_card_in_slot(game._response_slots()[int(lane)]))
		if snapshot.armed.kind == "coordinate" and targets.size() > 1: targets.resize(1)
		game.plans.armed = {"kind":snapshot.armed.kind, "triggered":snapshot.armed.triggered, "targets":targets, "destination":game._response_slots()[int(snapshot.armed.destination)] if int(snapshot.armed.destination) >= 0 else null}
	game._set_phase(snapshot.phase, "Continue your turn" if director.battle_active else "Choose your next school room")
	game._enemy_hp_ui.get_node("Caption").text = snapshot.enemy_caption
	game._player_hp_ui.get_node("Caption").text = director.CHARACTERS[director.selected_character].name
	game._turn_label.text = "Turn %d" % game.turn
	if not snapshot.game.has("view_mode"): game.view_mode = game.View.BOARD if game.in_board_view else game.View.DESK
	game.in_board_view = game.view_mode == game.View.BOARD
	game._apply_view(game.view_settings(game.view_mode))
	game._refresh_view_hints()
	game._refresh_bars()
	game.update_deck_label()
	game.opponent_hand.signature = -1
	game.opponent_hand.refresh()
	director.screen = ""
	director.modal.hide()
	match str(snapshot.screen):
		"coin": game.resume_coin()
		"battle": pass
		"map": director.show_map()
		"shop": director.show_shop()
		"event":
			if director.encounter == "rest": director.show_rest()
			else: director.show_event()
		"upgrade": director.show_upgrade()
		"reward": director.show_rewards()
		"contingency_reward": director.show_contingency_reward(director.unlock_after, true)
		"floor_buff": director.show_floor_buffs(true)
		"buff": director.show_buff_choices(true)
	restoring = false
	return true
