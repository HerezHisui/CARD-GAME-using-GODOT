# Covers: Original route and RNG parity for 50 fixed seeds, all floors and every room's reachability state.
extends SceneTree

const Routes = preload("res://scripts/run_routes.gd")
const Director = preload("res://scripts/run_director.gd")
# Captured against the original director methods before wrapper integration.
const ORIGINAL_RESULTS_SHA256 := "6fa650e49dd9affe7a40eccae01999e5e1ae1f4e91454f57427ce15ee66b2fe6"

var director: Node
var failures := 0
var comparisons := 0
var result_hash := HashingContext.new()

func _initialize() -> void:
	result_hash.start(HashingContext.HASH_SHA256)
	call_deferred("run")

func same(actual: Variant, expected: Variant, label: String) -> void:
	comparisons += 1
	result_hash.update(var_to_bytes(expected))
	if actual != expected:
		failures += 1
		if failures <= 10: push_error("FAILED: " + label)

func compare_reachable(rooms: Array, static_rng: RandomNumberGenerator) -> void:
	var rooms_before: Array = rooms.duplicate(true)
	for current: int in range(-1, rooms.size()):
		director.current = current
		for is_cleared: bool in [false, true]:
			director.cleared = [current] if is_cleared else []
			var cleared_before: Array = director.cleared.duplicate()
			for active: bool in [false, true]:
				director.battle_active = active
				var rng_before: int = director.rng.state
				for id: int in rooms.size():
					same(Routes.reachable(id, rooms, current, director.cleared, active),
						director.reachable(id), "reachable room %d from %d" % [id, current])
				same(director.rng.state, rng_before, "wrapper reachability preserves RNG")
				same(static_rng.state, rng_before, "static reachability preserves RNG")
				same(director.cleared, cleared_before, "reachability preserves cleared rooms")
	same(rooms, rooms_before, "static reachability preserves rooms")
	same(director.rooms, rooms_before, "wrapper reachability preserves rooms")

func compare_seed(seed_value: int, floor_value: int) -> void:
	director.floor_number = floor_value
	director.rng.seed = seed_value
	director.rooms = [{"stale": true}]
	director.cleared = [0, 1]
	director.current = 1
	director.battle_active = false
	var original_rooms: Array = director.rooms
	var original_cleared: Array = director.cleared
	var static_rng := RandomNumberGenerator.new()
	static_rng.seed = seed_value
	# Include continuation states, not only a freshly seeded generator.
	for draw: int in range(seed_value % 7):
		director.rng.randi()
		static_rng.randi()
	var rooms: Array = [{"stale": true}]
	director.generate_map()
	Routes.generate_map(rooms, static_rng)
	same(rooms, director.rooms, "generated rooms")
	same(static_rng.state, director.rng.state, "generation RNG state")
	same(director.cleared, [], "generation clears completed rooms")
	same(director.current, -1, "generation resets current room")
	same(is_same(director.rooms, original_rooms), true, "rooms array identity preserved")
	same(is_same(director.cleared, original_cleared), true, "cleared array identity preserved")
	same(Routes.MAP_ROWS, director.MAP_ROWS, "map row constant")
	same(Routes.EVENT_TYPES, director.EVENT_TYPES, "event type constant")
	compare_reachable(rooms, static_rng)

func run() -> void:
	# Keep the director outside the tree: these methods must not need UI or a manager.
	director = Director.new()
	for seed_value: int in range(50):
		for floor_value: int in [1, 2, 3]:
			compare_seed(seed_value, floor_value)
	var checksum := result_hash.finish().hex_encode()
	if checksum != ORIGINAL_RESULTS_SHA256:
		failures += 1
		push_error("FAILED: original route output checksum")
	director.free()
	if failures > 0:
		quit(1)
		return
	print("PASS: run_routes_smoke (%d comparisons, 50 seeds, floors 1-3)" % comparisons)
	quit(0)
