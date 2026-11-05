extends SceneTree
## Deck builder (scripts/deck_builder.gd) and the custom deck file in scripts/versus_decks.gd.
## The builder runs on its own here, without the game scene and without a director.

const DeckBuilder = preload("res://scripts/deck_builder.gd")
const VersusDecks = preload("res://scripts/versus_decks.gd")
const PREP := "preparedness"
const DISASTER := "disaster"
const TEST_SAVE := "user://test_deck_builder_smoke.cfg"  # never the real user://versus_decks.cfg

var failures := 0
var checks := 0
var done_decks: Array = []
var back_count := 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	var real_path := VersusDecks.save_path
	VersusDecks.save_path = TEST_SAVE
	remove_save()
	await check_prep_counts()
	await check_prep_tactics()
	await check_disaster()
	await check_done_and_back()
	check_save_file()
	await check_real_clicks()
	await check_preview()
	remove_save()
	VersusDecks.save_path = real_path
	expect(VersusDecks.save_path == "user://versus_decks.cfg", "save path is reset")
	if failures > 0:
		quit(1)
		return
	print("PASS: deck_builder_smoke (%d checks)" % checks)
	quit(0)


func make_builder(side: String, deck: Dictionary) -> Control:
	var builder: Control = DeckBuilder.new()
	root.add_child(builder)
	builder.setup(side, deck, null)
	builder.done.connect(func(d: Dictionary) -> void: done_decks.append(d))
	builder.back.connect(func() -> void: back_count += 1)
	await process_frame
	await process_frame
	return builder


func drop(builder: Control) -> void:
	builder.queue_free()
	await process_frame


func node(builder: Control, node_name: String) -> Control:
	return builder.find_child(node_name, true, false)


func press(builder: Control, node_name: String) -> void:
	var button := node(builder, node_name) as BaseButton
	if button == null:
		expect(false, "button exists: " + node_name)
		return
	button.pressed.emit()


func same_deck(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)


# Preparedness: Standard deck, add and remove, copy cap, pile cap, Reset.
func check_prep_counts() -> void:
	var b := await make_builder(PREP, VersusDecks.preset(PREP))
	expect(same_deck(b.current_deck(), VersusDecks.preset(PREP)), "prep: opens on the Standard deck")
	expect(not b.done_button.disabled, "prep: Done is enabled on the Standard deck")
	expect(b.main_label.text == "Main 24/24", "prep: main counter reads 24/24")
	expect(b.error_label.text == "", "prep: no error on the Standard deck")
	expect(node(b, "EvolutionCount") == null, "prep: no evolution counter")
	# Remove one Quick Dash: 23 cards, Done off, error shown.
	press(b, "Minus_main_quick_dash")
	expect(b.main.size() == 23, "prep: remove makes the main deck 23")
	expect(b.main.count("quick_dash") == 1, "prep: remove takes one copy")
	expect(b.main_label.text == "Main 23/24", "prep: counter reads 23/24")
	expect(b.count_labels["main/quick_dash"].text == "1/2", "prep: row count reads 1/2")
	expect(b.done_button.disabled, "prep: Done is disabled below 24")
	expect(b.error_label.text.contains("needs exactly 24"), "prep: error names the missing card")
	b.done_button.pressed.emit()
	expect(done_decks.is_empty(), "prep: Done does not emit an invalid deck")
	# Add it back.
	press(b, "Plus_main_quick_dash")
	expect(b.main.size() == 24 and b.main.count("quick_dash") == 2, "prep: add puts the copy back")
	expect(not b.done_button.disabled, "prep: Done is enabled again at 24")
	# Third copy refused.
	press(b, "Minus_main_scout")
	expect(b.main.size() == 23, "prep: room for one more card")
	expect(node(b, "Plus_main_quick_dash").disabled, "prep: + is off at 2 copies")
	press(b, "Plus_main_quick_dash")
	expect(b.main.count("quick_dash") == 2 and b.main.size() == 23, "prep: a third copy is refused")
	# Full pile refused.
	var empty_id := first_unused(b.main, b.main_pool)
	press(b, "Plus_main_" + empty_id)
	expect(b.main.size() == 24, "prep: + on an unused card fills the pile")
	var other_id := first_unused(b.main, b.main_pool)
	expect(node(b, "Plus_main_" + other_id).disabled, "prep: + is off when the pile is full")
	press(b, "Plus_main_" + other_id)
	expect(b.main.size() == 24 and other_id not in b.main, "prep: a full pile takes no more cards")
	expect(node(b, "Minus_main_" + other_id).disabled, "prep: - is off at 0 copies")
	# Reset.
	press(b, "ResetButton")
	expect(same_deck(b.current_deck(), VersusDecks.preset(PREP)), "prep: Reset to Standard restores the preset")
	expect(not b.done_button.disabled, "prep: Done is enabled after Reset")
	var row := node(b, "Row_main_evacuation")
	expect(row != null and row.tooltip_text.contains("\n"), "prep: an effect card has its full text in the tooltip")
	await drop(b)


func first_unused(pile: Array, pool: Dictionary) -> String:
	for id: String in pool:
		if id not in pile: return id
	return ""


# Preparedness tactics: Brace fixed, 2 more, max 2.
func check_prep_tactics() -> void:
	var b := await make_builder(PREP, VersusDecks.preset(PREP))
	var brace := node(b, "Tactic_brace") as CheckBox
	expect(brace.button_pressed and brace.disabled, "tactics: Brace is checked and locked")
	brace.button_pressed = false
	expect("brace" in b.tactics, "tactics: Brace cannot be unchecked")
	expect(node(b, "Tactic_supply").disabled, "tactics: a third pick is off while 2 are picked")
	(node(b, "Tactic_supply") as CheckBox).button_pressed = true
	expect(b.tactics.size() == 3 and "supply" not in b.tactics, "tactics: max 2 picks besides Brace")
	expect(not (node(b, "Tactic_supply") as CheckBox).button_pressed, "tactics: a refused pick is unchecked")
	(node(b, "Tactic_medicine") as CheckBox).button_pressed = false
	expect(b.tactics == ["brace", "coordinate"], "tactics: unchecking removes the pick")
	expect(b.done_button.disabled, "tactics: Done is off with 1 pick")
	expect(not node(b, "Tactic_supply").disabled, "tactics: other picks open again")
	(node(b, "Tactic_supply") as CheckBox).button_pressed = true
	expect(b.tactics == ["brace", "coordinate", "supply"], "tactics: a new pick is added")
	expect(not b.done_button.disabled, "tactics: Done is on with 2 picks")
	press(b, "ResetButton")
	expect(b.tactics == ["brace", "coordinate", "medicine"], "tactics: Reset restores the preset tactics")
	expect((node(b, "Tactic_medicine") as CheckBox).button_pressed, "tactics: Reset re-checks the boxes")
	expect(not (node(b, "Tactic_supply") as CheckBox).button_pressed, "tactics: Reset unchecks the others")
	await drop(b)


# Disaster: two sections, evolutions 6/6, pile cap.
func check_disaster() -> void:
	var b := await make_builder(DISASTER, VersusDecks.preset(DISASTER))
	var pool := VersusDecks.pool(DISASTER)
	expect(same_deck(b.current_deck(), VersusDecks.preset(DISASTER)), "disaster: opens on the Standard deck")
	expect(not b.done_button.disabled, "disaster: Done is enabled on the Standard deck")
	expect(b.evolution_label.text == "Evolutions 6/6", "disaster: evolution counter reads 6/6")
	expect(node(b, "Tactic_brace") == null, "disaster: no tactic boxes")
	var spell_id: String = pool.spells.keys()[0]
	expect(node(b, "Row_main_" + spell_id) != null, "disaster: spells are in the main deck section")
	expect(node(b, "Row_evolutions_wildfire") != null, "disaster: evolutions have their own section")
	expect(node(b, "Row_main_wildfire") == null, "disaster: evolutions are not in the main section")
	var unused := first_unused(b.evolutions, b.evolution_pool)
	expect(node(b, "Plus_evolutions_" + unused).disabled, "disaster: + is off when the pile has 6")
	press(b, "Plus_evolutions_" + unused)
	expect(b.evolutions.size() == 6, "disaster: the evolution pile cannot exceed 6")
	press(b, "Minus_evolutions_wildfire")
	expect(b.evolution_label.text == "Evolutions 5/6", "disaster: remove makes 5/6")
	expect(b.done_button.disabled, "disaster: Done is off with 5 evolutions")
	press(b, "Plus_evolutions_fissure")
	expect(b.evolutions.count("fissure") == 2 and b.evolutions.size() == 6, "disaster: add a second copy")
	expect(not b.done_button.disabled, "disaster: Done is on at 6/6")
	expect(VersusDecks.validate(DISASTER, b.current_deck()).ok, "disaster: changed deck passes validate")
	await drop(b)


# Done emits a valid deck; Back emits back.
func check_done_and_back() -> void:
	done_decks.clear()
	back_count = 0
	var b := await make_builder(PREP, VersusDecks.preset(PREP))
	press(b, "Minus_main_scout")
	press(b, "Plus_main_runner")
	press(b, "DoneButton")
	expect(done_decks.size() == 1, "done: Done emits once")
	if done_decks.size() == 1:
		var deck: Dictionary = done_decks[0]
		expect(VersusDecks.validate(PREP, deck).ok, "done: the emitted deck passes validate")
		expect(deck.main.count("runner") == 2 and "scout" not in deck.main, "done: the emitted deck has the change")
	press(b, "BackButton")
	expect(back_count == 1, "back: Back emits back")
	expect(done_decks.size() == 1, "back: Back does not emit done")
	await drop(b)


# The custom deck file: round trip, missing, broken, not a Dictionary, bad shape, invalid.
func check_save_file() -> void:
	remove_save()
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: missing file gives Standard")
	var custom := VersusDecks.preset(PREP)
	custom.main.erase("scout")
	custom.main.append("runner")
	custom.tactics = ["brace", "supply", "flank"]
	VersusDecks.save_custom(PREP, custom)
	expect(FileAccess.file_exists(TEST_SAVE), "save: the file is written at save_path")
	expect(same_deck(VersusDecks.load_custom(PREP), custom), "save: load gives back the saved deck")
	expect(same_deck(VersusDecks.load_custom(DISASTER), VersusDecks.preset(DISASTER)),
		"save: a side with no saved deck gives Standard")
	var evil := VersusDecks.preset(DISASTER)
	evil.evolutions[0] = "fissure"
	VersusDecks.save_custom(DISASTER, evil)
	expect(same_deck(VersusDecks.load_custom(DISASTER), evil), "save: Disaster round trip")
	expect(same_deck(VersusDecks.load_custom(PREP), custom), "save: saving one side keeps the other")
	write_text("[deck\npreparedness = {\"main\": [")  # broken on purpose: a ConfigFile parse error is expected
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: broken file gives Standard")
	write_value(PREP, "not a deck")
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: not a Dictionary gives Standard")
	write_value(PREP, {"main": "quick_dash", "evolutions": [], "tactics": []})
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: bad shape gives Standard")
	var short := VersusDecks.preset(PREP)
	short.main.resize(10)
	write_value(PREP, short)
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: invalid deck gives Standard")
	var copies := VersusDecks.preset(PREP)
	copies.main[0] = copies.main[1]
	copies.main[2] = copies.main[1]
	write_value(PREP, copies)
	expect(same_deck(VersusDecks.load_custom(PREP), VersusDecks.preset(PREP)), "save: 3 copies gives Standard")
	remove_save()


func write_text(text: String) -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func write_value(side: String, value: Variant) -> void:
	var file := ConfigFile.new()
	file.set_value("deck", side, value)
	file.save(TEST_SAVE)


func remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE): DirAccess.remove_absolute(TEST_SAVE)


# Real input path: a "+" button and Done, clicked with the mouse.
func check_real_clicks() -> void:
	done_decks.clear()
	var b := await make_builder(PREP, VersusDecks.preset(PREP))
	press(b, "Minus_main_quick_dash")
	var scroll := node(b, "CardScroll") as ScrollContainer
	scroll.ensure_control_visible(node(b, "Row_main_quick_dash"))
	await process_frame
	await process_frame
	await click(node(b, "Plus_main_quick_dash"))
	expect(b.main.count("quick_dash") == 2 and b.main.size() == 24, "click: a real click on + adds the card")
	await click(b.done_button)
	expect(done_decks.size() == 1, "click: a real click on Done emits done")
	await drop(b)


func click(target: Control) -> void:
	if target == null:
		expect(false, "click: target exists")
		return
	var center := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = center
	event.global_position = center
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


# The preview scene loads and opens a builder per side.
func check_preview() -> void:
	var scene: PackedScene = load("res://tests/deck_builder_preview.tscn")
	expect(scene != null, "preview: the scene loads")
	if scene == null: return
	var preview: Node = scene.instantiate()
	root.add_child(preview)
	await process_frame
	var disaster_button := preview.find_child("DisasterButton", true, false) as Button
	var prep_button := preview.find_child("PreparednessButton", true, false) as Button
	expect(disaster_button != null and prep_button != null, "preview: has both side buttons")
	if disaster_button != null:
		disaster_button.pressed.emit()
		await process_frame
		var builder: Node = preview.get("builder")
		expect(is_instance_valid(builder) and builder.side == DISASTER, "preview: Disaster opens the Disaster builder")
	if prep_button != null:
		prep_button.pressed.emit()
		await process_frame
		var builder: Node = preview.get("builder")
		expect(is_instance_valid(builder) and builder.side == PREP, "preview: Preparedness opens its builder")
	preview.queue_free()
	await process_frame
