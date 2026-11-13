extends RefCounted

static func debug_available(game: Node, battle_active: bool) -> bool:
	return battle_active \
		and not (is_instance_valid(game.dragged_hand_card) and game.dragged_hand_card.is_dragging) \
		and game.board_input.action.is_empty() \
		and game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY]

static func _debug_selected_card(targets: Array, selected: int) -> Node:
	if selected < 0 or selected >= targets.size(): return null
	if not is_instance_valid(targets[selected]): return null
	var card: Node = targets[selected]
	if not card.is_alive() or card.preview_only: return null
	return card if card.in_hand or is_instance_valid(card.current_slot) else null

# The caller checkpoints only after an accepted edit and its face refresh.
static func _debug_set_card_stat(value: float, card: Node, key: String) -> bool:
	if card == null or (key != "cost" and card.card_data.get("utility", false)): return false
	card.card_data[key] = maxi(1 if key == "health" else 0, int(value))
	if key == "health": card.max_health = maxi(card.max_health, int(card.card_data.health))
	card._refresh_face()
	return true

# ---- Debug screens (moved from run_director.gd; the director keeps thin wrappers) ----
const DebugPasswordScene = preload("res://scenes/ui/ui_debug_password.tscn")
const DebugScene = preload("res://scenes/ui/ui_debug.tscn")

static func show_debug(director: Node) -> void:
	if director.screen == "debug":
		director.close_modal()
		return
	if not director.debug_available() or (director.modal.visible and director.screen != "menu"): return
	director.debug_from_menu = director.screen == "menu"
	director.reset_panel("DEBUG ACCESS", "", "debug_password")
	# The layout lives in ui_debug_password.tscn.
	director.unpack_screen(DebugPasswordScene)
	var password: LineEdit = director.content.get_node("DebugPassword")
	var error: Label = director.content.get_node("PasswordError")
	var submit := func():
		if password.text != "*****":
			error.text = "Incorrect password."
			return
		password.text = ""
		if not director.debug_available():
			director.cancel_debug_password()
			return
		director._open_debug("*****")
	password.text_submitted.connect(func(_text): submit.call())
	director.hook_button(director.content.get_node("UnlockButton"), submit)
	director.hook_button(director.content.get_node("CancelButton"), director.cancel_debug_password)
	password.grab_focus()

static func open_debug(director: Node, password: String) -> void:
	if password != "*****" or director.screen != "debug_password" or not director.debug_available(): return
	var game: Node = director.game
	director.reset_panel("DEBUG VALUES", "", "debug")
	# The layout lives in ui_debug.tscn; each SpinBox there is named after its value.
	director.unpack_screen(DebugScene)
	var fields := {}
	for spec in [
		["player_hp", "Player HP", 1, game.hero_max_hp()], ["enemy_hp", "Enemy HP", 1, game.enemy_max_hp],
		["energy_cap", "Energy cap", 1, 30], ["preparedness", "Energy", 0, 30],
		["tension_cap", "Tension cap", 1, 30], ["tension", "Tension", 0, 30],
		["coins", "Supplies", 0, 9999], ["plans", "Plans", 0, 2],
	]:
		var field: SpinBox = director.content.get_node("Values/" + spec[0])
		field.min_value = spec[2]
		field.max_value = spec[3]
		field.value = director.coins if spec[0] == "coins" else \
			(game.plans.tokens if spec[0] == "plans" else game.get(spec[0]))
		fields[spec[0]] = field
	director.hook_button(director.content.get_node("ApplyButton"), func():
		for key in fields:
			if key == "coins": director.coins = int(fields[key].value)
			elif key == "plans": game.plans.tokens = int(fields[key].value)
			else: game.set(key, int(fields[key].value))
		game.preparedness = mini(game.preparedness, game.energy_cap)
		game.tension = mini(game.tension, game.tension_cap)
		game._refresh_bars()
		game.log_event("Debug values applied.")
		director.close_modal()
		director.persistence.checkpoint()
	)
	debug_card_controls(director)
	var boss_row := HBoxContainer.new()
	boss_row.name = "BossSelection"
	director.content.add_child(boss_row)
	var bosses := OptionButton.new()
	bosses.name = "BossPicker"
	for title in ["Floor 1 · Janitor", "Floor 2 · Janitor", "Floor 3 · Midnight Warden"]:
		bosses.add_item(title)
	bosses.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_row.add_child(bosses)
	director.button("Enter boss", func(): director.debug_enter_boss(bosses.selected + 1), boss_row)
	director.hook_button(director.content.get_node("CancelButton"), director.close_modal)

static func debug_enter_boss(director: Node, boss_floor: int) -> bool:
	if director.screen != "debug" or boss_floor not in [1, 2, 3]: return false
	# Reuse the run collection and normal encounter initializer; never bypass the coin or Warden setup.
	if director.collection.is_empty(): director.new_run()
	director.floor_number = boss_floor
	director.generate_map()
	director.current = int(director.rooms.back().id)
	director.encounter = "boss"
	director.intel_revealed = false
	director.battle_active = true
	director.run_active = true
	director.game.player_hp = director.game.hero_max_hp()
	director.action_cancel = Callable()
	director.modal.hide()
	director.screen = ""
	director.get_tree().paused = false
	director.game.start_encounter(director.collection, director.encounter, director.floor_number,
		director.rng.randi_range(0, 3))
	return true

static func debug_card_controls(director: Node) -> void:
	var game: Node = director.game
	var status_row: Control = director.content.get_node("StatusRow")
	var targets := game.get_tree().get_nodes_in_group("cards").filter(func(card):
		return card.is_alive() and not card.preview_only and (card.in_hand or is_instance_valid(card.current_slot)))
	var target: OptionButton = status_row.get_node("DebugCard")
	for i in targets.size():
		var card: Node = targets[i]
		var location := "HAND" if card.in_hand else str(card.card_data.get("type", "")).to_upper()
		target.add_item("%d / %s / %s" % [i + 1, location, card.card_data.name])
	if targets.is_empty(): target.add_item("No cards")
	target.disabled = targets.is_empty()
	var fields := {}
	for spec in [["cost", "Cost"], ["attack", "ATK"], ["health", "HP"]]:
		var field: SpinBox = status_row.get_node("Stats/Debug" + str(spec[1]))
		fields[spec[0]] = field
		field.value_changed.connect(director._debug_set_card_stat.bind(targets, target, spec[0]))
	target.item_selected.connect(func(_index): director._debug_load_card_stats(targets, target, fields))
	director._debug_load_card_stats(targets, target, fields)
	var status: OptionButton = status_row.get_node("Status")
	for key in ["strength", "bleed", "burn", "poison", "barrier", "healing_reduced"]: status.add_item(key)
	var amount: SpinBox = status_row.get_node("Amount")
	director.hook_button(status_row.get_node("SetStatusButton"), func():
		var card: Node = director._debug_selected_card(targets, target)
		if card == null: return
		var key := status.get_item_text(status.selected)
		if amount.value == 0: card.statuses.erase(key)
		else: card.statuses[key] = int(amount.value)
		card._refresh_face()
		game.vfx.sync_status(card)
		game.log_event("Debug status: %s · %s %d" % [card.card_data.name, key, int(amount.value)])
		director.persistence.checkpoint()
	).disabled = targets.is_empty()
