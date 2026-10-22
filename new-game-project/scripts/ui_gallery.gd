@tool
extends Control
## Gallery only: applies the per-node styles the game sets in code, so the gallery matches the game.
## Nothing in the game loads this scene.
const UI = preload("res://scripts/ui_theme.gd")

func _ready() -> void:
	# Same as run_director.gd _gauge(): energy uses RESPONSE, tension uses DANGER.
	for pair in [["EnergyBar", UI.RESPONSE], ["TensionBar", UI.DANGER]]:
		var bar: ProgressBar = find_child(pair[0], true, false)
		bar.add_theme_stylebox_override("background", UI.panel(UI.INSET, UI.BRONZE, 0))
		bar.add_theme_stylebox_override("fill", UI.bar(pair[1]))
	# Same as ui_theme.gd apply_hud(): player gold, enemy crimson, lag amber.
	for pair in [["PlayerHealth", UI.GOLD, UI.INSET], ["EnemyHealth", UI.CRIMSON, UI.TEXT]]:
		var health: Control = find_child(pair[0], true, false)
		health.get_node("PlayerHealthBar" if pair[0] == "PlayerHealth" else "EnemyHealthBar") \
			.add_theme_stylebox_override("fill", UI.bar(pair[1]))
		health.get_node("LagBar").add_theme_stylebox_override("fill", UI.bar(UI.AMBER))
		health.get_node("Value").add_theme_color_override("font_color", pair[2])
	# Same as card_3d.gd: card frames, a cost badge and an affinity band.
	find_child("ResponsePlate", true, false).add_theme_stylebox_override("panel", UI.card_frame(false))
	find_child("DisasterPlate", true, false).add_theme_stylebox_override("panel", UI.card_frame(true))
	find_child("CostBadge", true, false).add_theme_stylebox_override("panel", UI.badge_style(UI.RAISED))
	find_child("AffinityBand", true, false).add_theme_stylebox_override("normal", UI.affinity_band("evac"))
	# Same as run_director.gd modals: gold-edged panel with the industrial trim.
	var dialog: Control = find_child("DialogBox", true, false)
	dialog.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, UI.GOLD))
	UI.decorate(dialog)
	# Same as run_director.gd label(): sizes of 22 and up use the heading font.
	for label in find_children("*", "Label", true, false):
		if label.has_theme_font_size_override("font_size") and label.get_theme_font_size("font_size") >= 22:
			label.add_theme_font_override("font", UI.font(true))
