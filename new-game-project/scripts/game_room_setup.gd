extends RefCounted
## One-time room build for the battle scene: classroom, board slots, lighting and the colour finish.
## Called once from game_3d_manager.gd _ready through thin wrappers.

# =================================================================== ENVIRONMENT
static func build_environment(game: Node3D) -> void:
	var school := preload("res://scripts/supplied_classroom.gd").new()
	game.add_child(school)

# =================================================================== BOARD
## Cards, hit areas and drop highlights share the imported board's painted slot centers.
static func build_board(game: Node3D) -> void:
	var playmat := preload("res://scripts/card_playmat.gd")
	for slot: MeshInstance3D in game.get_node("Slots").get_children():
		var column := int(str(slot.name).right(1)) - 1
		var row := 0 if str(slot.name).begins_with("Threat") else 1
		slot.position = Vector3(playmat.SLOT_COLUMNS[column] * playmat.WIDTH,
			playmat.SLOT_HEIGHT, playmat.SLOT_ROWS[row] * playmat.DEPTH)
		# A flat overlay sits just above the recess floor; a box adds a raised top face.
		var highlight := PlaneMesh.new()
		highlight.size = Vector2(1.1, 1.5)
		slot.mesh = highlight
		slot.scale = Vector3(game.BOARD_SCALE, 1, game.BOARD_SCALE)
	game.add_child(playmat.new())

# =================================================================== LIGHTING
static func build_lighting(game: Node3D) -> void:
	var env_node = game.get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("9fa8af")
		env.ambient_light_energy = 0.24
		# Preserve the supplied metallic lockers' colour with soft environment
		# reflections, while the visible background and diffuse room stay dark.
		var reflection_sky := Sky.new()
		var reflection_material := ProceduralSkyMaterial.new()
		reflection_material.sky_top_color = Color(.55, .59, .64)
		reflection_material.sky_horizon_color = Color(.61, .63, .65)
		reflection_material.ground_horizon_color = Color(.36, .38, .39)
		reflection_material.ground_bottom_color = Color(.27, .28, .29)
		reflection_sky.sky_material = reflection_material
		env.sky = reflection_sky
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.04
		env.adjustment_saturation = 0.82
		var enhanced := RenderingServer.get_current_rendering_method() == "forward_plus"
		env.ssao_enabled = enhanced
		env.ssao_radius = 0.65
		env.ssao_intensity = 1.3
		env.ssao_power = 1.15
		env.ssao_detail = 0.8
		env.ssil_enabled = enhanced
		env.ssil_radius = 3.0
		env.ssil_intensity = 0.65
		env.volumetric_fog_enabled = enhanced
		env.volumetric_fog_density = 0.002
		env.volumetric_fog_albedo = Color("b4b4a3")
		env.volumetric_fog_anisotropy = 0.55
		env.glow_enabled = enhanced
		env.glow_intensity = 0.65
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.2
		env.glow_hdr_scale = 1.4
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level in 7: env.set_glow_level(level, [0.8, 0.65, 0.4, 0.2, 0.1, 0.0, 0.0][level])

static func build_visual_finish(game: Node3D) -> void:
	# Only color-grade the 3D world, not the HUD.
	var layer := CanvasLayer.new()
	layer.name = "ClassroomFinish"
	layer.layer = 0
	game.add_child(layer)
	var effect := ColorRect.new()
	effect.name = "ClarityAndSharpness"
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/classroom_finish.gdshader")
	effect.material = material
	layer.add_child(effect)
