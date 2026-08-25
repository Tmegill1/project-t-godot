class_name Map3

## Builds "The Coils" — the 28x16 third map.
##
## One entrance and a serpentine route that folds back on itself three times.
## The folds are the whole point: each straight is long enough that a tower
## placed on a bend covers two passes, which is why its tower budget (18) is
## LOWER than The Fork's (20) despite the wider board. More ground does not
## mean more difficulty when the ground doubles up.
##
## Takes an Rng so the blocked-tile layout is reproducible. Ported from the
## reference's data/map3.ts.

const GRID_COLS := 28
const GRID_ROWS := 16

const SPAWN_ROW := 2
const GOAL_ROW := 13
const GOAL_COL := GRID_COLS - 2

## Scatter bounds. Unlike The Pass and The Fork there is NO combined ceiling:
## upstream takes six from the adjacent list and nine from the distant one
## independently, rather than capping the total. Preserved deliberately.
const MAX_ADJACENT_BLOCKED := 6
const MAX_DISTANT_BLOCKED := 9

static func build(rng: Rng = null) -> Array:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_MAP3_SEED)

	var map: Array = []
	for r in GRID_ROWS:
		var row: Array = []
		for c in GRID_COLS:
			row.append(Tiles.BUILDABLE)
		map.append(row)

	# Three folds. Each straight is long enough that a tower placed on a bend
	# covers two passes, which is the shape's whole point.
	var path_coords: Array[Vector2i] = []
	_run_row(path_coords, SPAWN_ROW, 0, 23)
	_run_col(path_coords, 23, SPAWN_ROW, 6)
	_run_row(path_coords, 6, 23, 3)
	_run_col(path_coords, 3, 6, 10)
	_run_row(path_coords, 10, 3, 23)
	_run_col(path_coords, 23, 10, GOAL_ROW)
	_run_row(path_coords, GOAL_ROW, 23, GOAL_COL)

	var path_set := {}
	for coord in path_coords:
		map[coord.y][coord.x] = Tiles.PATH
		path_set[Vector2i(coord.x, coord.y)] = true

	map[SPAWN_ROW][0] = Tiles.SPAWN
	map[GOAL_ROW][GOAL_COL] = Tiles.GOAL

	# The endpoint sprites are drawn larger than a tile, so the ground they
	# cover is blocked rather than buildable.
	_block_around(map, SPAWN_ROW, 0)
	_block_around(map, GOAL_ROW, GOAL_COL)

	# Scatter clutter. Tiles beside the route are blocked more readily than
	# distant ones, so the good positions stay contested. Row 0 is reserved
	# for UI; the last column for the tower menu.
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

	var adjacent_blocked: int = mini(MAX_ADJACENT_BLOCKED, shuffled_adjacent.size())
	for i in adjacent_blocked:
		var t: Vector2i = shuffled_adjacent[i]
		map[t.y][t.x] = Tiles.BLOCKED

	var distant_blocked: int = mini(MAX_DISTANT_BLOCKED, shuffled_distant.size())
	for i in distant_blocked:
		var t: Vector2i = shuffled_distant[i]
		map[t.y][t.x] = Tiles.BLOCKED

	return map

## Inclusive at both ends, in either direction.
static func _run_row(out: Array[Vector2i], row: int, from_col: int, to_col: int) -> void:
	var step := 1 if from_col <= to_col else -1
	var c := from_col
	while (c <= to_col) if step > 0 else (c >= to_col):
		out.append(Vector2i(c, row))
		c += step

static func _run_col(out: Array[Vector2i], col: int, from_row: int, to_row: int) -> void:
	var step := 1 if from_row <= to_row else -1
	var r := from_row
	while (r <= to_row) if step > 0 else (r >= to_row):
		out.append(Vector2i(col, r))
		r += step

static func _block_around(map: Array, row: int, col: int) -> void:
	for r in range(row - 1, row + 2):
		for c in range(col - 1, col + 2):
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
