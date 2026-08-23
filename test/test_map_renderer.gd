extends TestCase

# MapRenderer draws Sprite2D children rather than using a TileMapLayer, so
# these tests inspect the child tree (position, z_index, texture) rather
# than a tilemap API. Textures are identified by their public
# Texture2D.resource_path rather than by reaching into MapRenderer's private
# _decorations dict, so these tests only rely on public state.

const _SPIKE_PATH := "res://assets/art/forest/spike.png"
const _FIRE_PATH := "res://assets/art/forest/fire.png"
const _STONE_PATH := "res://assets/art/forest/stone.png"
const _TREE_PATH := "res://assets/art/forest/tree.png"
const _CAVE_PATH := "res://assets/art/cave.png"
const _CASTLE_PATH := "res://assets/art/castle.png"

func _demo_tiles() -> Array:
	return Maps.build_tiles(Maps.FIRST)

# Every z_index == 1 (decoration/endpoint/blocked-overlay) sprite, keyed by
# world position so the check does not depend on child add order.
func _overlay_signature(mr: MapRenderer) -> Dictionary:
	var sig := {}
	for child in mr.get_children():
		if child is Sprite2D and child.z_index == 1:
			sig[child.position] = child.texture.resource_path
	return sig

func test_render_is_deterministic_for_the_same_seed() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var a := MapRenderer.new()
	a.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	var b := MapRenderer.new()
	b.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	assert_eq(_overlay_signature(a), _overlay_signature(b), "same seed produces the same decoration layout")
	a.free()
	b.free()
	return true

func test_a_different_seed_gives_a_different_layout() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var a := MapRenderer.new()
	a.render(tiles, Rng.new(1))
	var b := MapRenderer.new()
	b.render(tiles, Rng.new(2))
	assert_false(_overlay_signature(a) == _overlay_signature(b), "a different seed scatters decoration differently")
	a.free()
	b.free()
	return true

func test_the_ground_layer_has_one_sprite_per_tile() -> bool:
	# The corner lattice drew (cols+1)*(rows+1) sprites offset half a tile.
	# The edge mask draws one per tile, on the grid.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var ground := 0
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == -1:
			ground += 1
	assert_eq(ground, DemoMap.GRID_COLS * DemoMap.GRID_ROWS,
		"one ground sprite per tile")
	renderer.free()
	return true

func test_the_edge_mask_reads_the_four_orthogonal_neighbours() -> bool:
	# Bit order is fixed and load-bearing: N=1, E=2, S=4, W=8.
	var renderer := MapRenderer.new()
	var tiles: Array = []
	for r in 3:
		var row: Array = []
		for c in 3:
			row.append(Tiles.BUILDABLE)
		tiles.append(row)
	tiles[1][1] = Tiles.PATH
	tiles[0][1] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 1, "a road neighbour to the north sets bit 1")
	tiles[0][1] = Tiles.BUILDABLE
	tiles[1][2] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 2, "a road neighbour to the east sets bit 2")
	tiles[1][2] = Tiles.BUILDABLE
	tiles[2][1] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 4, "a road neighbour to the south sets bit 4")
	tiles[2][1] = Tiles.BUILDABLE
	tiles[1][0] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 8, "a road neighbour to the west sets bit 8")
	renderer.free()
	return true

func test_out_of_bounds_neighbours_are_not_road() -> bool:
	var renderer := MapRenderer.new()
	var tiles: Array = [[Tiles.PATH]]
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(0, 0), 0, "an isolated cell has no road neighbours")
	renderer.free()
	return true

func test_spawn_and_goal_count_as_road() -> bool:
	# Tiles.WALKABLE is PATH, SPAWN and GOAL; the road must not break at the
	# endpoints.
	var renderer := MapRenderer.new()
	var tiles: Array = [[Tiles.SPAWN, Tiles.PATH, Tiles.GOAL]]
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 0), 2 | 8,
		"spawn to the west and goal to the east both count")
	renderer.free()
	return true

func test_every_road_cell_draws_the_piece_its_mask_names() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		if not sprite.texture.resource_path.contains("road_"):
			continue
		var c := int(sprite.position.x / Tiles.TILE_SIZE)
		var r := int(sprite.position.y / Tiles.TILE_SIZE)
		var named := int(sprite.texture.resource_path.get_file().get_basename().split("_")[1])
		assert_eq(named, renderer.edge_mask(c, r),
			"the piece at (%d, %d) is the one its mask names" % [c, r])
		checked += 1
	assert_true(checked > 0, "road cells were checked")
	renderer.free()
	return true

func test_the_demo_map_needs_the_dead_end_pieces() -> bool:
	# The reason there is no rotation. Rotating the five pieces the sheet
	# itself draws reaches twelve of the sixteen masks; the four dead ends
	# (1, 2, 4, 8) are unreachable from them, and the demo map has two - the
	# spawn and the goal, where the road enters from one side only. This test
	# fails the day someone reintroduces a rotation scheme.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var dead_ends := 0
	for r in DemoMap.GRID_ROWS:
		for c in DemoMap.GRID_COLS:
			if tiles[r][c] in Tiles.WALKABLE and renderer.edge_mask(c, r) in [1, 2, 4, 8]:
				dead_ends += 1
	assert_eq(dead_ends, 2, "the demo map's road has two dead ends")
	renderer.free()
	return true

func test_ground_and_road_tiles_fill_their_cell_exactly() -> bool:
	# Replaces test_square_ground_tiles_take_zero_slack_from_the_tile_box,
	# whose premise was that every ground source is square. The illustrated
	# road pieces are 66x63, so aspect-fitting them leaves a 2.2px transparent
	# gap under every road tile - seams, in the layer whose whole job is to
	# have none. The property worth keeping is unchanged and is stated more
	# directly here: a tile lands on its cell's origin and covers the cell.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var box := float(Tiles.TILE_SIZE)
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		var display := sprite.region_rect.size * sprite.scale
		assert_almost_eq(display.x, box, 0.01, "a tile is exactly one cell wide")
		assert_almost_eq(display.y, box, 0.01, "a tile is exactly one cell tall")
		var c := int(round(sprite.position.x / box))
		var r := int(round(sprite.position.y / box))
		assert_eq(sprite.position, Vector2(c * box, r * box),
			"a tile lands on its cell's origin")
		checked += 1
	assert_true(checked > 0, "tiles were checked")
	renderer.free()
	return true

func test_a_non_square_tile_source_is_the_case_this_covers() -> bool:
	# The precondition the test above rests on. If every source were square,
	# stretching and aspect-fitting would be the same thing and the seam this
	# task fixes could not occur.
	var bytes := FileAccess.get_file_as_bytes("res://assets/art/forest/road_10.png")
	assert_false(bytes.is_empty(), "a road piece exists to measure")
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(bytes), OK, "the road piece decodes")
	assert_false(img.get_width() == img.get_height(),
		"the road pieces are genuinely non-square (%dx%d)"
			% [img.get_width(), img.get_height()])
	return true

func test_render_defaults_to_the_default_decoration_seed_when_no_rng_is_given() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()

	var defaulted := MapRenderer.new()
	defaulted.render(tiles)  # no rng argument

	var explicit := MapRenderer.new()
	explicit.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	assert_eq(_overlay_signature(defaulted), _overlay_signature(explicit),
		"omitting rng falls back to Rng.new(Seeds.DEFAULT_DECORATION_SEED), matching an explicit one")

	defaulted.free()
	explicit.free()
	return true

func test_endpoints_are_placed_and_scaled_correctly() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()

	var spawn_tile := Vector2i(-1, -1)
	var goal_tile := Vector2i(-1, -1)
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] == Tiles.SPAWN:
				spawn_tile = Vector2i(c, r)
			elif tiles[r][c] == Tiles.GOAL:
				goal_tile = Vector2i(c, r)
	assert_true(spawn_tile.x >= 0, "the demo map has a spawn tile")
	assert_true(goal_tile.x >= 0, "the demo map has a goal tile")

	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var cave: Sprite2D = null
	var castle: Sprite2D = null
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _CAVE_PATH:
			cave = child
		elif child is Sprite2D and child.texture.resource_path == _CASTLE_PATH:
			castle = child
	assert_true(cave != null, "a cave sprite was drawn on the spawn tile")
	assert_true(castle != null, "a castle sprite was drawn on the goal tile")

	# These assertions used to require BOTH axes to measure TILE_SIZE * 3,
	# which is what the Phaser reference's setDisplaySize(s, s) produces - and
	# which stretched cave.png (300x216) and castle.png (287x305) off their
	# true proportions. _place now contain-fits and centres instead (see its
	# doc comment), so the endpoints are checked against that rule: the long
	# axis fills the 3-tile box, the short axis keeps its ratio, and the
	# leftover slack is split evenly around the documented base offset.
	var box := float(Tiles.TILE_SIZE * 3)
	var offset := Vector2(-Tiles.TILE_SIZE, -Tiles.TILE_SIZE - 20)

	for entry in [[cave, spawn_tile, "cave", "spawn"], [castle, goal_tile, "castle", "goal"]]:
		var sprite: Sprite2D = entry[0]
		var tile: Vector2i = entry[1]
		var name: String = entry[2]
		var role: String = entry[3]
		var tex := sprite.texture
		var src := Vector2(tex.get_width(), tex.get_height())

		assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001,
			"%s scales uniformly - it is not stretched to a square" % name)

		var factor := box / maxf(src.x, src.y)
		assert_almost_eq(sprite.scale.x, factor, 0.0001,
			"%s's longest axis fills the 3-tile box exactly" % name)

		var display := src * sprite.scale
		assert_almost_eq(maxf(display.x, display.y), box, 0.01,
			"%s's long axis measures TILE_SIZE * 3" % name)
		assert_true(minf(display.x, display.y) <= box + 0.01,
			"%s's short axis stays inside the 3-tile box (got %.2fx%.2f)" % [name, display.x, display.y])
		assert_almost_eq(display.x / display.y, src.x / src.y, 0.0001,
			"%s keeps its source aspect ratio (%dx%d)" % [name, tex.get_width(), tex.get_height()])

		var base := Vector2(tile.x * Tiles.TILE_SIZE, tile.y * Tiles.TILE_SIZE) + offset
		var slack := (Vector2(box, box) - display) / 2.0
		assert_almost_eq(sprite.position.x, base.x + slack.x, 0.01,
			"%s sits at the %s tile origin plus the (-TILE_SIZE, -TILE_SIZE - 20) offset, centred horizontally" % [name, role])
		assert_almost_eq(sprite.position.y, base.y + slack.y, 0.01,
			"%s sits at the %s tile origin plus the (-TILE_SIZE, -TILE_SIZE - 20) offset, centred vertically" % [name, role])

	mr.free()
	return true

func test_spike_count_matches_the_formula_for_the_demo_map() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()

	var buildable := 0
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] == Tiles.BUILDABLE:
				buildable += 1
	var expected: int = mini(buildable, maxi(5, int(floor(buildable * 0.1))))

	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	var spikes := 0
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _SPIKE_PATH:
			spikes += 1
	assert_eq(spikes, expected, "spike count is mini(buildable, maxi(5, floor(buildable * 0.1))) = %d" % expected)

	mr.free()
	return true

# On the real demo map floor(buildable * 0.1) already exceeds 5, so the
# maxi(5, ...) floor is never the binding constraint there and a mutation
# to the literal 5 is invisible to the test above. A small synthetic map
# (30 buildable tiles: floor(30 * 0.1) = 3) is what actually exercises it.
func test_spike_count_floor_of_five_binds_on_a_small_buildable_pool() -> bool:
	Grid.set_active(6, 5)
	var synthetic: Array = []
	for r in 5:
		var row: Array = []
		for c in 6:
			row.append(Tiles.BUILDABLE)
		synthetic.append(row)  # 30 buildable tiles total

	var mr := MapRenderer.new()
	mr.render(synthetic, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	var spikes := 0
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _SPIKE_PATH:
			spikes += 1
	assert_eq(spikes, 5, "maxi(5, floor(30 * 0.1) = 3) = 5 spikes, not the 10%% formula's 3")

	mr.free()
	return true

func test_fire_is_capped_and_only_on_buildable_tiles_adjacent_to_walkable_without_a_spike() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var spike_positions := {}
	var fire_positions: Array = []
	for child in mr.get_children():
		if not (child is Sprite2D):
			continue
		if child.texture.resource_path == _SPIKE_PATH:
			spike_positions[child.position] = true
		elif child.texture.resource_path == _FIRE_PATH:
			fire_positions.append(child.position)

	# Independently recompute the fire candidate pool (buildable, adjacent to
	# a walkable tile, not already a spike tile) as a separate implementation
	# of the same rule, so the cap is checked against a known-exceeded pool
	# on the real demo map (67 candidates) rather than only asserting an
	# upper bound that a smaller cap would still satisfy vacuously.
	var pool := 0
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] != Tiles.BUILDABLE:
				continue
			if spike_positions.has(Vector2(c * Tiles.TILE_SIZE, r * Tiles.TILE_SIZE)):
				continue
			var pool_adjacent := false
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var pr: int = r + d.y
				var pc: int = c + d.x
				if pr < 0 or pr >= tiles.size() or pc < 0 or pc >= tiles[0].size():
					continue
				if tiles[pr][pc] in Tiles.WALKABLE:
					pool_adjacent = true
			if pool_adjacent:
				pool += 1
	assert_true(pool > 7, "precondition: the demo map's fire-candidate pool exceeds 7, so the cap is actually exercised (got %d)" % pool)
	assert_eq(fire_positions.size(), 7, "fire is capped at exactly _MAX_FIRE_TILES = 7 when the pool exceeds it, got %d" % fire_positions.size())

	for pos in fire_positions:
		var c := int(pos.x / Tiles.TILE_SIZE)
		var r := int(pos.y / Tiles.TILE_SIZE)
		assert_eq(tiles[r][c], Tiles.BUILDABLE, "fire only lands on a buildable tile (col %d row %d)" % [c, r])
		assert_false(spike_positions.has(pos), "fire never lands on a tile that already took a spike (col %d row %d)" % [c, r])

		var adjacent_to_walkable := false
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var nr: int = r + d.y
			var nc: int = c + d.x
			if nr < 0 or nr >= tiles.size() or nc < 0 or nc >= tiles[0].size():
				continue
			if tiles[nr][nc] in Tiles.WALKABLE:
				adjacent_to_walkable = true
		assert_true(adjacent_to_walkable, "fire tile (col %d row %d) is orthogonally adjacent to a walkable tile" % [c, r])

	mr.free()
	return true

# On the real demo map, whether a spiked tile ever gets reconsidered for
# fire (were the exclusion check broken) depends on shuffle luck - the pool
# is large (67 candidates) and only 7 are drawn, so a broken exclusion may
# simply never happen to draw one of the ~24 spiked tiles. This map removes
# luck from the equation: 4 buildable tiles, each sandwiched between two
# path tiles (so all 4 are walkable-adjacent), and nothing else buildable.
# spike_count = mini(4, maxi(5, floor(4 * 0.1) = 0)) = 4, so *every*
# buildable tile gets a spike, deterministically, regardless of shuffle
# order. If the fire pass fails to exclude already-spiked tiles, its
# candidate pool is exactly these same 4 tiles and an overlap is
# unavoidable; if it excludes them correctly, zero candidates remain.
func test_fire_never_reuses_a_spiked_tile_even_when_forced_to_overlap() -> bool:
	Grid.set_active(9, 1)
	var synthetic: Array = [[
		Tiles.PATH, Tiles.BUILDABLE, Tiles.PATH, Tiles.BUILDABLE, Tiles.PATH,
		Tiles.BUILDABLE, Tiles.PATH, Tiles.BUILDABLE, Tiles.PATH,
	]]

	var mr := MapRenderer.new()
	mr.render(synthetic, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var spikes := 0
	var fires := 0
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _SPIKE_PATH:
			spikes += 1
		elif child is Sprite2D and child.texture.resource_path == _FIRE_PATH:
			fires += 1

	assert_eq(spikes, 4, "all 4 buildable tiles get a spike: mini(4, maxi(5, floor(4 * 0.1) = 0)) = 4")
	assert_eq(fires, 0, "no fire candidates remain once every walkable-adjacent buildable tile already has a spike")

	mr.free()
	return true

# _is_adjacent_to_walkable is exercised indirectly by the fire tests above,
# but only through whichever direction the real/synthetic maps happen to
# need - a dropped direction (e.g. "right") is invisible unless a tile's
# *only* walkable neighbour is in that exact direction. These four cases
# isolate each direction individually by calling the method directly
# (render() populates _tiles/_rows/_cols as a side effect; the method
# itself carries no other state). GDScript does not enforce the leading
# underscore as real privacy - the project already reaches into "private"
# helpers from tests (see test_sim_purity.gd) - so this is calling the
# actual function under test, not reimplementing it.
func test_is_adjacent_to_walkable_checks_all_four_orthogonal_directions() -> bool:
	Grid.set_active(3, 3)
	# center tile (1,1) is BUILDABLE; test one direction at a time by
	# putting a single PATH tile in just that direction and BLOCKED
	# everywhere else, so only that direction could produce a true result.
	var mr := MapRenderer.new()

	var up: Array = [
		[Tiles.BLOCKED, Tiles.PATH, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
	]
	mr.render(up, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1), "adjacency check finds a walkable tile directly above")

	var down: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.PATH, Tiles.BLOCKED],
	]
	mr.render(down, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1), "adjacency check finds a walkable tile directly below")

	var left: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.PATH, Tiles.BUILDABLE, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
	]
	mr.render(left, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1), "adjacency check finds a walkable tile directly to the left")

	var right: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.PATH],
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
	]
	mr.render(right, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1), "adjacency check finds a walkable tile directly to the right")

	var none: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
	]
	mr.render(none, Rng.new(1))
	assert_false(mr._is_adjacent_to_walkable(1, 1), "no walkable neighbour in any direction reports false")

	mr.free()
	return true

# _is_adjacent_to_walkable checks directions in a fixed order: up, down,
# left, right. On Godot 4.7.1, an out-of-bounds index access aborts the
# *entire* enclosing function frame and returns the declared return type's
# default - not just the failing expression, with everything after it in
# that function skipped. (This is the same mechanism test/case.gd's
# `-> bool` / `return true` crash sentinel itself depends on - see
# run_tests.gd's header comment - so it is settled behaviour, not
# incidental.) A tile in the last row has no real "down" neighbour; the
# correct bounds check skips it cleanly via `continue`. But if that bounds
# check were ever broken, the resulting out-of-bounds access on the down
# probe - checked *before* left and right - would abort the whole function
# and return false immediately, even when the genuine walkable neighbour is
# to the left or right and would otherwise have been found. The direction
# test above always centres its target tile, so no probe there is ever out
# of bounds and it structurally cannot exercise this; these cases exist
# specifically to close that gap.
func test_is_adjacent_to_walkable_checks_left_and_right_from_the_last_row() -> bool:
	var mr := MapRenderer.new()

	# Last row, walkable neighbour only to the right - past where the down
	# probe (checked second) would go out of bounds.
	Grid.set_active(3, 2)
	var right_only: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.PATH],
	]
	mr.render(right_only, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1),
		"last-row tile finds its walkable neighbour to the right, past where the down probe would go out of bounds")

	# Last row, walkable neighbour only to the left - same hazard.
	var left_only: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.PATH, Tiles.BUILDABLE, Tiles.BLOCKED],
	]
	mr.render(left_only, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1),
		"last-row tile finds its walkable neighbour to the left, past where the down probe would go out of bounds")

	# Bottom-right corner: last row AND last column, walkable neighbour only
	# to the left - both the down and right probes would go out of bounds.
	Grid.set_active(2, 2)
	var corner: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.PATH, Tiles.BUILDABLE],
	]
	mr.render(corner, Rng.new(1))
	assert_true(mr._is_adjacent_to_walkable(1, 1),
		"bottom-right corner tile finds its walkable neighbour to the left, past where both the down and right probes would go out of bounds")

	mr.free()
	return true

# A single seed's stone count can coincidentally match between rng.int_range
# (3, 5) and a mutated (2, 5) or (3, 6): they share the same underlying
# next() draw at that call site, and lo + int(next() * width) can round to
# the same integer despite a different width. Sweeping many seeds is what
# actually pins the bounds: across 40 fixed, deterministic seeds the correct
# range visits every value in {3, 4, 5}, while a mutated (2, 5) would have
# to avoid ever drawing 2 across all 40, and a mutated (3, 6) would have to
# avoid ever drawing 6 - vanishingly unlikely, and since Rng is
# deterministic this isn't chance at all, it's a fixed, reproducible check.
# The synthetic map (8 blocked tiles, no spawn/goal so nothing is excluded)
# isolates the call: mini(8, rng.int_range(3, 5)) never clamps, since 8 > 5.
func test_stone_count_bounds_are_exactly_three_to_five_across_many_seeds() -> bool:
	Grid.set_active(4, 2)
	var synthetic: Array = [
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
		[Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED, Tiles.BLOCKED],
	]

	var min_seen := 999
	var max_seen := -999
	for seed in range(1, 41):
		var mr := MapRenderer.new()
		mr.render(synthetic, Rng.new(seed))
		var stones := 0
		for child in mr.get_children():
			if child is Sprite2D and child.texture.resource_path == _STONE_PATH:
				stones += 1
		min_seen = mini(min_seen, stones)
		max_seen = maxi(max_seen, stones)
		mr.free()

	assert_eq(min_seen, 3, "across 40 seeds, the lowest stone count ever drawn is exactly 3 (int_range's lower bound)")
	assert_eq(max_seen, 5, "across 40 seeds, the highest stone count ever drawn is exactly 5 (int_range's upper bound)")

	return true

func test_blocked_tiles_get_three_to_five_stones_and_nothing_in_the_exclusion_zone() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()

	# Independently recomputes the exclusion zone and the eligible blocked
	# tiles as a separate implementation of the same rule (not a call into
	# map_renderer.gd), so this pins the *rule*, not just whatever the
	# renderer currently does.
	var excluded := {}
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] != Tiles.SPAWN and tiles[r][c] != Tiles.GOAL:
				continue
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					excluded[Vector2i(c + dc, r + dr)] = true

	var eligible := {}
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] == Tiles.BLOCKED and not excluded.has(Vector2i(c, r)):
				eligible[Vector2i(c, r)] = true

	assert_true(eligible.size() >= 5, "precondition: the demo map has at least 5 eligible blocked tiles, got %d" % eligible.size())

	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var stones := {}
	var trees := {}
	for child in mr.get_children():
		if not (child is Sprite2D):
			continue
		var tile := Vector2i(int(child.position.x / Tiles.TILE_SIZE), int(child.position.y / Tiles.TILE_SIZE))
		if child.texture.resource_path == _STONE_PATH:
			stones[tile] = true
		elif child.texture.resource_path == _TREE_PATH:
			trees[tile] = true

	assert_true(stones.size() >= 3 and stones.size() <= 5, "stone count is in [3, 5], got %d" % stones.size())
	# The [3, 5] check above only fails if rng.int_range's bounds drift far
	# enough to escape [3, 5] for this exact seed - int_range(2, 5) or
	# int_range(3, 6) both still land inside [3, 5] a large fraction of the
	# time and would slip past a range-only check by luck. Pinning the exact
	# observed value (independently verified against this run) closes that
	# gap the same way test_demo_map.gd's golden board does. If this ever
	# legitimately needs to change (e.g. a map/seed change), recompute it by
	# inspection, don't just paste in whatever the renderer currently emits.
	assert_eq(stones.size(), 4, "golden: rng.int_range(3, 5) draws 4 stones for Seeds.DEFAULT_DECORATION_SEED on the demo map")
	assert_eq(stones.size() + trees.size(), eligible.size(), "every eligible blocked tile gets exactly a stone or a tree")

	for tile in stones:
		assert_true(eligible.has(tile), "stone at %s is an eligible blocked tile" % tile)
	for tile in trees:
		assert_true(eligible.has(tile), "tree at %s is an eligible blocked tile" % tile)
	for tile in excluded:
		assert_false(stones.has(tile), "no stone inside the spawn/goal exclusion zone at %s" % tile)
		assert_false(trees.has(tile), "no tree inside the spawn/goal exclusion zone at %s" % tile)

	mr.free()
	return true

# _place fits a texture inside a size_px square box *preserving the source
# aspect ratio*, then centres the result in that box. This is a deliberate
# divergence from the Phaser reference, which calls
# setDisplaySize(TILE_SIZE, TILE_SIZE) and therefore stretches every source
# to a square regardless of its true proportions (see map_renderer.gd's
# DELIBERATE DIVERGENCE note for the reference's own, much more extreme,
# numbers - that history is about the pre-Kenney art and stays there).
#
# The illustrated forest/stone.png this test exercises is 96x61 (about
# 1.57:1), so a regression to non-uniform scaling is still visible here.
# Expected geometry is derived from the texture's own dimensions rather than
# hardcoded, so the rule is what is pinned, not one particular PNG's size.
func test_decorations_preserve_their_aspect_ratio_and_sit_centred_in_the_tile() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var stone: Sprite2D = null
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _STONE_PATH:
			stone = child
			break
	assert_true(stone != null, "a stone sprite was drawn on the demo map")

	var tex := stone.texture
	assert_false(tex.get_width() == tex.get_height(),
		"precondition: stone.png is genuinely non-square (%dx%d), so uniform scaling is observable"
			% [tex.get_width(), tex.get_height()])

	assert_almost_eq(stone.scale.x, stone.scale.y, 0.0001,
		"scale is uniform on both axes - the source is not stretched out of proportion")

	var box := float(Tiles.TILE_SIZE)
	var expected_scale := box / maxf(float(tex.get_width()), float(tex.get_height()))
	assert_almost_eq(stone.scale.x, expected_scale, 0.0001,
		"the longest source axis is fitted to exactly one tile (contain-fit, not cover)")

	var display := Vector2(tex.get_width(), tex.get_height()) * stone.scale
	assert_true(display.x <= box + 0.01 and display.y <= box + 0.01,
		"the scaled sprite fits inside its %dpx tile box (got %.2fx%.2f)" % [Tiles.TILE_SIZE, display.x, display.y])

	# Top-left anchored (centered = false), so centring has to come from the
	# position: without it an aspect-corrected short/wide sprite would hug the
	# top edge of its tile instead of sitting in the middle of it.
	var tile := Vector2i(int(stone.position.x / box), int(stone.position.y / box))
	var origin := Vector2(tile.x * box, tile.y * box)
	assert_almost_eq(stone.position.x - origin.x, (box - display.x) / 2.0, 0.01,
		"horizontal slack is split evenly, centring the sprite in its tile")
	assert_almost_eq(stone.position.y - origin.y, (box - display.y) / 2.0, 0.01,
		"vertical slack is split evenly, centring the sprite in its tile")

	mr.free()
	return true

func test_render_called_twice_does_not_double_up_sprites() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()

	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	var first_count := mr.get_children().size()

	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))
	var second_count := mr.get_children().size()
	assert_eq(second_count, first_count, "re-rendering the same map twice does not accumulate sprites")

	mr.free()
	return true

# A mipmap chain is inert unless the sprite selects a filter that reads it:
# Godot's TEXTURE_FILTER_LINEAR (the project default) samples the base level
# only, however many mip levels exist. MapRenderer draws two different
# filters for two different reasons, and this test checks both.
#
# Props and endpoints (_place, drawn at z_index 1) sample
# LINEAR_WITH_MIPMAPS: painted art past a hard minification (up to 1.83x for
# props, 1.49x for the endpoints), the same case the enemy sprites are now
# in (game/enemy.tscn also filters LINEAR_WITH_MIPMAPS - see test_enemy.gd;
# this used to be the "opposite call" until this task generated their chain
# too).
#
# Ground and road tiles (_place_tile, drawn at z_index -1) stay plain
# LINEAR instead, on purpose: they are region-sampled (region_enabled crops
# the card's painted border, TILE_BLEED) and only mildly minified (1.125x),
# and a mip level would average that cropped border back into the terrain -
# reintroducing by hand the seam the crop exists to remove. See
# _place_tile's doc comment in map_renderer.gd.
#
# The other half of this fix - that a chain actually exists where one is
# wanted, and does not exist where it would actively hurt - is pinned by
# test_art_import.gd, which reads mipmaps/generate off the committed
# .import files for both sides of the split.
func test_map_sprites_select_a_filter_that_actually_samples_the_mipmap_chain() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var overlay_checked := 0
	var ground_checked := 0
	for child in mr.get_children():
		if not (child is Sprite2D):
			continue
		if child.z_index == 1:
			overlay_checked += 1
			assert_eq(child.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"%s (prop/endpoint) samples the mipmap chain when minified" % child.texture.resource_path.get_file())
		elif child.z_index == -1:
			ground_checked += 1
			assert_eq(child.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR,
				("%s (ground/road tile) stays plain LINEAR - a mip chain would " +
				"bleed its cropped card border back into the terrain") %
				child.texture.resource_path.get_file())
	assert_true(overlay_checked > 0, "precondition: the render produced prop/endpoint sprites to check")
	assert_true(ground_checked > 0, "precondition: the render produced ground/road sprites to check")

	mr.free()
	return true

# --------------------------------------------------------------------------
# prop_footprints
# --------------------------------------------------------------------------

# Blocking circles for free placement. Endpoints are deliberately excluded:
# cave.png and castle.png are drawn 3 tiles wide, so a footprint derived from
# them would carry a ~72px radius and sterilise the ground around the spawn
# and the goal - which is exactly where a player most wants a last line of
# defence. The road corridor already keeps towers off the endpoints themselves.
func test_prop_footprints_cover_every_prop_and_no_endpoint() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var prop_paths := [_TREE_PATH, _STONE_PATH, _SPIKE_PATH, _FIRE_PATH]
	var expected := 0
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path in prop_paths:
			expected += 1
	assert_true(expected > 0, "precondition: the demo map draws props at all")

	var footprints := mr.prop_footprints()
	assert_eq(footprints.size(), expected, "one footprint per tree, stone, spike and fire - and nothing else")

	mr.free()
	return true

# The radius is half the LONGEST displayed axis, so it over-covers rather than
# under-covers. Blocking slightly too much reads as level design; a tower
# clipping into a rock reads as a bug. stone.png displays about 48x42, so a
# radius taken from the short axis would give ~21 instead of ~24 - a small
# under-cover here, but the rule the test pins is the one that stays correct
# for whichever prop is least square.
func test_prop_footprint_radius_covers_the_sprite_s_longest_axis() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var stone: Sprite2D = null
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _STONE_PATH:
			stone = child
			break
	assert_true(stone != null, "a stone sprite was drawn")

	var tex := stone.texture
	var display := Vector2(tex.get_width(), tex.get_height()) * stone.scale
	var want_radius := maxf(display.x, display.y) / 2.0
	var want_centre := stone.position + display / 2.0

	var matched := false
	for entry in mr.prop_footprints():
		var f: Dictionary = entry
		if f["pos"].distance_to(want_centre) < 0.01:
			matched = true
			assert_almost_eq(f["radius"], want_radius, 0.01,
				"the stone's radius is half its longest displayed axis")
	assert_true(matched, "a footprint sits at the stone's displayed centre, not its top-left corner")

	mr.free()
	return true

func test_props_come_from_the_biome_being_rendered() -> bool:
	var forest := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	forest.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var forest_paths := {}
	for child in forest.get_children():
		if child is Sprite2D and child.z_index == 1:
			forest_paths[child.texture.resource_path] = true
	forest.free()

	var ice := MapRenderer.new()
	ice.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"ice")
	var shared := 0
	for child in ice.get_children():
		if child is Sprite2D and child.z_index == 1:
			if forest_paths.has(child.texture.resource_path):
				shared += 1
	ice.free()
	# The endpoints are shared across biomes; the props are not.
	assert_true(shared <= 2, "ice props are not forest props (%d shared)" % shared)
	return true

func test_prop_footprints_cover_only_the_props() -> bool:
	# Endpoints are excluded on purpose - they are drawn 3 tiles wide and a
	# footprint from one would sterilise the ground around spawn and goal.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var footprints := renderer.prop_footprints()
	assert_true(footprints.size() > 0, "the demo map scatters props")
	for entry in footprints:
		var f: Dictionary = entry
		var radius: float = f["radius"]
		assert_true(radius > 0.0, "a footprint has a positive radius")
		# A prop is fitted into one 48px tile, so no footprint may exceed half
		# of it. A radius above 24 means an endpoint leaked in - those are
		# drawn 3 tiles wide and would carry a 72px radius, sterilising the
		# ground around spawn and goal.
		assert_true(radius <= float(Tiles.TILE_SIZE) / 2.0,
			"footprint radius %f fits inside one tile" % radius)
	renderer.free()
	return true

func test_every_prop_sprite_contributes_exactly_one_footprint() -> bool:
	# Guards the set-membership swap: a prop that fails to register produces no
	# blocking circle at all and towers build straight through it, which no
	# other assertion here would notice.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var props := 0
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == 1 \
				and not child.texture.resource_path.ends_with("castle.png") \
				and not child.texture.resource_path.ends_with("cave.png"):
			props += 1
	assert_eq(renderer.prop_footprints().size(), props,
		"one footprint per prop sprite, endpoints excluded")
	renderer.free()
	return true

func test_a_props_blocking_radius_is_half_the_box_its_slot_is_fitted_into() -> bool:
	# _place normalises a prop's LONGEST axis to exactly the box it is given,
	# so the radius prop_footprints derives is always half that box whatever
	# the source dimensions are. That is precisely why trimming has to happen
	# at bake time and cannot be compensated for here: the radius does not
	# move to fit the art, so the ART has to fill the box. An untrimmed source
	# drawing its subject at ~23px inside a 24px radius is a blocking circle
	# over twice the area of the visible art. test_prop_assets.gd's tight-bbox
	# gate holds the other half of this bargain.
	#
	# The box is per slot, not one constant: fire is drawn at 80% of a tile
	# because the campfire out-shouted the player's towers. Asserting a single
	# TILE_SIZE / 2 here - which this test did until fire shrank - would pin
	# the wrong invariant, because the property that matters is that the
	# radius follows the box, not that every box is a whole tile.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	# Read the slot off each prop sprite rather than out of the footprint:
	# prop_footprints' dictionaries are a sim-facing contract that
	# sim/placement.gd consumes, and growing them with a key only a test wants
	# is how that contract stops meaning anything.
	var checked := 0
	var scales_seen := {}
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != 1:
			continue
		var sprite: Sprite2D = child
		var slot := sprite.texture.resource_path.get_file().get_basename()
		if not MapRenderer.PROP_SCALE.has(StringName(slot)):
			continue  # castle and cave are drawn at this z and are not props
		var scale: float = float(MapRenderer.PROP_SCALE[StringName(slot)])
		var tex: Texture2D = sprite.texture
		var display := Vector2(tex.get_width(), tex.get_height()) * sprite.scale
		scales_seen[scale] = true
		assert_almost_eq(maxf(display.x, display.y), float(Tiles.TILE_SIZE) * scale, 0.001,
			"%s's longest axis fills its own box exactly" % slot)
		checked += 1
	assert_true(checked > 0, "the demo map scatters props")
	assert_true(scales_seen.size() > 1,
		"and at more than one scale, so this proves something")

	var footprints := renderer.prop_footprints()
	assert_eq(footprints.size(), checked, "one footprint per prop")
	var boxes := {}
	for scale in scales_seen:
		boxes[snappedf(float(Tiles.TILE_SIZE) * float(scale) / 2.0, 0.001)] = true
	for entry in footprints:
		var f: Dictionary = entry
		assert_true(boxes.has(snappedf(float(f["radius"]), 0.001)),
			"a footprint radius of %f is half one of the slot boxes" % f["radius"])
	renderer.free()
	return true

func test_tiles_are_drawn_without_their_card_border() -> bool:
	# The sheet's terrain tiles are cards with a painted dark edge. Drawn
	# whole, every cell boundary carries two of those edges back to back and
	# the map reads as a grid of cards in black gutters. The renderer draws
	# the interior of each tile instead.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		assert_true(sprite.region_enabled, "a tile is drawn from a region")
		var tex: Texture2D = sprite.texture
		assert_eq(sprite.region_rect,
			Rect2(MapRenderer.TILE_BLEED, MapRenderer.TILE_BLEED,
				tex.get_width() - MapRenderer.TILE_BLEED * 2.0,
				tex.get_height() - MapRenderer.TILE_BLEED * 2.0),
			"the region is the tile's interior")
		checked += 1
	assert_true(checked > 0, "tiles were checked")
	renderer.free()
	return true

func test_the_bleed_is_wide_enough_for_the_widest_card_border() -> bool:
	# Measured: probing inward from each edge of all 66 ground and road PNGs
	# in all three biomes, the run of near-black pixels - the card's border
	# plus _trim's 1px pad - never exceeds 5. A bleed under that leaves a dark
	# line; far over it eats art. This pins the measurement rather than the
	# taste.
	var worst := 0
	for biome in Biomes.KINDS:
		for i in Biomes.GROUND_VARIANTS:
			worst = maxi(worst, _border_run(Biomes.ground_path(biome, i)))
		for mask in 16:
			worst = maxi(worst, _border_run(Biomes.road_path(biome, mask)))
	assert_true(worst > 0, "the tiles do have a card border to crop")
	assert_true(MapRenderer.TILE_BLEED > worst,
		"the bleed %d clears the widest border %d" % [MapRenderer.TILE_BLEED, worst])
	assert_true(MapRenderer.TILE_BLEED <= worst + 3,
		"the bleed %d does not eat art beyond the border %d"
			% [MapRenderer.TILE_BLEED, worst])
	return true

## Longest run of near-black pixels reaching in from any edge of a tile.
func _border_run(path: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return 0
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return 0
	var w := img.get_width()
	var h := img.get_height()
	var worst := 0
	for probe in [w / 4, w / 2, 3 * w / 4]:
		worst = maxi(worst, _run_from(img, probe, 0, 0, 1))
		worst = maxi(worst, _run_from(img, probe, h - 1, 0, -1))
	for probe in [h / 4, h / 2, 3 * h / 4]:
		worst = maxi(worst, _run_from(img, 0, probe, 1, 0))
		worst = maxi(worst, _run_from(img, w - 1, probe, -1, 0))
	return worst

func _run_from(img: Image, x: int, y: int, dx: int, dy: int) -> int:
	var n := 0
	while x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		var c := img.get_pixel(x, y)
		var lum := (c.r + c.g + c.b) / 3.0 * c.a
		if lum >= 45.0 / 255.0:
			break
		n += 1
		x += dx
		y += dy
	return n

# --------------------------------------------------------------------------
# ground orientation
# --------------------------------------------------------------------------

# Six ground cards over 322 cells put the same picture down roughly 54 times,
# and the eye reads that repetition as a grid rather than as a field.
#
# Measured on the composed board: the ground's self-similarity at a lag of
# exactly one tile sits +55.8 above its neighbouring lags, which is the
# periodic signal that reads as "grid-like". Drawing each ground tile at a
# random one of four orientations turns six cards into twenty-four and cuts
# that excess to +22.0, a 61% reduction, at no cost to the art.
#
# Two things measured and rejected on the way: normalising each card's mean
# colour toward the biome's moved the number by nothing (+22.0 to +22.6, which
# is noise) and would have flattened the deliberate dirt patches; and
# cross-fading the tile edges reduced the variation INSIDE a tile by 42%,
# which is softening the grass rather than fixing the grid. The seams were
# never the problem - the luminance step across a tile boundary measured no
# larger than the step inside one.
func test_ground_tiles_are_drawn_at_a_mix_of_orientations() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var seen := {}
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		if sprite.texture.resource_path.contains("road_"):
			continue
		seen["%s%s" % [sprite.flip_h, sprite.flip_v]] = true
	assert_eq(seen.size(), 4, "all four orientations appear on the board")
	renderer.free()
	return true

func test_road_pieces_are_never_flipped() -> bool:
	# A road piece is chosen by an edge mask, so flipping one draws the wrong
	# connections - a north-east corner mirrored into a north-west one, with
	# the mask still saying north-east.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		if not sprite.texture.resource_path.contains("road_"):
			continue
		assert_false(sprite.flip_h, "a road piece is not mirrored horizontally")
		assert_false(sprite.flip_v, "a road piece is not mirrored vertically")
		checked += 1
	assert_true(checked > 0, "the demo map has road to check")
	renderer.free()
	return true

func test_the_ground_orientation_is_reproducible_from_the_seed() -> bool:
	# Same seed, same board. The whole harness rests on that.
	var first := []
	var second := []
	for pass_index in 2:
		var renderer := MapRenderer.new()
		var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
		renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
		for child in renderer.get_children():
			if child is Sprite2D and child.z_index == -1:
				var sprite: Sprite2D = child
				var entry := "%s|%s%s" % [sprite.texture.resource_path,
					sprite.flip_h, sprite.flip_v]
				if pass_index == 0:
					first.append(entry)
				else:
					second.append(entry)
		renderer.free()
	assert_true(first.size() > 0, "the board drew something")
	assert_eq(first, second, "two renders from the same seed agree tile for tile")
	return true
