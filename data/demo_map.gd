class_name DemoMap

## Builds "The Pass" — the 23x14 first map.
##
## Takes an Rng so the blocked-tile layout is reproducible. Draw order is
## load-bearing: adjacent tiles are shuffled before distant ones, from the
## same stream, exactly as the TypeScript does.

const GRID_COLS := 23
const GRID_ROWS := 14

const MAX_ADJACENT_BLOCKED := 5
const MAX_DISTANT_BLOCKED := 7
const MAX_TOTAL_BLOCKED := 12

static func build(rng: Rng = null) -> Array:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED)

	var map: Array = []
	for r in GRID_ROWS:
		var row: Array = []
		for c in GRID_COLS:
			row.append(Tiles.BUILDABLE)
		map.append(row)

	# Path legs, authored as [col, row] pairs.
	var path_coords: Array[Vector2i] = []
	for c in range(0, 17):
		path_coords.append(Vector2i(c, 4))
	for r in range(4, 8):
		path_coords.append(Vector2i(16, r))
	for c in range(16, 3, -1):
		path_coords.append(Vector2i(c, 8))
	for r in range(8, 11):
		path_coords.append(Vector2i(4, r))
	for c in range(4, GRID_COLS - 1):
		path_coords.append(Vector2i(c, 10))

	var path_set := {}
	for coord in path_coords:
		map[coord.y][coord.x] = Tiles.PATH
		path_set[Vector2i(coord.x, coord.y)] = true

	map[4][0] = Tiles.SPAWN
	map[10][GRID_COLS - 2] = Tiles.GOAL

	# The spawn and goal sprites are drawn 3x3, so the tiles they cover are
	# blocked rather than left buildable underneath the artwork.
	for r in range(3, 6):
		for c in range(0, 3):
			if r >= 0 and r < GRID_ROWS and c < GRID_COLS and map[r][c] == Tiles.BUILDABLE:
				map[r][c] = Tiles.BLOCKED

	var goal_row := 10
	var goal_col := GRID_COLS - 2
	for r in range(goal_row - 1, goal_row + 2):
		for c in range(goal_col - 1, goal_col + 2):
			if r >= 0 and r < GRID_ROWS and c >= 0 and c < GRID_COLS and map[r][c] == Tiles.BUILDABLE:
				map[r][c] = Tiles.BLOCKED

	# Scatter. Row 0 is reserved for UI; the last column for the tower menu.
	var adjacent: Array = []
	var distant: Array = []
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if map[r][c] != Tiles.BUILDABLE:
				continue
			if r == 0 or c == GRID_COLS - 1:
				continue
			if _is_adjacent_to_path(r, c, path_set):
				adjacent.append(Vector2i(c, r))
			else:
				distant.append(Vector2i(c, r))

	var shuffled_adjacent := rng.shuffle(adjacent)
	var shuffled_distant := rng.shuffle(distant)

	var blocked_count := 0
	var adjacent_blocked: int = mini(MAX_ADJACENT_BLOCKED, shuffled_adjacent.size())
	for i in adjacent_blocked:
		var t: Vector2i = shuffled_adjacent[i]
		map[t.y][t.x] = Tiles.BLOCKED
		blocked_count += 1

	var remaining := MAX_TOTAL_BLOCKED - blocked_count
	var distant_blocked: int = mini(MAX_DISTANT_BLOCKED, mini(shuffled_distant.size(), remaining))
	for i in distant_blocked:
		var t: Vector2i = shuffled_distant[i]
		map[t.y][t.x] = Tiles.BLOCKED

	return map

static func _is_adjacent_to_path(row: int, col: int, path_set: Dictionary) -> bool:
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d in directions:
		var nr := row + d.y
		var nc := col + d.x
		if nr < 0 or nr >= GRID_ROWS or nc < 0 or nc >= GRID_COLS:
			continue
		if path_set.has(Vector2i(nc, nr)):
			return true
	return false
