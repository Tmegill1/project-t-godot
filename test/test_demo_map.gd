extends TestCase

# Legend: buildable, path, blocked, spawn, goal.
const _TILE_CHARS := {
	Tiles.BUILDABLE: ".",
	Tiles.PATH: "#",
	Tiles.BLOCKED: "X",
	Tiles.SPAWN: "S",
	Tiles.GOAL: "G",
}

# The exact board produced by Seeds.DEFAULT_DEMO_MAP_SEED, independently
# verified row-for-row (including the scattered blocked tiles) against the
# reference TypeScript implementation in
# reference/project-t/td-browser/src/game/data/demoMap.ts.
#
# test_same_seed_same_map and test_different_seed_different_map only prove
# "deterministic per seed" and "different seeds differ" - a swapped shuffle
# order, a forked second RNG stream, or a reordered candidate-pool build
# would still satisfy both of those while silently changing which tiles are
# buildable. This test is what pins the RNG stream, the shuffle order, and
# the draw order (adjacent tiles shuffled before distant ones, both from the
# same stream) as a single observable board, the way the RNG golden test
# pins the raw number stream.
#
# If this test fails, the generated board has diverged from the reference
# game - the fix is in build(), not here. Do NOT regenerate these strings
# from whatever build() currently produces and paste them in to make the
# test pass; that pins a bug exactly as happily as it pins correct behavior.
const GOLDEN_BOARD := [
	".......................",
	".......................",
	".X.........X...........",
	"XXX....................",
	"S################......",
	"XXX.............#......",
	".............X..#......",
	"................#......",
	"...X#############......",
	"....#...............XXX",
	"...X#################GX",
	".........X.......X.XXXX",
	"..X..................X.",
	"..............X....X...",
]

func _build() -> Array:
	return DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))

func _render_row(row: Array) -> String:
	var out := ""
	for kind in row:
		out += _TILE_CHARS[kind]
	return out

func test_dimensions() -> bool:
	var m := _build()
	assert_eq(m.size(), 14, "14 rows")
	assert_eq(m[0].size(), 23, "23 columns")
	return true

func test_has_exactly_one_spawn_and_one_goal() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	var spawns := 0
	var goals := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.SPAWN:
				spawns += 1
			elif m[r][c] == Tiles.GOAL:
				goals += 1
	assert_eq(spawns, 1, "one spawn")
	assert_eq(goals, 1, "one goal")
	return true

func test_spawn_and_goal_positions() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	assert_eq(m[4][0], Tiles.SPAWN, "spawn at row 4, col 0")
	assert_eq(m[10][21], Tiles.GOAL, "goal at row 10, col 21")
	return true

func test_path_runs_where_authored() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	# First leg: row 4, columns 1..16 (column 0 is the spawn).
	for c in range(1, 17):
		assert_eq(m[4][c], Tiles.PATH, "row 4 col %d is path" % c)
	# Second leg: column 16, rows 5..7. Indexing is map[row][col].
	for r in range(5, 8):
		assert_eq(m[r][16], Tiles.PATH, "col 16 row %d is path" % r)
	# Final leg: row 10, columns 4..20 (21 is the goal).
	for c in range(4, 21):
		assert_eq(m[10][c], Tiles.PATH, "row 10 col %d is path" % c)
	return true

func test_spawn_and_goal_surroundings_are_blocked() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	for r in range(3, 6):
		for c in range(0, 3):
			assert_true(m[r][c] == Tiles.BLOCKED or m[r][c] == Tiles.SPAWN or m[r][c] == Tiles.PATH,
				"tile (%d,%d) near spawn is not buildable" % [r, c])
	for r in range(9, 12):
		for c in range(20, 23):
			assert_true(m[r][c] != Tiles.BUILDABLE,
				"tile (%d,%d) near goal is not buildable" % [r, c])
	return true

func test_blocked_scatter_is_capped_at_twelve() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	var scattered := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] != Tiles.BLOCKED:
				continue
			var near_spawn: bool = r >= 3 and r <= 5 and c <= 2
			var near_goal: bool = r >= 9 and r <= 11 and c >= 20 and c <= 22
			if not near_spawn and not near_goal:
				scattered += 1
	assert_true(scattered <= 12, "at most 12 scattered blocked tiles, got %d" % scattered)
	return true

func test_top_row_and_last_column_are_never_scatter_blocked() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	for c in 23:
		assert_true(m[0][c] != Tiles.BLOCKED, "row 0 reserved for UI, col %d" % c)
	for r in 14:
		if r >= 9 and r <= 11:
			continue  # the goal surround legitimately blocks column 22
		assert_true(m[r][22] != Tiles.BLOCKED, "last column reserved, row %d" % r)
	return true

func test_golden_board_matches_reference() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var m := _build()
	for r in GOLDEN_BOARD.size():
		assert_eq(_render_row(m[r]), GOLDEN_BOARD[r], "row %d matches the reference board" % r)
	return true

func test_same_seed_same_map() -> bool:
	var a := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	var b := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	assert_eq(a, b, "generation is reproducible")
	return true

func test_different_seed_different_map() -> bool:
	var a := DemoMap.build(Rng.new(1))
	var b := DemoMap.build(Rng.new(2))
	assert_false(a == b, "a different seed scatters differently")
	return true
