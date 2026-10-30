extends Node3D
var game: Node
var signature := -1 # run_save invalidates this when restoring an encounter.
var character: Node3D

func setup(manager: Node) -> void:
	game = manager
	character = preload("res://scripts/janitor_character.gd").new()
	add_child(character)
	var anchor: Node3D = game.find_child("OpponentPosition", true, false)
	character.global_position = anchor.global_position
	# Supplied mesh faces +Z already; the existing anchor faces imported -Z-forward characters.
	character.scale = Vector3.ONE * 2.65
	character.position.y += 0.25

func refresh() -> void:
	var count: int = game.enemy_hand.size()
	var active: bool = is_instance_valid(game.run_director) and game.run_director.battle_active
	character.set_encounter(active)
	# Face-down backs only display count; seals do not change their appearance.
	if signature < 0: character.hand_count = -1
	character.set_hand_count(count if active else 0)
	signature = count

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
