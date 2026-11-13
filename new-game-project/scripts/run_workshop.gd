extends RefCounted
## Workshop: card upgrades and their preview. State stays on the run director, which keeps thin wrappers.

const Sfx = preload("res://scripts/sfx_call.gd")
const UI = preload("res://scripts/ui_theme.gd")
## Screen layouts. Edit them in the editor; the card tiles are still made in code.
const UpgradeScene = preload("res://scenes/ui/ui_upgrade.tscn")
const UpgradePreviewScene = preload("res://scenes/ui/ui_upgrade_preview.tscn")

static func show_upgrade(director: Node) -> void:
	director.reset_panel("THE WORKSHOP", "Each card can upgrade twice.", "upgrade")
	# The layout lives in ui_upgrade.tscn; the card tiles are made here.
	director.unpack_screen(UpgradeScene)
	director.setup_sort_controls(director.content.get_node("SortRow"), true)
	var scroll: ScrollContainer = director.content.get_node("Cards")
	var grid: GridContainer = scroll.get_node("Grid")
	director.fit_card_grid(grid, scroll)
	for i in director.sorted_indices(director.collection, director.upgrade_sort, director.upgrade_descending):
		var card: Dictionary = director.collection[i]
		var preview: Callable = director.show_upgrade_preview.bind(i) if director.can_upgrade(card) else Callable()
		director._card_tile(card, grid, preview, "Preview upgrade")
		if not director.can_upgrade(card):
			grid.get_child(grid.get_child_count() - 1).tooltip_text = "This card has reached its two-upgrade limit."
			grid.get_child(grid.get_child_count() - 1).get_child(0).add_child(
				director.label("Fully upgraded", 14, UI.GOLD))
	director.hook_button(director.content.get_node("LeaveButton"), director.finish_room)

static func upgrade(director: Node, index: int) -> void:
	if index < 0 or index >= director.collection.size() or not director.can_upgrade(director.collection[index]): return
	director.collection[index] = upgraded_definition(director, director.collection[index])
	Sfx.play("upgrade_confirmed")
	director.finish_room()

static func upgraded_definition(director: Node, card: Dictionary) -> Dictionary:
	var result: Dictionary = card.duplicate(true)
	if not director.can_upgrade(card): return result
	var tier: int = director.upgrade_level(card) + 1
	result.upgrades = tier
	if result.get("utility", false):
		if tier == 1 and int(result.cost) > 0: result.cost = int(result.cost) - 1
		elif result.get("effect", "") in ["move", "tutor", "scout", "recover"]:
			if tier == 2: result.refund_energy = int(result.get("refund_energy", 0)) + 1
		else: result.utility_power = int(result.get("utility_power", 0)) + 1
	else:
		match str(result.get("element", "")):
			"evac":
				if tier == 1:
					result.attack = int(result.attack) + 1
					if int(result.get("on_play_draw", 0)) > 0:
						result.on_play_draw = int(result.on_play_draw) + 1
				else:
					result.health = int(result.health) + 1
					result.cost = maxi(0, int(result.cost) - 1)
					if int(result.get("on_play_draw", 0)) == 0: result.on_play_draw = 1
			"douse":
				if tier == 1:
					result.attack = int(result.attack) + 1
				var has_burn: bool = int(result.get("on_hit", {}).get("burn", 0)) > 0
				if (tier == 1 and has_burn) or (tier == 2 and not has_burn):
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.burn = int(hits.get("burn", 0)) + 1
					result.on_hit = hits
				if tier == 2:
					result.health = int(result.health) + 1
					result.leech = int(result.get("leech", 0)) + 1
			"clearance":
				if tier == 1:
					result.attack = int(result.attack) + 1
				var has_poison: bool = int(result.get("on_hit", {}).get("poison", 0)) > 0
				if (tier == 1 and has_poison) or (tier == 2 and not has_poison):
					var hits: Dictionary = result.get("on_hit", {}).duplicate(true)
					hits.poison = int(hits.get("poison", 0)) + 1
					result.on_hit = hits
				if tier == 2:
					result.health = int(result.health) + 1
					result.status_bonus = int(result.get("status_bonus", 0)) + 2
			"brace":
				if tier == 1:
					result.health = int(result.health) + 2
				var armored: bool = director.game.definition_has_modifier(result, "armored")
				if (tier == 1 and armored) or (tier == 2 and not armored):
					var base_armor: int = 1 if director.game.definition_has_modifier(result, "armored") else 0
					result.armor_value = int(result.get("armor_value", base_armor)) + 1
					var traits: Array = result.get("modifiers", []).duplicate()
					if result.get("modifier", "") != "armored" and "armored" not in traits: traits.append("armored")
					result.modifiers = traits
				if tier == 2:
					result.health = int(result.health) + 1
					result.thorns = int(result.get("thorns", 0)) + 1
			_:
				result.attack = int(result.attack) + 1
				result.health = int(result.health) + 1
	result.name = str(result.name) + "+"
	return result

static func show_upgrade_preview(director: Node, index: int) -> void:
	if not director.can_upgrade(director.collection[index]): return
	director.reset_panel("UPGRADE PREVIEW", "", "upgrade_preview")
	# The layout lives in ui_upgrade_preview.tscn; the two card tiles go on each side of the arrow.
	director.unpack_screen(UpgradePreviewScene)
	var row: Control = director.content.get_node("Row")
	director._card_tile(director.collection[index], row)
	row.move_child(row.get_child(row.get_child_count() - 1), 0)
	director._card_tile(upgraded_definition(director, director.collection[index]), row)
	director.hook_button(director.content.get_node("ConfirmButton"), director.upgrade.bind(index))
	director.hook_button(director.content.get_node("BackButton"), director.show_upgrade)
