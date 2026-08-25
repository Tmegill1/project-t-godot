class_name Map2

## Builds "The Fork" — the 26x17 second map.
##
## Two entrances, top left and bottom left, converging at row 7 and running
## right to the goal. That convergence is the map's whole point: a tower on the
## joined stretch covers both streams, and one placed before it covers only
## half the wave.
##
## Note what two spawns MEAN for difficulty. The full wave composition runs
## down EVERY path (see GameBoard._spawn), so this map fields twice the enemies
## of the same wave number on The Pass. That is why it opens with 250 gold
## against The Pass's 100, and a budget of 20 against 16 - the map's own
## numbers carry the difficulty, not a special case in the wave tables.
##
## Takes an Rng so the blocked-tile layout is reproducible. Ported from the
## reference's data/map2.ts.

const GRID_COLS := 26
const GRID_ROWS := 17

const MAX_ADJACENT_BLOCKED := 5
const MAX_DISTANT_BLOCKED := 7
const MAX_TOTAL_BLOCKED := 12

static func build(rng: Rng = null) -> Array:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_MAP2_SEED)

	var map: Array = []
	for r in GRID_ROWS:
		var row: Array = []
		for c in GRID_COLS:
			row.append(Tiles.BUILDABLE)
		map.append(row)

	# Path legs, authored as [col, row] pairs, matching data/demo_map.gd.
	var path_coords: Array[Vector2i] = []
	# Top left entrance: right along row 1, then down column 10 to row 7.
	for c in range(0, 10):
		path_coords.append(Vector2i(c, 1))
	for r in range(1, 7):
		path_coords.append(Vector2i(10, r))
	# Bottom left entrance: right along row 12, then up column 9 to row 7.
	for c in range(0, 9):
		path_coords.append(Vector2i(c, 12))
	for r in range(12, 7, -1):
		path_coords.append(Vector2i(9, r))
	# The joined stretch: row 7, right to the goal.
	for c in range(9, GRID_COLS - 1):
		path_coords.append(Vector2i(c, 7))

	var path_set := {}
	for coord in path_coords:
		map[coord.y][coord.x] = Tiles.PATH
		path_set[Vector2i(coord.x, coord.y)] = true

	map[1][0] = Tiles.SPAWN
	map[12][0] = Tiles.SPAWN
	map[7][GRID_COLS - 2] = Tiles.GOAL

	# The endpoint sprites are drawn 3x3, so the ground they cover is blocked
	# rather than left buildable underneath the artwork.
	_block_box(map, 0, 2, 0, 2)     # top spawn
	_block_box(map, 11, 13, 0, 2)   # bottom spawn
	var goal_row := 7
	var goal_col := GRID_COLS - 2
	_block_box(map, goal_row - 1, goal_row + 1, goal_col - 1, goal_col + 1)

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

static func _block_box(map: Array, r0: int, r1: int, c0: int, c1: int) -> void:
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if r >= 0 and r < GRID_ROWS and c >= 0 and c < GRID_COLS \
					and map[r][c] == Tiles.BUILDABLE:
				map[r][c] = Tiles.BLOCKED

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
