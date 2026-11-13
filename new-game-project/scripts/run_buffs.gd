extends RefCounted
## Battle adaptations and floor rewards. State stays on the run director, which keeps thin wrappers.

const Sfx = preload("res://scripts/sfx_call.gd")
const UI = preload("res://scripts/ui_theme.gd")
const Rules = preload("res://scripts/battle_rules.gd")
## Screen layouts. Edit them in the editor; the buff tiles are still made in code.
const BuffChoicesScene = preload("res://scenes/ui/ui_buff_choices.tscn")
const FloorBuffsScene = preload("res://scenes/ui/ui_floor_buffs.tscn")

static func show_buff_choices(director: Node, restore_offers: bool) -> void:
	var game: Node = director.game
	Sfx.play("adaptation_offered")
	if not restore_offers: director.buff_choices.clear()
	var pool: Array = Rules.BUFFS.duplicate(true)
	if not restore_offers:
		for i in range(3):
			var index: int = director.rng.randi_range(0, pool.size() - 1)
			director.buff_choices.append(pool.pop_at(index))
	director.reset_panel("ROUND %d · BATTLE ADAPTATION" % game.turn,
		"Choose one adaptation · lasts this battle", "buff")
	# The layout lives in ui_buff_choices.tscn; the buff tiles are made here.
	var box: Control = director.centered_screen(BuffChoicesScene)
	box.custom_minimum_size.x = maxf(300, director.modal.size.x - 100)
	var heading: Label = box.get_child(0)
	heading.add_theme_font_size_override("font_size", 32)
	var row: Control = box.get_node("Row")
	var symbols := {
		"strength": "strength", "health": "regenerating", "energy": "refund_energy", "burn": "burn",
		"poison": "poison", "bleed": "bleed", "draw": "draw", "glass": "strength",
		"overclock": "refund_energy", "blood_pact": "bleed", "patient": "regenerating",
		"toxic_ward": "poison", "formation": "rally_all", "spines": "thorns", "precision": "piercing"
	}
	for buff in director.buff_choices:
		var pick: Button = director.choice_tile(buff.name, buff.description, director.select_buff.bind(buff.id), row)
		pick.clip_text = false
		pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pick.icon = UI.icon(symbols.get(buff.id, "strength"), UI.GOLD)
		pick.expand_icon = true
		pick.add_theme_constant_override("icon_max_width", 28)
		pick.custom_minimum_size.y = 76
		pick.add_theme_font_size_override("font_size", 24)
		var tile: Control = pick.get_parent().get_parent()
		tile.custom_minimum_size = Vector2(0, 290)
		var details: Label = tile.get_node("Box/Details")
		details.add_theme_font_size_override("font_size", 22)
	box.get_node("Summary").text = "CURRENT ADAPTATIONS\n" + buff_summary(game.player_buffs)
	box.get_node("Summary").add_theme_font_size_override("font_size", 22)
	# Skip the focus if the screen changed before this deferred call ran.
	var first_pick: Button = row.get_child(0).get_node("Box/PickButton")
	var focus_first := func(button) -> void:
		if is_instance_valid(button) and button.is_inside_tree():
			button.grab_focus()
	focus_first.call_deferred(first_pick)

static func select_buff(director: Node, id: String) -> void:
	if director.screen != "buff" or not director.buff_choices.any(func(buff): return buff.id == id): return
	director.game.add_global_buff(true, id)
	Sfx.play("adaptation_selected")
	director.close_modal()
	director.game.continue_round()

static func show_floor_buffs(director: Node, restore_offers: bool) -> void:
	if not restore_offers: director.buff_choices.clear()
	var pool: Array = Rules.RUN_BUFFS.duplicate(true)
	if not restore_offers:
		for i in range(3): director.buff_choices.append(pool.pop_at(director.rng.randi_range(0, pool.size() - 1)))
	director.reset_panel("FLOOR %d CLEARED · PERMANENT REWARD" % director.floor_number,
		"Lasts the whole run.", "floor_buff")
	# The layout lives in ui_floor_buffs.tscn; the buff tiles are made here.
	var box: Control = director.centered_screen(FloorBuffsScene)
	box.custom_minimum_size.x = maxf(300, director.modal.size.x - 100)
	var row: Control = box.get_node("Row")
	for buff in director.buff_choices:
		var pick: Button = director.choice_tile(buff.name, buff.description,
			director.select_floor_buff.bind(buff.id), row)
		director._style_reward_choice(pick, "strength")
	director.hook_button(box.get_node("ReturnButton"), director.return_title)

static func select_floor_buff(director: Node, id: String) -> void:
	if director.screen != "floor_buff" or not director.buff_choices.any(func(buff): return buff.id == id): return
	director.game.add_global_buff(true, id, true)
	Sfx.play("adaptation_selected")
	director.next_floor()

static func buff_summary(buffs: Dictionary) -> String:
	var names: PackedStringArray = []
	for id in buffs:
		var title: String = str(id).capitalize()
		for option in Rules.BUFFS + Rules.RUN_BUFFS + Rules.CHARACTER_BUFFS:
			if option.id == id:
				title = option.name
				break
		names.append("%s ×%d" % [title, int(buffs[id])])
	return "None" if names.is_empty() else " / ".join(names)
