extends Node
## Direct board picks and relocation gestures. Selection never spends a card/token by itself.
var game: Node
var action: Dictionary = {}

func setup(manager: Node) -> void:
	game = manager

func clear() -> void: action.clear()

func pick(title: String, cards: Array, callback: Callable, cancel_callback: Callable, tactic: String = "") -> void:
	game.set_board_view(true)
	action = {"kind":"pick", "title":title, "cards":cards.duplicate(), "callback":callback, "cancel":cancel_callback,
		"tactic":tactic}

func relocation(source: Node) -> void:
	game.set_board_view(true)
	action = {"kind":"relocate", "title":"Drag another friendly card onto an empty lane.", "source":source, "cancel":game.cancel_move_effect}

## Emergency Extraction: drag an ally onto the empty lane it escapes to, like a relocation.
## Nothing moves now: drop(slot, ally) arms the tactic (game.complete_move_effect).
func extraction(drop: Callable) -> void:
	game.set_board_view(true)
	action = {"kind":"relocate", "title":"Drag an ally onto an empty lane for Emergency Extraction.", "source":null,
		"cancel":game.cancel_move_effect, "drop":drop}

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
