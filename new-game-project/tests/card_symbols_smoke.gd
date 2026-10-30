# Covers: Imported pixel symbols, tint caching, all card effect layouts, and seal timing labels.
extends SceneTree
const UI = preload("res://scripts/ui_theme.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func check_layout(card: Node) -> void:
	var bounds: Rect2 = card._symbol_bounds()
	for badge: Control in card._status_row.get_children():
		var rect := Rect2(card._status_row.position + badge.position, badge.size)
		check(bounds.encloses(rect), "symbol stays inside its allocated face area")
		check(not badge.tooltip_text.is_empty(), "symbol retains its meaning in a tooltip")
		var label := badge.get_node_or_null("Count") as Label
		if label: check(label.size.x <= badge.size.x, "count stays inside its badge")

func run() -> void:
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/symbols/inventory.json"))
	for kind in inventory.symbols:
		var texture := UI.icon(kind, Color.WHITE)
		check(texture != null and texture.get_size() == Vector2(24, 24), "imported mask: " + kind)
		check(texture.resource_path.ends_with(".svg"), "white texture uses imported asset: " + kind)
	for alias in inventory.aliases:
		check(UI.icon(alias) == UI.icon(inventory.aliases[alias]), "alias shares cached tint: " + alias)
	for kind in inventory.runtime_data_keys:
		check(not UI.icon(kind, Color.WHITE).resource_path.ends_with("fallback.svg"), "data key has a glyph: " + kind)
	var tinted := UI.icon("burn", Color(0.2, 0.4, 0.6, 0.5))
	check(tinted == UI.icon("burn", Color(0.2, 0.4, 0.6, 0.5)), "tinted masks are cached")
	var image := tinted.get_image()
	var opaque_found := false
	for y in 24:
		for x in 24:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.1:
				opaque_found = true
				check(absf(pixel.r - 0.2) < 0.01 and absf(pixel.a - 0.5) < 0.01, "arbitrary tint and alpha")
	check(opaque_found, "mask contains visible pixels")
	check(UI.icon("on", UI.GOLD) != UI.icon("on", UI.DISABLED), "theme states retain separate tints")
	var game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var card = load("res://scenes/card_3d.tscn").instantiate()
	game.add_child(card)
	card.preview_only = true
	card.setup({"id":"symbols", "name":"Symbol fixture", "type":"response", "element":"evac", "cost":1,
		"attack":2, "health":4, "modifier":"armored", "effect":"draw", "on_hit":{"burn":2},
		"condition":{"status":"burn", "threshold":2}, "status_bonus":2, "utility_power":1})
	card.statuses = {"poison":3, "bleed":12, "healing_reduced":2, "barrier":3}
	card._refresh_face()
	await process_frame
	check(card._status_row.visible, "creature symbols are visible")
	check(card._status_row.has_node("Condition"), "conditional effect is visible")
	check(card._status_row.has_node("StatusBonus"), "status bonus is visible")
	check(card._status_row.get_node("Bleed/Count").text == "12", "active status count is preserved")
	check(card._status_row.get_node("Burn/Count").text == "2", "on-hit amount is preserved")
	check_layout(card)
	var before: int = card._status_row.get_child_count()
	for i in 30: card._add_effect_icon("burn", i + 1, "Fixture %d" % i)
	await process_frame
	check(card._status_row.get_child_count() == before + 30, "every symbol remains visible without overflow collapse")
	check_layout(card)
	card.card_data.utility = true
	card._refresh_face()
	await process_frame
	check(card._status_row.has_node("Draw"), "utility primary effect appears once in the grid")
	check_layout(card)
	card.preview_only = false
	card.card_data.seal_round = game.turn + 1
	card._refresh_face()
	check(card._seal_label.text == "NEXT · R%d" % (game.turn + 1), "pending seal round is visible")
	check("Pending" in card._seal_label.tooltip_text, "pending seal retains full rules")
	card.card_data.seal_round = game.turn
	card._refresh_face()
	check(card._seal_label.text == "SEALED · R%d" % game.turn, "active seal is distinct from pending seal")
	card.card_data.seal_round = game.turn - 1
	card._refresh_face()
	check(not card._seal_label.visible, "expired seal label disappears")
	card.queue_free()
	await process_frame
	if failures: quit(1)
	else:
		print("PASS: imported symbols, aliases, cached tint states, uncapped bounded layout, counts and seal timing")
		quit()
