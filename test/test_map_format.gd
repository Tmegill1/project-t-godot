extends TestCase

# The text map format. One character per tile, one line per row.
#
# The format is the CONTRACT: the game reads it, and any editor - Godot's
# TileMap painter exporting to it, or a text editor - writes it. Neither
# depends on the other existing, which is why the format came first.

func test_the_alphabet_covers_every_tile_kind() -> bool:
	# A kind with no character could never be authored, and would be silently
	# unreachable rather than loudly missing.
	for kind in [Tiles.BUILDABLE, Tiles.PATH, Tiles.BLOCKED, Tiles.SPAWN, Tiles.GOAL]:
		assert_true(MapFormat.CHARS.values().has(kind),
			"%s has a character" % kind)
	return true

func test_parse_reads_a_grid() -> bool:
	var tiles := MapFormat.parse("S=.\n.#.\n..G")
	assert_eq(tiles.size(), 3, "three rows")
	assert_eq(tiles[0].size(), 3, "three columns")
	assert_eq(tiles[0][0], Tiles.SPAWN, "S is a spawn")
	assert_eq(tiles[0][1], Tiles.PATH, "= is road")
	assert_eq(tiles[0][2], Tiles.BUILDABLE, ". is buildable")
	assert_eq(tiles[1][1], Tiles.BLOCKED, "# is blocked")
	assert_eq(tiles[2][2], Tiles.GOAL, "G is the goal")
	return true

func test_parse_and_format_round_trip() -> bool:
	var source := "S==..\n..#..\n..==G"
	assert_eq(MapFormat.format(MapFormat.parse(source)), source,
		"text survives a round trip unchanged")
	return true

func test_format_and_parse_round_trip_from_a_real_map() -> bool:
	# The migration itself: a builder's output must survive being written to
	# text and read back, or the golden boards would shift under it.
	var built := Maps.build_tiles(&"demoMap")
	var round_tripped := MapFormat.parse(MapFormat.format(built))
	assert_eq(round_tripped.size(), built.size(), "same row count")
	for r in built.size():
		for c in built[r].size():
			assert_eq(round_tripped[r][c], built[r][c],
				"tile %d,%d survives the round trip" % [c, r])
	return true

# Trailing whitespace and blank lines are the two things a text editor adds
# without being asked, so the parser must be immune to both.
func test_parse_ignores_blank_lines_and_trailing_whitespace() -> bool:
	var messy := "\nS=.  \n.#.\t\n..G\n\n"
	var tiles := MapFormat.parse(messy)
	assert_eq(tiles.size(), 3, "blank lines are not rows")
	assert_eq(tiles[0].size(), 3, "trailing whitespace is not tiles")
	assert_eq(tiles[2][2], Tiles.GOAL, "and the content still lands")
	return true

func test_parse_tolerates_windows_line_endings() -> bool:
	var tiles := MapFormat.parse("S=.\r\n.#.\r\n..G")
	assert_eq(tiles.size(), 3, "CRLF is still three rows")
	assert_eq(tiles[0][0], Tiles.SPAWN, "and the first tile is intact")
	return true

# A ragged map would produce rows of different lengths, which every consumer
# indexes into blindly. Better to fail loudly at authoring time.
func test_validate_rejects_a_ragged_grid() -> bool:
	var problems := MapFormat.validate(MapFormat.parse("S=.\n.#\n..G"))
	assert_true(problems.size() > 0, "a ragged grid is reported")
	return true

func test_validate_rejects_an_unknown_character() -> bool:
	var problems := MapFormat.validate(MapFormat.parse("S=.\n.X.\n..G"))
	assert_true(problems.size() > 0, "an unknown character is reported")
	return true

func test_validate_requires_exactly_one_goal() -> bool:
	assert_true(MapFormat.validate(MapFormat.parse("S=.\n...\n...")).size() > 0,
		"no goal is a problem")
	assert_true(MapFormat.validate(MapFormat.parse("S=G\n...\n..G")).size() > 0,
		"two goals is a problem")
	return true

func test_validate_requires_at_least_one_spawn() -> bool:
	assert_true(MapFormat.validate(MapFormat.parse(".=.\n...\n..G")).size() > 0,
		"no spawn is a problem")
	return true

func test_validate_accepts_a_well_formed_map() -> bool:
	assert_eq(MapFormat.validate(MapFormat.parse("S==\n..=\n..G")), [],
		"a valid map reports nothing")
	return true

# The three shipped maps must pass their own validator, or the format is
# describing something the game does not actually use.
func test_every_shipped_map_validates() -> bool:
	for name in Maps.DEFS:
		var problems := MapFormat.validate(Maps.build_tiles(name))
		assert_eq(problems, [], "%s validates: %s" % [name, str(problems)])
	return true
