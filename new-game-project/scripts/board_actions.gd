extends Node
## Direct board picks and relocation gestures. Selection never spends a card/token by itself.
var game: Node
var action: Dictionary = {}

func setup(manager: Node) -> void:
	game = manager
	for slot in game._response_slots():
		var body: CollisionObject3D = slot.get_node("StaticBody3D")
		body.input_event.connect(func(_camera, event, _position, _normal, _shape):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: choose_slot(slot)
		)

func clear() -> void: action.clear()

func pick(title: String, cards: Array, callback: Callable, cancel_callback: Callable) -> void:
	game.clear_hand_hover()
	action = {"kind":"pick", "title":title, "cards":cards.duplicate(), "callback":callback, "cancel":cancel_callback}

func relocation(source: Node) -> void:
	game.clear_hand_hover()
	action = {"kind":"relocate", "title":"Drag another friendly card onto an empty lane. Esc skips movement.", "source":source, "cancel":game.cancel_move_effect}

func destination(card: Node, callback: Callable) -> void:
	action = {"kind":"place", "title":"Click an empty friendly lane for Emergency Extraction. Esc cancels.", "card":card, "callback":callback, "cancel":Callable()}

func click_card(card: Node) -> bool:
	if action.is_empty() or game.run_director.modal.visible: return false
	match str(action.kind):
		"relocate":
			if game.plans.eligible(card) and card != action.source: game.select_moving_ally(card)
		"pick":
			if card in action.cards and card.is_alive():
				var callback: Callable = action.callback
				clear()
				callback.call(card)
	return true

func choose_slot(slot: Node3D) -> void:
	if action.get("kind", "") != "place" or game.run_director.modal.visible or game._get_card_in_slot(slot) != null: return
	var callback: Callable = action.callback
	clear()
	callback.call(slot)

func cancel() -> void:
	if action.is_empty(): return
	var callback: Callable = action.get("cancel", Callable())
	clear()
	if is_instance_valid(game.moving_ally) and game.moving_ally.is_dragging:
		game.moving_ally.is_dragging = false
		game.moving_ally.is_relocating = false
		game.end_hand_drag(game.moving_ally)
		if game.moving_ally.current_slot: game.moving_ally.place_on_slot(game.moving_ally.current_slot)
	if callback.is_valid(): callback.call()
