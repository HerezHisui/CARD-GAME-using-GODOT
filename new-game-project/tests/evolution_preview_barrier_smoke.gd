extends "res://tests/balance_economy_smoke.gd"
## Audit A6: the evolution confirmation shows the same Barrier the real entry gives.
## Costs 2, 3, 4 with zero and two matching materials, entry nerf on and off.

var shown_total := -1

# Runs on the next idle frame, while the confirmation is open. Reads the total, then cancels.
func read_preview() -> void:
	var text := ""
	for label: Label in game.run_director.content.find_children("*", "Label", true, false): text += label.text
	var found := RegEx.create_from_string("Total Barrier: (\\d+) / 3").search(text)
	shown_total = int(found.get_string(1)) if found != null else -1
	game.run_director.balance_evolution_decision(false)

func preview_total(evolution: Dictionary, materials: Array) -> int:
	shown_total = -1
	read_preview.call_deferred()
	await game.run_director.confirm_balance_evolution(evolution, materials)
	return shown_total

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	game.balance_patch_override = true
	var pool: Dictionary = Decks.pool("disaster")
	for nerf in [true, false]:
		for cost in [2, 3, 4]:
			for matching in [0, 2]:
				reset()
				game.entry_barrier_nerf_override = nerf
				var evolution: Dictionary = game.balance_card(pool.evolutions.worldbreaker)
				evolution.cost = cost
				var materials: Array = []
				for lane in cost:
					var base: Dictionary = pool.base.tremor if lane < matching else pool.base.cinder_cloud
					materials.append(unit(base, lane))
				var label := "nerf %s, cost %d, %d matching" % [str(nerf), cost, matching]
				var shown: int = await preview_total(evolution, materials)
				expect(await game.disaster_evolve(evolution, materials, game._threat_slots()[0]), "evolves: " + label)
				var evolved: Node = game._get_card_in_slot(game._threat_slots()[0])
				var actual := int(evolved.statuses.get("barrier", 0))
				expect(shown == mini(3, actual), "preview %d matches actual %d: %s" % [shown, actual, label])
	game.entry_barrier_nerf_override = null
	game.balance_patch_override = null
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("evolution_preview_barrier_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
