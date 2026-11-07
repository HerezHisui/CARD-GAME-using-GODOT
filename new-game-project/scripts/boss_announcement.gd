extends Control
## Dismissal is presentation state only; the encounter remains authoritative.
const Sfx = preload("res://scripts/sfx_call.gd")
const MenuSkin = preload("res://scripts/suspended_menu.gd")
const UI = preload("res://scripts/ui_theme.gd")

var announcement_key := ""
var dismissed := false

func _ready() -> void:
	MenuSkin.apply_skin($Parchment, self)
	# Keep the existing white intent text readable on an inset inside the parchment.
	$IntentLabel.add_theme_color_override("font_color", Color.WHITE)
	$IntentLabel.add_theme_stylebox_override("normal", MenuSkin.box(UI.PANEL, MenuSkin.BRONZE, 14))
	$CloseButton.pressed.connect(_dismiss)

func _dismiss() -> void:
	dismissed = true
	hide.call_deferred()

func update_intent(key: String, message: String, active: bool) -> void:
	if key != announcement_key:
		announcement_key = key
		if active: Sfx.play("attack_warning")
		dismissed = false
	$IntentLabel.text = message
	visible = active and not dismissed

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		# Keep the panel present through press and release so neither reaches the board.
		if not event.pressed:
			_dismiss()
