extends Node
## Restores the classroom environment exactly after a boss encounter or a settings change.
var game: Node
var active := false
var original: Dictionary = {}
var environment: Environment

func setup(owner_game: Node) -> void:
	game = owner_game
	environment = game.get_node("WorldEnvironment").environment
	for property in ["fog_enabled", "fog_light_color", "fog_density", "fog_sky_affect",
			"volumetric_fog_density", "volumetric_fog_enabled"]:
		original[property] = environment.get(property)

func set_active(enabled: bool) -> void:
	active = enabled
	refresh()

func refresh() -> void:
	if environment == null: return
	for property in original: environment.set(property, original[property])
	if not active or not game.boss_fog_enabled: return
	# Depth fog works in Compatibility too. The table stays clear; the distant classroom fades.
	environment.fog_enabled = true
	environment.fog_light_color = Color("55565b")
	environment.fog_density = 0.018
	environment.fog_sky_affect = 0.6
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.008

func _exit_tree() -> void:
	if environment != null:
		for property in original: environment.set(property, original[property])
