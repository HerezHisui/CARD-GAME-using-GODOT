extends RefCounted
## Room events: the event screen and its choices. State stays on the run director, which keeps thin wrappers.

const Sfx = preload("res://scripts/sfx_call.gd")
## Screen layout. Edit it in the editor; the card tiles are still made in code.
const EventScene = preload("res://scenes/ui/ui_event.tscn")

static func show_event(director: Node) -> void:
	var key: String = "%d:%d" % [director.floor_number, director.current]
	if director.event_key != key:
		director.event_key = key
		var in_map: bool = director.current >= 0 and director.current < director.rooms.size()
		director.event_type = str(director.rooms[director.current].get("event", "locked")) if in_map else "locked"
		if director.event_type == "": director.event_type = "locked"
		director.event_resolved = false
		director.event_cards.clear()
		if director.event_type == "locked": director.event_cards = director.offers(1)
		elif director.event_type == "science":
			var burn: Dictionary = director.catalog_card("steam_team")
			burn.name = "Experimental Steam Team"
			burn.on_hit.burn = int(burn.on_hit.burn) + 2
			var poison: Dictionary = director.catalog_card("hazmat_team")
			poison.name = "Experimental Hazmat Team"
			poison.on_hit.poison = int(poison.on_hit.poison) + 1
			director.event_cards.assign([burn, poison])
	var group_name: String
	match director.event_type:
		"radio":
			director.reset_panel("THE EMERGENCY RADIO", "Kit: Hazard Forecast, Search and Rescue.", "event")
			group_name = "Radio"
		"rooftop":
			director.reset_panel("ROOFTOP DRILLS", "Energy loss lasts the rest of the run.", "event")
			group_name = "Rooftop"
		"science":
			director.reset_panel("THE SCIENCE LAB", "", "event")
			group_name = "Science"
		"infirmary":
			director.reset_panel("A VOLUNTEER'S OFFER", "Paperwork: spend 1 energy to discard it.", "event")
			group_name = "Infirmary"
		"lost_found":
			director.reset_panel("LOST AND FOUND", "", "event")
			group_name = "LostFound"
		_:
			director.reset_panel("A LOCKED CLASSROOM", "", "event")
			group_name = "Locked"
	# The layout lives in ui_event.tscn: one group of buttons per event. Only this event's group stays.
	var box: Control = director.centered_screen(EventScene)
	for other in box.get_children():
		if other is VBoxContainer and other.name != group_name: other.free()
	var group: Control = box.get_node(group_name)
	match group_name:
		"Radio":
			var buy: Button = director.hook_button(group.get_node("BuyButton"), director.resolve_event.bind("radio_buy"))
			buy.disabled = director.coins < 20
		"Rooftop":
			director.hook_button(group.get_node("TrainButton"), director.resolve_event.bind("training"))
		"Science":
			var row: Control = group.get_node("Stock")
			for i in range(director.event_cards.size()):
				var take: Callable = director.resolve_event.bind("science_%d" % i) if director.game.player_hp > 3 else Callable()
				director._card_tile(director.event_cards[i], row, take, "Take card · -3 HP")
		"Infirmary":
			var treatment: Button = group.get_node("TreatmentButton")
			treatment.text = "Full treatment · +%d HP · add Paperwork" % director.healing_gain(8)
			var treat: Button = director.hook_button(treatment, director.resolve_event.bind("treatment"))
			treat.disabled = director.game.player_hp >= director.game.hero_max_hp()
			var short_break: Button = group.get_node("RestButton")
			short_break.text = "Short break · +%d HP · free" % director.healing_gain(3)
			director.hook_button(short_break, director.resolve_event.bind("rest"))
		"LostFound":
			var trade: Button = director.hook_button(group.get_node("TradeButton"), director.show_remove_cards.bind("event"))
			trade.disabled = director.collection.size() <= 5
		"Locked":
			var risk: Button = director.hook_button(group.get_node("RiskButton"), director.event_risk)
			risk.disabled = director.game.player_hp <= 3
	if group.has_node("SafeButton"):
		director.hook_button(group.get_node("SafeButton"), director.resolve_event.bind("safe"))

static func resolve_event(director: Node, choice: String) -> void:
	if director.screen != "event" or director.event_resolved: return
	if choice in ["risk", "science_0", "science_1"] and director.game.player_hp <= 3: return
	if choice == "radio_buy" and director.coins < 20: return
	director.event_resolved = true
	match choice:
		"risk":
			director.game.player_hp -= 3
			director.coins += 30
			Sfx.play("supplies_gained")
			director.add_collection_card(director.event_cards[0].duplicate(true))
		"radio_buy":
			director.coins -= 20
			director.add_collection_card(director.catalog_card("scout"))
			director.add_collection_card(director.catalog_card("tutor"))
		"training": director.game.add_global_buff(true, "drill_tactics", true)
		"science_0", "science_1":
			director.game.player_hp -= 3
			director.add_collection_card(director.event_cards[int(choice.right(1))].duplicate(true))
		"treatment":
			director.game.player_hp = mini(director.game.hero_max_hp(), director.game.player_hp + 8)
			director.add_collection_card({"id":"paperwork", "name":"Paperwork", "type":"response", "element":"clearance",
				"cost":1, "attack":0, "health":1, "utility":true, "effect":"delay"})
		"rest": director.game.player_hp = mini(director.game.hero_max_hp(), director.game.player_hp + 3)
		_:
			director.coins += 10
			Sfx.play("supplies_gained")
	director.finish_room()
