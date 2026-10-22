extends RefCounted
## Supply room and card removal. State stays on the run director, which keeps thin wrappers.

const UI = preload("res://scripts/ui_theme.gd")
const CardRules = preload("res://scripts/run_card_rules.gd")

static func show_shop(director: Node) -> void:
	var key: String = "%d:%d" % [director.floor_number, director.current]
	if director.shop_key != key:
		director.shop_key = key
		director.shop_stock = director.offers(4)
		if director.floor_number >= 2:
			var remainder: Array = director.shop_stock.filter(
				func(card): return card.id not in ["barrier", "alarm_sweep"])
			director.shop_stock.clear()
			for id in ["barrier", "alarm_sweep"]:
				for card in director.catalog:
					if card.id == id:
						director.shop_stock.append(card.duplicate(true))
						break
			director.shop_stock.append(remainder[0])
			director.shop_stock.append(remainder[1])
		director.shop_purchased.clear()
	director.reset_panel("THE SUPPLY ROOM",
		"Buy as many stocked items as you can afford. Card prices scale with power. First aid restores up to 5 HP for 15 supplies. Stock stays fixed.",
		"shop")
	var row := HBoxContainer.new()
	director.content.add_child(row)
	for card in director.shop_stock:
		var sold: bool = card.id in director.shop_purchased
		var price: int = director.shop_price(card)
		director._card_tile(card, row,
			Callable(director, "buy").bind(card) if not sold and director.coins >= price else Callable(),
			"Buy card · -%d supplies" % price)
		if sold:
			row.get_child(row.get_child_count() - 1).get_child(0).add_child(director.label("SOLD OUT", 16, UI.GOLD))
		elif director.coins < price:
			row.get_child(row.get_child_count() - 1).get_child(0).add_child(
				director.label("Need %d supplies" % price, 14, UI.MUTED))
	director.button("First aid · +%d HP · -15 supplies" % director.healing_gain(5), Callable(director, "buy_heal"),
		director.content).disabled = director.coins < 15 \
		or director.game.player_hp >= director.game.hero_max_hp()
	director.button("Destroy 1 card · -30 supplies", Callable(director, "show_remove_cards").bind("shop"),
		director.content).disabled = director.coins < 30 or director.collection.size() <= 5
	director.button("Leave shop", Callable(director, "finish_room"), director.content)

static func shop_price(card: Dictionary) -> int:
	return CardRules.shop_price(card)

static func buy(director: Node, card: Dictionary) -> void:
	var stocked: Array = director.shop_stock.filter(func(item): return item.id == card.id)
	if stocked.is_empty() or card.id in director.shop_purchased: return
	var definition: Dictionary = stocked[0]
	var price: int = director.shop_price(definition)
	if director.coins < price: return
	director.coins -= price
	director.add_collection_card(definition.duplicate(true))
	director.shop_purchased.append(definition.id)
	director.show_shop()

static func buy_heal(director: Node) -> void:
	if director.coins < 15 or director.game.player_hp >= director.game.hero_max_hp(): return
	director.coins -= 15
	director.game.player_hp = mini(director.game.hero_max_hp(), director.game.player_hp + 5)
	director.show_shop()

static func show_remove_cards(director: Node, origin: String) -> void:
	if director.battle_active or origin not in ["shop", "rest", "event"]: return
	director.remove_origin = origin
	director.reset_panel("REMOVE A CARD", "Choose the exact copy to retire. Keep at least 5 cards. "
		+ ("Removal costs 30 supplies; the shop stays open." if origin == "shop"
		else ("This replaces healing or training at this rest node." if origin == "rest"
		else "Trade one card for 25 supplies.")), "remove")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	director.content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)
	director.fit_card_grid(grid, scroll)
	for i in director.sorted_indices(director.collection, director.deck_sort, director.deck_descending):
		director._card_tile(director.collection[i], grid, Callable(director, "preview_remove").bind(i),
			"Choose this copy")
	director.button("Cancel", Callable(director, "cancel_remove"), director.content)

static func preview_remove(director: Node, index: int) -> void:
	if index < 0 or index >= director.collection.size(): return
	director.remove_index = index
	director.reset_panel("DESTROY THIS COPY?",
		"This removes the card from your run deck. Your other copies are kept.", "remove_confirm")
	director._card_tile(director.collection[index], director.content)
	director.button("Destroy card · " + ("-30 supplies" if director.remove_origin == "shop"
		else ("+25 supplies" if director.remove_origin == "event" else "free")), Callable(director, "confirm_remove"),
		director.content).disabled = director.collection.size() <= 5 \
		or (director.remove_origin == "shop" and director.coins < 30)
	director.button("Back", Callable(director, "show_remove_cards").bind(director.remove_origin), director.content)

static func confirm_remove(director: Node) -> void:
	if director.screen != "remove_confirm" or director.collection.size() <= 5 or director.remove_index < 0 \
			or director.remove_index >= director.collection.size(): return
	if director.remove_origin == "shop" and director.coins < 30: return
	if director.remove_origin == "shop": director.coins -= 30
	director.collection.remove_at(director.remove_index)
	director.remove_index = -1
	if director.remove_origin == "shop": director.show_shop()
	else:
		if director.remove_origin == "event":
			director.coins += 25
			director.event_resolved = true
		director.finish_room()

static func cancel_remove(director: Node) -> void:
	if director.remove_origin == "shop": director.show_shop()
	elif director.remove_origin == "event": director.show_event()
	else: director.show_rest()
