class_name PathFinder

## BFS from each spawn tile to the goal, over walkable tiles only.
## Returns world-space paths; the first point is the spawn centre.

static func get_path_from_spawn_to_goal(map: Array) -> PackedVector2Array:
	var all := get_all_spawn_paths(map)
	return all[0] if all.size() > 0 else PackedVector2Array()

static func get_all_spawn_paths(map: Array) -> Array[PackedVector2Array]:
	var results: Array[PackedVector2Array] = []
	var rows := map.size()
	if rows == 0:
		return results
	var cols: int = map[0].size()

	var spawns: Array[Vector2i] = []
	var goal := Vector2i(-1, -1)
	for r in rows:
		for c in cols:
			if map[r][c] == Tiles.SPAWN:
				spawns.append(Vector2i(c, r))
			elif map[r][c] == Tiles.GOAL:
				goal = Vector2i(c, r)

	if spawns.is_empty() or goal.x < 0:
		return results

	for spawn in spawns:
		var tiles := _bfs(spawn, goal, map, rows, cols)
		var path := PackedVector2Array()
		path.append(Grid.tile_to_world_center(spawn.x, spawn.y))
		if tiles.is_empty():
			# BFS found no route: the goal is unreachable from this spawn.
			# Match the reference's fallback (PathFinder.ts:49-55) rather
			# than leaving a one-point path with no goal at all - later
			# tasks (e.g. Movement.advance) index path[path_index] and
			# derive arrival from path.size(), so every path must have at
			# least a start and an end. A spawn adjacent to the goal is
			# NOT this case: its trail is [goal], not empty, so it takes
			# the normal branch below.
			path.append(Grid.tile_to_world_center(goal.x, goal.y))
		else:
			for t in tiles:
				path.append(Grid.tile_to_world_center(t.x, t.y))
		results.append(path)

	return results

static func _bfs(start: Vector2i, goal: Vector2i, map: Array, rows: int, cols: int) -> Array[Vector2i]:
	var visited := {start: true}
	var queue: Array = [[start, [] as Array[Vector2i]]]
	var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	while not queue.is_empty():
		var entry = queue.pop_front()
		var current: Vector2i = entry[0]
		var trail: Array[Vector2i] = entry[1]

		if current == goal:
			return trail

		for d in directions:
			var nxt: Vector2i = current + d
			if nxt.x < 0 or nxt.x >= cols or nxt.y < 0 or nxt.y >= rows:
				continue
			if visited.has(nxt):
				continue
			if not (map[nxt.y][nxt.x] in Tiles.WALKABLE):
				continue
			visited[nxt] = true
			var extended := trail.duplicate()
			extended.append(nxt)
			queue.append([nxt, extended])

	return [] as Array[Vector2i]
