extends TestCase

# The bridge between a painted TileMapLayer and the text map format.
#
# Tested headlessly against a real TileMapLayer, because the conversion is
# where the bugs would be and a scene cannot be exercised in this harness. The
# editor scene is a thin shell over these functions.

func _layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = MapEditorIO.build_tileset()
	return layer

# --------------------------------------------------------------------------
# The palette is a contract with the baker
# --------------------------------------------------------------------------

func test_the_palette_covers_every_tile_kind() -> bool:
	for kind in [Tiles.BUILDABLE, Tiles.PATH, Tiles.BLOCKED, Tiles.SPAWN, Tiles.GOAL]:
		assert_true(MapEditorIO.column_for(kind) >= 0,
			"%s can be painted" % kind)
	return true

func test_the_palette_and_the_text_format_describe_the_same_alphabet() -> bool:
	# Two modules naming tile kinds independently is exactly how an editor
	# starts producing maps the loader cannot read.
	for kind in MapEditorIO.PALETTE:
		assert_true(MapFormat.CHARS.values().has(kind),
			"%s has a character in the text format" % kind)
	assert_eq(MapEditorIO.PALETTE.size(), MapFormat.CHARS.size(),
		"the palette and the format cover the same number of kinds")
	return true

func test_the_tileset_has_one_tile_per_palette_entry() -> bool:
	var tileset := MapEditorIO.build_tileset()
	var source: TileSetAtlasSource = tileset.get_source(MapEditorIO.SOURCE_ID)
	assert_eq(source.get_tiles_count(), MapEditorIO.PALETTE.size(),
		"every kind is paintable from the palette")
	return true

# --------------------------------------------------------------------------
# Round trip
# --------------------------------------------------------------------------

func test_painting_and_reading_back_round_trips() -> bool:
	var layer := _layer()
	var source := MapFormat.parse("S==.\n.#=.\n..=G")
	MapEditorIO.paint_layer(layer, source)
	assert_eq(MapEditorIO.tiles_from_layer(layer), source,
		"what was painted is what reads back")
	layer.free()
	return true

# The real thing this exists for: open a committed map, write it back, and get
# the same bytes. If this drifts, every edit rewrites the whole file.
func test_a_shipped_map_survives_a_painted_round_trip_byte_for_byte() -> bool:
	for name in Maps.DEFS:
		var layer := _layer()
		var original := Maps.build_tiles(name)
		MapEditorIO.paint_layer(layer, original)
		var text := MapFormat.format(MapEditorIO.tiles_from_layer(layer))
		assert_eq(text, MapFormat.format(original),
			"%s round trips through the editor unchanged" % name)
		layer.free()
	return true

# Bounds come from the painted cells, so a map drawn away from the origin is
# still the map - not a map with a margin of empty rows.
func test_the_map_is_bounded_by_what_was_painted() -> bool:
	var layer := _layer()
	layer.set_cell(Vector2i(5, 3), MapEditorIO.SOURCE_ID,
		Vector2i(MapEditorIO.column_for(Tiles.SPAWN), 0))
	layer.set_cell(Vector2i(7, 4), MapEditorIO.SOURCE_ID,
		Vector2i(MapEditorIO.column_for(Tiles.GOAL), 0))
	var tiles := MapEditorIO.tiles_from_layer(layer)
	assert_eq(tiles.size(), 2, "two rows were painted")
	assert_eq(tiles[0].size(), 3, "spanning three columns")
	assert_eq(tiles[0][0], Tiles.SPAWN, "the spawn is at the top left of the bounds")
	assert_eq(tiles[1][2], Tiles.GOAL, "and the goal at the bottom right")
	layer.free()
	return true

func test_an_unpainted_cell_inside_the_bounds_reads_as_buildable() -> bool:
	var layer := _layer()
	layer.set_cell(Vector2i(0, 0), MapEditorIO.SOURCE_ID,
		Vector2i(MapEditorIO.column_for(Tiles.SPAWN), 0))
	layer.set_cell(Vector2i(2, 0), MapEditorIO.SOURCE_ID,
		Vector2i(MapEditorIO.column_for(Tiles.GOAL), 0))
	var tiles := MapEditorIO.tiles_from_layer(layer)
	assert_eq(tiles[0][1], Tiles.BUILDABLE,
		"the gap between them is open ground, not a hole")
	layer.free()
	return true

func test_an_empty_layer_is_an_empty_map() -> bool:
	var layer := _layer()
	assert_eq(MapEditorIO.tiles_from_layer(layer), [], "nothing painted, nothing exported")
	layer.free()
	return true

func test_painting_replaces_rather_than_merges() -> bool:
	var layer := _layer()
	MapEditorIO.paint_layer(layer, MapFormat.parse("S=G\n###\n###"))
	MapEditorIO.paint_layer(layer, MapFormat.parse("S=G"))
	assert_eq(MapEditorIO.tiles_from_layer(layer).size(), 1,
		"the second paint replaced the first rather than leaving its rows behind")
	layer.free()
	return true

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------

func test_problems_with_reports_structural_faults() -> bool:
	assert_true(MapEditorIO.problems_with(MapFormat.parse("S=.\n...\n...")).size() > 0,
		"a map with no goal is refused")
	return true

# The defect no structural check can see, and the reason the editor calls the
# real pathfinder rather than reimplementing one.
func test_problems_with_catches_a_goal_that_cannot_be_reached() -> bool:
	# Spawn and goal both present and well formed, but walled off from
	# each other - structurally perfect, unplayable.
	var walled := MapFormat.parse("S.#.G\n..#..\n..#..")
	assert_eq(MapFormat.validate(walled), [], "precondition: structurally valid")
	var problems := MapEditorIO.problems_with(walled)
	assert_true(problems.size() > 0, "but the editor refuses it")
	assert_true(str(problems).contains("reach"), "and says why: %s" % str(problems))
	return true

func test_problems_with_accepts_every_shipped_map() -> bool:
	for name in Maps.DEFS:
		assert_eq(MapEditorIO.problems_with(Maps.build_tiles(name)), [],
			"%s would be accepted by the editor" % name)
	return true
