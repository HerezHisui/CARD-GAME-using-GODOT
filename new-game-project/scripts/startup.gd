extends Control
## Launch-only splash. Menu returns go straight to run_director.show_title().
signal finished
@export var next_scene := "res://scenes/game_3d.tscn"
@export var hold_seconds := 1.8
var elapsed := 0.0
var dismissing := false
var transition: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$StudioLogo.modulate.a = 0.0
	transition = create_tween()
	transition.tween_property($StudioLogo, "modulate:a", 1.0, 0.35)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= hold_seconds and not dismissing: dismiss()

func _input(event: InputEvent) -> void:
	# Consume the complete press/release pair while this splash exists.
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		if event.is_pressed() and not event.is_echo() and elapsed >= 0.15: dismiss()

func dismiss() -> void:
	if dismissing: return
	dismissing = true
	if transition: transition.kill()
	transition = create_tween()
	transition.tween_property($StudioLogo, "modulate:a", 0.0, 0.3)
	transition.tween_interval(0.15)
	transition.tween_callback(complete)

func complete() -> void:
	# Do not carry a held dismissal button into the menu's focused Start/Continue control.
	if Input.is_anything_pressed():
		transition = create_tween()
		transition.tween_interval(0.05)
		transition.tween_callback(complete)
		return
	finished.emit()
	if not next_scene.is_empty(): get_tree().change_scene_to_file(next_scene)

func _exit_tree() -> void:
	if transition: transition.kill()
