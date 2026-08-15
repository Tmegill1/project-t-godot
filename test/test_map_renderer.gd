extends TestCase

# MapRenderer draws Sprite2D children rather than using a TileMapLayer, so
# these tests inspect the child tree (position, z_index, texture) rather
# than a tilemap API. Textures are identified by their public
# Texture2D.resource_path rather than by reaching into MapRenderer's private
# _decorations dict, so these tests only rely on public state.

const _SPIKE_PATH := "res://assets/map/spike.png"
const _FIRE_PATH := "res://assets/map/fire.png"
const _STONE_PATH := "res://assets/map/stone.png"
const _TREE_PATH := "res://assets/map/tree.png"
const _CAVE_PATH := "res://assets/map/cave.png"
const _CASTLE_PATH := "res://assets/map/castle.png"
const _GRASS_PATH := "res://assets/map/grass.png"
const _PATH_PATH := "res://assets/map/path.png"

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

func _grid_overlay(mr: MapRenderer) -> Node2D:
	for child in mr.get_children():
		if child is MapRenderer._GridOverlay:
			return child
	return null

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

func test_ground_layer_has_one_sprite_per_tile_with_the_right_texture() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var ground_by_pos := {}
	for child in mr.get_children():
		if child is Sprite2D and child.z_index == -1:
			ground_by_pos[child.position] = child.texture.resource_path
			assert_false(child.centered, "ground sprites are top-left anchored (centered = false), matching Phaser's setOrigin(0,0)")
	assert_eq(ground_by_pos.size(), DemoMap.GRID_COLS * DemoMap.GRID_ROWS, "one ground sprite per tile")

	for r in tiles.size():
		for c in tiles[r].size():
			var pos := Vector2(c * Tiles.TILE_SIZE, r * Tiles.TILE_SIZE)
			assert_true(ground_by_pos.has(pos), "a ground sprite exists at col %d row %d" % [c, r])
			var kind = tiles[r][c]
			var expected := _PATH_PATH if (kind == Tiles.PATH or kind == Tiles.SPAWN or kind == Tiles.GOAL) else _GRASS_PATH
			assert_eq(ground_by_pos.get(pos), expected, "ground texture at col %d row %d" % [c, r])

	mr.free()
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

	var offset := Vector2(-Tiles.TILE_SIZE, -Tiles.TILE_SIZE - 20)
	assert_eq(cave.position, Vector2(spawn_tile.x * Tiles.TILE_SIZE, spawn_tile.y * Tiles.TILE_SIZE) + offset,
		"cave sits at the spawn tile origin plus the (-TILE_SIZE, -TILE_SIZE - 20) offset")
	assert_eq(castle.position, Vector2(goal_tile.x * Tiles.TILE_SIZE, goal_tile.y * Tiles.TILE_SIZE) + offset,
		"castle sits at the goal tile origin plus the (-TILE_SIZE, -TILE_SIZE - 20) offset")

	var target := float(Tiles.TILE_SIZE * 3)
	assert_almost_eq(cave.scale.x * cave.texture.get_width(), target, 0.01, "cave display width is TILE_SIZE * 3")
	assert_almost_eq(cave.scale.y * cave.texture.get_height(), target, 0.01, "cave display height is TILE_SIZE * 3")
	assert_almost_eq(castle.scale.x * castle.texture.get_width(), target, 0.01, "castle display width is TILE_SIZE * 3")
	assert_almost_eq(castle.scale.y * castle.texture.get_height(), target, 0.01, "castle display height is TILE_SIZE * 3")

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

func test_clear_decoration_at_removes_a_decorated_tile_and_is_idempotent() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var decorated_positions := {}
	for child in mr.get_children():
		if child is Sprite2D and (child.texture.resource_path == _SPIKE_PATH or child.texture.resource_path == _FIRE_PATH):
			var t := Vector2i(int(child.position.x / Tiles.TILE_SIZE), int(child.position.y / Tiles.TILE_SIZE))
			decorated_positions[t] = true
	assert_true(decorated_positions.size() > 0, "the demo map has at least one decorated tile")
	var decorated_tile: Vector2i = decorated_positions.keys()[0]

	var undecorated_tile := Vector2i(-1, -1)
	for r in tiles.size():
		for c in tiles[r].size():
			if tiles[r][c] == Tiles.BUILDABLE and not decorated_positions.has(Vector2i(c, r)):
				undecorated_tile = Vector2i(c, r)
	assert_true(undecorated_tile.x >= 0, "found a buildable tile with no decoration on it")

	assert_false(mr.clear_decoration_at(undecorated_tile.x, undecorated_tile.y), "clearing an undecorated tile returns false")

	assert_true(mr.clear_decoration_at(decorated_tile.x, decorated_tile.y), "clearing a decorated tile returns true")

	var still_present := false
	for child in mr.get_children():
		if child is Sprite2D and (child.texture.resource_path == _SPIKE_PATH or child.texture.resource_path == _FIRE_PATH):
			var t := Vector2i(int(child.position.x / Tiles.TILE_SIZE), int(child.position.y / Tiles.TILE_SIZE))
			if t == decorated_tile:
				still_present = true
	assert_false(still_present, "the sprite for the cleared tile is actually gone from the scene tree")

	assert_false(mr.clear_decoration_at(decorated_tile.x, decorated_tile.y), "clearing an already-cleared tile is idempotent (returns false)")

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

	var grid_overlays := 0
	for child in mr.get_children():
		if child is MapRenderer._GridOverlay:
			grid_overlays += 1
	assert_eq(grid_overlays, 1, "exactly one grid overlay survives after two renders, not two")

	mr.free()
	return true

func test_grid_overlay_line_count_and_bounds() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var grid := _grid_overlay(mr)
	assert_true(grid != null, "render() adds a grid overlay node")

	var lines: Array = grid.grid_lines()
	var expected_line_count := (DemoMap.GRID_COLS + 1) + (DemoMap.GRID_ROWS + 1)
	assert_eq(lines.size(), expected_line_count, "cols + 1 verticals plus rows + 1 horizontals")

	var full_height := DemoMap.GRID_ROWS * Tiles.TILE_SIZE
	var full_width := DemoMap.GRID_COLS * Tiles.TILE_SIZE
	assert_eq(lines[0], [Vector2(0, 0), Vector2(0, full_height)], "first vertical line is the left edge, x = 0")
	assert_eq(lines[DemoMap.GRID_COLS], [Vector2(full_width, 0), Vector2(full_width, full_height)],
		"last vertical line is the right edge, x = cols * TILE_SIZE (inclusive outer edge)")
	assert_eq(lines[DemoMap.GRID_COLS + 1], [Vector2(0, 0), Vector2(full_width, 0)], "first horizontal line is the top edge, y = 0")
	assert_eq(lines[lines.size() - 1], [Vector2(0, full_height), Vector2(full_width, full_height)],
		"last horizontal line is the bottom edge, y = rows * TILE_SIZE (inclusive outer edge)")

	mr.free()
	return true

func test_grid_overlay_sizes_itself_from_the_tiles_argument_not_demo_map_constants() -> bool:
	# A synthetic 5x3 grid, deliberately not 23x14, proving the grid (and
	# the rest of the renderer) sizes itself from whatever is passed to
	# render(), not from DemoMap's or Maps' constants.
	Grid.set_active(5, 3)
	var synthetic: Array = []
	for r in 3:
		var row: Array = []
		for c in 5:
			row.append(Tiles.BUILDABLE)
		synthetic.append(row)

	var mr := MapRenderer.new()
	mr.render(synthetic, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var grid := _grid_overlay(mr)
	assert_true(grid != null, "a grid overlay node was added for the synthetic map")
	assert_eq(grid.grid_lines().size(), (5 + 1) + (3 + 1), "grid line count derives from the 5x3 tiles argument, not 23x14")

	var ground_count := 0
	for child in mr.get_children():
		if child is Sprite2D and child.z_index == -1:
			ground_count += 1
	assert_eq(ground_count, 5 * 3, "ground layer also derives from the tiles argument")

	mr.free()
	return true

func test_grid_overlay_sits_above_ground_and_below_decoration() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var grid := _grid_overlay(mr)
	assert_true(grid != null, "render() adds a grid overlay node")
	assert_eq(grid.z_index, 0, "the grid overlay sits at z_index 0")

	var ground_z := -999
	var overlay_z := -999
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _GRASS_PATH:
			ground_z = child.z_index
		elif child is Sprite2D and child.texture.resource_path == _SPIKE_PATH:
			overlay_z = child.z_index
	assert_eq(ground_z, -1, "the ground layer sits at z_index -1, below the grid")
	assert_eq(overlay_z, 1, "the decoration layer sits at z_index 1, above the grid")
	assert_true(ground_z < grid.z_index, "ground draws below the grid")
	assert_true(grid.z_index < overlay_z, "the grid draws below decoration/endpoints/blocked overlays")

	mr.free()
	return true

# _GRID_LINE_COLOR is a plain script-level const on a class_name script, so
# it is readable directly via MapRenderer._GRID_LINE_COLOR - no scene tree,
# node instantiation, or draw pass required. (An earlier version of this
# suite treated the grid's draw color as untestable in headless mode,
# reasoning that _draw()'s draw_line calls only execute during a live
# render pass; that reasoning is correct for verifying what actually gets
# painted to a canvas, but wrong for reading the constant the drawing code
# would use - the two are different questions, and this test answers the
# one that is actually checkable here.)
func test_grid_line_color_matches_the_reference() -> bool:
	assert_eq(MapRenderer._GRID_LINE_COLOR, Color8(0x2a, 0x2a, 0x2a),
		"grid overlay strokes match the reference MapRenderer.ts drawGrid()'s 0x2a2a2a")
	return true
