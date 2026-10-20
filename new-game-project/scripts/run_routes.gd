extends RefCounted

const MAP_ROWS := 11
const EVENT_TYPES := ["locked", "radio", "rooftop", "science", "infirmary", "lost_found"]

static func generate_map(rooms: Array, rng: RandomNumberGenerator) -> void:
	rooms.clear()
	for row in range(MAP_ROWS):
		for lane in range(3 if row < MAP_ROWS - 1 else 1):
			var kind := "battle"
			if row == MAP_ROWS - 1:
				kind = "boss"
			elif row == 7:
				kind = ["elite", "rest", "upgrade"][lane]
			elif row in [0, 3, 6, 9]:
				kind = "elite" if row == 9 and lane == 1 else "battle"
			elif row > 0:
				kind = ["battle", "battle", "event", "shop", "upgrade", "rest"][rng.randi_range(0, 5)]
			rooms.append({"id":rooms.size(), "row":row, "lane":lane if row < MAP_ROWS - 1 else 1,
				"kind":kind, "links":[],
				"event":EVENT_TYPES[rng.randi_range(0, EVENT_TYPES.size() - 1)] if kind == "event" else ""})
	for room in rooms:
		var candidates: Array = []
		for next in rooms:
			if next.row == room.row + 1 and (abs(next.lane - room.lane) <= 1 or next.kind == "boss"):
				candidates.append(next.id)
		if not candidates.is_empty():
			room.links.append(candidates[rng.randi_range(0, candidates.size() - 1)])
			for id in candidates:
				if id not in room.links and rng.randf() < 0.38: room.links.append(id)
	# Guarantee incoming paths too: every generated room can be reached.
	for next in rooms:
		if next.row == 0: continue
		if rooms.any(func(room): return next.id in room.links): continue
		var predecessors := rooms.filter(func(room):
			return room.row == next.row - 1 and (abs(room.lane - next.lane) <= 1 or next.kind == "boss")
		)
		predecessors[rng.randi_range(0, predecessors.size() - 1)].links.append(next.id)

static func reachable(id: int, rooms: Array, current: int, cleared: Array, battle_active: bool) -> bool:
	if battle_active or (current >= 0 and current not in cleared): return false
	return rooms[id].row == 0 if current < 0 else id in rooms[current].links
