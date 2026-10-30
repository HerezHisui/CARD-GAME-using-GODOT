extends PanelContainer
## Dismissal is presentation state only; the encounter remains authoritative.
var announcement_key := ""
var dismissed := false

func update_intent(key: String, message: String, active: bool) -> void:
	if key != announcement_key:
		announcement_key = key
		dismissed = false
	$IntentLabel.text = message
	visible = active and not dismissed

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		# Keep the panel present through press and release so neither reaches the board.
		if not event.pressed:
			dismissed = true
			hide.call_deferred()
