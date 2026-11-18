extends Node3D
const SeatFigures = preload("res://scripts/seat_figures.gd")
const StandeeFigure = preload("res://scripts/standee_figure.gd")
## The fan's centre above the Grip_R bone, in the Janitor's own units (janitor_character.gd update_floating_cards).
const FAN_LIFT := Vector3(0, .24, .035)
## How far in front of the picture the fan sits, in the standee's own units.
const HAND_FRONT := 0.05
var game: Node
var signature := -1 # run_save invalidates this when restoring an encounter.
var character: Node3D
var figure: Node3D
var far_standee: Node3D # null while the Janitor shows at the far seat.
var applied := "" # The "far|near" pair of figure ids built now.
var home := Vector3.ZERO # The Janitor's place. Behind a standee his unseen body moves so the fan sits in its hand.

func setup(manager: Node) -> void:
	game = manager
	character = preload("res://scripts/janitor_character.gd").new()
	add_child(character)
	var anchor: Node3D = game.find_child("OpponentPosition", true, false)
	character.global_position = anchor.global_position
	# Supplied mesh faces +Z already; the existing anchor faces imported -Z-forward characters.
	character.scale = Vector3.ONE * 2.65
	character.position.y += 0.25
	home = character.position
	# The Preparedness figure on the other seat. Hidden unless the camera is at the Disaster seat.
	# It hangs off the game, not this node, because this node is hidden at the Disaster seat.
	figure = preload("res://scripts/standee_figure.gd").make_for(game)
	game.add_child(figure)
	figure.place_at(game.find_child("PlayerPosition", true, false))

func refresh() -> void:
	var count: int = game.enemy_hand.size()
	var active: bool = is_instance_valid(game.run_director) and game.run_director.battle_active
	var presentation_on: bool = preload("res://scripts/versus_match.gd").SIDE_BY_SIDE_HUD
	character.set_fixed_pose(presentation_on and game.encounter_kind == "versus" and active)
	character.set_encounter(active)
	_apply_figures()
	# Face-down backs only display count; seals do not change their appearance.
	if signature < 0: character.hand_count = -1
	character.set_hand_count(count if active else 0)
	signature = count

## Puts the room's figure at the far seat and the leader at the near seat (scripts/seat_figures.gd).
## Runs every frame: it rebuilds only when the pair of ids changed.
func _apply_figures() -> void:
	var far := SeatFigures.far_id(game)
	if not SeatFigures.usable(far): far = "janitor"
	var near := SeatFigures.near_id(game)
	if not StandeeFigure.CUTS.has(near): near = ""
	if far + "|" + near == applied:
		# set_encounter turns the cloth back on, so it is stopped again behind a standee.
		if far != "janitor": character.cloth.running = false
		return
	var old_far := applied.get_slice("|", 0)
	var old_near := applied.get_slice("|", 1)
	applied = far + "|" + near
	if far != old_far: _set_far(far)
	if near != old_near: _set_near(near)

## The far seat. The Janitor's skeleton, fan and played card stay live; only his body hides behind a standee.
func _set_far(id: String) -> void:
	if is_instance_valid(far_standee): far_standee.queue_free()
	far_standee = null
	character.find_child("JanitorMesh", true, false).visible = id == "janitor"
	character.position = home
	if id == "janitor":
		character.cloth.running = character.active_encounter and not character.fixed_pose
		return
	character.cloth.running = false
	# A child of this node, so the lines that hide and show the far seat hide and show it too.
	far_standee = StandeeFigure.new()
	far_standee.build(id)
	add_child(far_standee)
	far_standee.place_at(game.find_child("OpponentPosition", true, false))
	# Faces the player (+Z), like the Janitor's mesh.
	far_standee.rotation_degrees.y = 0.0
	far_standee.show()
	var point := SeatFigures.hand(id)
	if point == Vector2.INF: return
	# Move the unseen dealer so the centre of the fan sits at the standee's hand.
	var hand_at := far_standee.to_global(Vector3(point.x, point.y, HAND_FRONT))
	character.global_position += hand_at - fan_centre()

## Where the centre of the card fan is now.
func fan_centre() -> Vector3:
	return character.holding.global_position + character.global_basis * FAN_LIFT

## The near seat. The figure is swapped in one step, so `figure` is valid on every frame.
func _set_near(id: String) -> void:
	# The spike's override keeps its own figure.
	if StandeeFigure.leader(game) != "": return
	var next: Node3D
	if id == "":
		next = preload("res://scripts/preparedness_figure.gd").new()
	else:
		next = StandeeFigure.new()
		next.build(id)
	game.add_child(next)
	next.place_at(game.find_child("PlayerPosition", true, false))
	next.visible = figure.visible
	var old := figure
	figure = next
	old.queue_free()

func play_card(definition: Dictionary, target := Vector3.ZERO) -> void:
	refresh()
	character.play_card(definition, target)

func release_card() -> void:
	character.release_card()

func release_position() -> Vector3:
	return character.released_origin

func cancel_action() -> void:
	character.set_encounter(false)
	character.cancel_action()
	character.set_hand_count(0)
	character.cloth.reset_simulation()
