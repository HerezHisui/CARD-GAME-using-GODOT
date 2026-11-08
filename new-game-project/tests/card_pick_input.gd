extends RefCounted
## Test helper for the card picker. The tiles have no "Choose" button any more:
## a card is chosen with a real double click on its tile.

## The picker tile for a card name, or the first visible tile when the name is empty.
static func tile(parent: Node, card_name: String = "") -> Control:
	for node: Node in parent.find_children("*", "PanelContainer", true, false):
		if not node.has_meta("pick_name") or not (node as Control).is_visible_in_tree(): continue
		if card_name.is_empty() or str(node.get_meta("pick_name")) == card_name: return node
	return null

## A real double click on the middle of the control, through the viewport input path.
## The caller waits a frame or two afterwards.
static func double_click(viewport: Viewport, control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	viewport.push_input(move, true)
	for second in [false, true]:
		for down in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.global_position = point
			event.pressed = down
			event.double_click = second and down
			viewport.push_input(event, true)
