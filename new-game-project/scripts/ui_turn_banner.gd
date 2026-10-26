extends CanvasLayer
## Big "TURN N" band that plays at the start of each round. Never blocks the mouse.
## Restyle it in scenes/ui/ui_turn_banner.tscn.

const SLIDE := 40.0

var game: Node
var hint: Control
var tween: Tween

@onready var band: Control = $Band
@onready var text_box: Control = $Band/Text
@onready var number_label: Label = $Band/Text/Number

func setup(owner_game: Node) -> void:
	game = owner_game
	hint = game.get_node_or_null("HUD/Root/PhaseLabel")
	band.visible = false

func is_playing() -> bool:
	return tween != null and tween.is_running()

func play(number: int) -> void:
	if tween: tween.kill()
	number_label.text = str(number)
	band.visible = true
	band.modulate.a = 0.0
	band.pivot_offset = band.size / 2
	band.scale = Vector2(1, 0.6)
	text_box.position.x = -SLIDE
	if hint: hint.visible = false
	tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Fade and grow in, text slides in from the left.
	tween.tween_property(band, "modulate:a", 1.0, 0.15)
	var grow := tween.parallel().tween_property(band, "scale", Vector2.ONE, 0.15)
	grow.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var slide := tween.parallel().tween_property(text_box, "position:x", 0.0, 0.15)
	slide.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_property(band, "modulate:a", 0.0, 0.25)
	tween.tween_callback(stop)

func stop() -> void:
	if tween: tween.kill()
	tween = null
	band.visible = false
	if hint: hint.visible = true

func _process(_delta: float) -> void:
	# Hide while a modal screen (Deck, Map, Menu) is open.
	if not is_playing() or game == null or game.run_director == null: return
	if game.run_director.modal.visible: stop()
