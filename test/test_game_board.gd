extends TestCase

# GameBoard is the hub that wires sim to views, so most of these tests read
# and mutate its private state directly (Grid tile scans, _occupied,
# _counts, _selected_tower, ...) the same way test_enemy.gd and
# test_tower.gd reach into Enemy/Tower's own private state.
#
# @onready resolution: as in test_enemy.gd/test_tower.gd, add_child() alone
# does not resolve @onready fields in this harness (test/run_tests.gd runs
# inside SceneTree._initialize(), before the tree's own root has entered a
# tree - confirmed empirically by Task 17, and reconfirmed here for the
# board's own onready fields). _ready_board() below fires
# NOTIFICATION_READY on the freshly instantiated board directly, which
# resolves GameBoard's own @onready fields (_map_renderer, _towers_root,
# _enemies_root, _projectiles_root) and runs the real _ready() body (Grid
# setup, tile build, map render, path computation) - so every test gets a
# fully initialised board with Grid already active for the demo map.
#
# A further consequence matters for _try_place()/_spawn(): both instantiate
# a Tower/Enemy, add_child() it under a board that itself never entered a
# live tree, and immediately call setup() - so the spawned node's OWN
# @onready fields (Tower._sprite/_range_indicator, Enemy._sprite/
# _health_bar) are never resolved either, and setup() aborts partway
# through the first statement that touches one of them (Godot prints a
# SCRIPT ERROR and substitutes that call's default, per run_tests.gd's
# documented crash-recovery semantics - the caller is unaffected). Verified
# directly with a throwaway probe before writing any test below: every
# board-owned field setup() assigns BEFORE that line - kind, grid_col/
# grid_row, price_paid, position, _def for Tower; kind, sim (fully
# populated), position for Enemy - lands correctly, and only the purely
# visual remainder (sprite texture/scale, range indicator, health bar) is
# skipped. So tests that exercise _try_place()/_spawn() (placement rules,
# wave spawn timing, budget/limit boundaries) print SCRIPT ERROR noise from
# the engine - exactly like test_harness_selfcheck.gd's crash probes - and
# that noise is expected, not a failure; the board-logic assertions
# alongside it are unaffected because they only read fields set before the
# crash point. Tests that don't need that flow (splash resolution, firing a
# projectile) instead build their own enemies with _ready_enemy_under(),
# which fires NOTIFICATION_READY before setup() so nothing crashes there.

func _instantiate_board() -> GameBoard:
	return load("res://game/game_board.tscn").instantiate()

func _ready_board() -> GameBoard:
	var b := _instantiate_board()
	b.notification(Node.NOTIFICATION_READY)
	return b

func _ready_enemy_under(root: Node2D, kind: StringName, pos: Vector2) -> Enemy:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	e.notification(Node.NOTIFICATION_READY)
	root.add_child(e)
	e.setup(kind, PackedVector2Array([pos, pos + Vector2(1.0, 0.0)]), 1)
	return e

## First `count` BUILDABLE tiles found scanning the board's own tiles in
## row-major order. The demo map's generation is seeded and deterministic,
## so this is stable across runs without hardcoding coordinates that would
## silently go stale if the map or its seed ever changed.
func _find_buildable_tiles(b: GameBoard, count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == Tiles.BUILDABLE:
				found.append(Vector2i(c, r))
				if found.size() >= count:
					return found
	return found

func _find_tile(b: GameBoard, kind: StringName) -> Vector2i:
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == kind:
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func _find_decorated_buildable_tile(b: GameBoard) -> Vector2i:
	for key in b._map_renderer._decorations.keys():
		return key
	return Vector2i(-1, -1)

# --------------------------------------------------------------------------
# _ready()
# --------------------------------------------------------------------------

func test_ready_emits_initial_gold_lives_and_wave() -> bool:
	var b := _instantiate_board()
	var gold_events: Array = []
	var lives_events: Array = []
	var wave_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	b.lives_changed.connect(func(l): lives_events.append(l))
	b.wave_changed.connect(func(w, m): wave_events.append([w, m]))

	b.notification(Node.NOTIFICATION_READY)

	var expected_gold := int(Maps.get_def(Maps.FIRST)["starting_gold"])
	assert_eq(gold_events, [expected_gold], "gold_changed fires once at _ready() with the map's starting gold")
	assert_eq(lives_events, [Economy.STARTING_LIVES], "lives_changed fires once at _ready() with STARTING_LIVES")
	assert_eq(wave_events, [[0, Waves.MAX_WAVES]], "wave_changed fires once at _ready() with wave 0")
	assert_eq(b.get_gold(), expected_gold, "get_gold reflects the same value")
	assert_eq(b.get_lives(), Economy.STARTING_LIVES, "get_lives reflects the same value")
	assert_eq(b.get_wave(), 0, "no wave has started yet")
	assert_false(b.is_wave_active(), "no wave is active yet")
	b.free()
	return true

# --------------------------------------------------------------------------
# Placement rejection reasons
# --------------------------------------------------------------------------

func test_handle_tap_off_grid_is_ignored() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var rejected := {"count": 0}
	b.placement_rejected.connect(func(_r): rejected["count"] += 1)
	var gold_before := b.get_gold()

	# Deliberately one tile short of the grid, not a huge negative offset:
	# world_to_tile(-24, -24) resolves to col=-1, row=-1, and GDScript Array
	# indexing treats a small negative index as "from the end" rather than
	# raising an out-of-bounds error - so a broken `in_bounds` guard would
	# silently fall through to _try_place() reading a real (wrong) tile
	# instead of crashing before this test's assertions run. A far-off-grid
	# coordinate like (-1000, -1000) would instead hit a genuine
	# out-of-bounds error inside _try_place() and abort that call before any
	# rejection/placement state changes - which would make this test pass
	# "by accident" even with the `in_bounds` guard inverted, since the
	# crash (not the guard) is what stopped the placement. Confirmed by
	# actually running that mutation against the (-1000, -1000) version
	# before switching to this one.
	b._handle_tap(Vector2(-24, -24))

	assert_eq(rejected["count"], 0, "an off-grid tap is silently ignored, not rejected")
	assert_eq(b.get_gold(), gold_before, "no gold spent")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower placed")
	b.free()
	return true

func test_try_place_rejects_a_non_buildable_tile() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var blocked := _find_tile(b, Tiles.BLOCKED)
	assert_true(blocked.x >= 0, "precondition: the demo map has at least one blocked tile")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)

	b._try_place(blocked.x, blocked.y)

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "You can only build on open ground.", "reason names open ground")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower placed")
	b.free()
	return true

# Isolates `>=` from `>`: exactly at budget, the next placement must be
# rejected; a mutation to `>` would let it through.
func test_try_place_enforces_the_tower_budget_at_the_boundary() -> bool:
	var b := _ready_board()
	b._gold = 1000000
	var budget := int(Maps.get_def(Maps.FIRST)["tower_budget"])
	assert_eq(budget, 16, "precondition: demoMap's tower_budget is 16")
	var tiles := _find_buildable_tiles(b, budget + 1)
	assert_eq(tiles.size(), budget + 1, "precondition: enough buildable tiles exist for this test")

	# basic's per-kind limit is 8 and fast's is 8 (8 + 8 = 16), so filling
	# the budget exactly does not also trip the per-kind limit check first.
	for i in budget:
		b.select_tower_kind(&"basic" if i < 8 else &"fast")
		b._try_place(tiles[i].x, tiles[i].y)
	assert_eq(b._towers_root.get_child_count(), budget, "precondition: exactly `budget` towers placed")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b.select_tower_kind(&"basic")
	b._try_place(tiles[budget].x, tiles[budget].y)

	assert_eq(rejected["count"], 1, "the (budget + 1)th placement is rejected")
	assert_eq(rejected["reason"], "Tower budget reached.", "budget rejection message")
	assert_eq(b._towers_root.get_child_count(), budget, "still exactly `budget` towers - none snuck in")
	b.free()
	return true

# Isolates `>=` from `>` for the per-kind limit specifically (mortar's
# limit of 5 sits well under the budget of 16, so the budget check cannot
# be the one firing here).
func test_try_place_enforces_the_per_kind_limit_at_the_boundary() -> bool:
	var b := _ready_board()
	b._gold = 1000000
	var kind := &"mortar"
	var limit := EconomySim.tower_limit(kind, Maps.FIRST)
	assert_eq(limit, 5, "precondition: mortar's tower_limit on demoMap is 5")
	var tiles := _find_buildable_tiles(b, limit + 1)
	b.select_tower_kind(kind)
	for i in limit:
		b._try_place(tiles[i].x, tiles[i].y)
	assert_eq(b.get_tower_count(kind), limit, "precondition: exactly the limit placed")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b._try_place(tiles[limit].x, tiles[limit].y)

	assert_eq(rejected["count"], 1, "the (limit + 1)th placement of the same kind is rejected")
	assert_eq(rejected["reason"], "You cannot build any more of that tower.", "per-kind limit message")
	assert_eq(b.get_tower_count(kind), limit, "count did not exceed the limit")
	b.free()
	return true

func test_try_place_rejects_when_gold_is_insufficient() -> bool:
	var b := _ready_board()
	b._gold = 5  # below basic's base price of 20
	b.select_tower_kind(&"basic")
	var tile := _find_buildable_tiles(b, 1)[0]
	var expected_price := EconomySim.tower_price(&"basic", 0)

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b._try_place(tile.x, tile.y)

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "Not enough gold — that costs %d." % expected_price,
		"reason includes the exact price the tower would have cost")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower placed")
	assert_eq(b.get_gold(), 5, "gold untouched")
	b.free()
	return true

# --------------------------------------------------------------------------
# Successful placement
# --------------------------------------------------------------------------

func test_try_place_success_deducts_gold_marks_occupied_and_emits_signals() -> bool:
	var b := _ready_board()
	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"fast")
	var gold_before := b.get_gold()
	var expected_price := EconomySim.tower_price(&"fast", 0)

	var gold_events: Array = []
	var placed_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	b.tower_placed.connect(func(k): placed_events.append(k))

	b._try_place(tile.x, tile.y)

	assert_eq(b.get_gold(), gold_before - expected_price, "gold reduced by exactly the price")
	assert_eq(gold_events, [b.get_gold()], "gold_changed emitted exactly once with the new total")
	assert_eq(placed_events, [&"fast"], "tower_placed emitted exactly once with the placed kind")
	assert_eq(b.get_tower_count(&"fast"), 1, "per-kind count incremented")
	assert_true(b._occupied.has(tile), "tile marked occupied")
	assert_eq(b._occupied[tile].kind, &"fast", "the occupying tower is the one just placed")
	assert_eq(b._towers_root.get_child_count(), 1, "one tower node added")
	b.free()
	return true

func test_try_place_success_clears_the_tiles_decoration() -> bool:
	var b := _ready_board()
	var tile := _find_decorated_buildable_tile(b)
	assert_true(tile.x >= 0, "precondition: the demo map has at least one decorated buildable tile")
	assert_true(b._map_renderer._decorations.has(tile), "precondition: a decoration sits on this tile before placement")

	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)

	assert_false(b._map_renderer._decorations.has(tile), "the decoration is cleared once a tower occupies its tile")
	b.free()
	return true

func test_placing_a_second_tower_of_a_kind_charges_the_escalated_price() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var tiles := _find_buildable_tiles(b, 2)
	b.select_tower_kind(&"basic")

	var first_price := EconomySim.tower_price(&"basic", 0)
	var second_price := EconomySim.tower_price(&"basic", 1)
	assert_true(second_price > first_price, "precondition: the second tower costs strictly more than the first")

	b._try_place(tiles[0].x, tiles[0].y)
	var gold_after_first := b.get_gold()
	b._try_place(tiles[1].x, tiles[1].y)

	assert_eq(gold_after_first, 1000 - first_price, "the first tower was charged the base price")
	assert_eq(b.get_gold(), gold_after_first - second_price, "the second tower was charged the escalated price, not the base again")
	b.free()
	return true

# --------------------------------------------------------------------------
# Selection / selling
# --------------------------------------------------------------------------

func test_select_tower_kind_deselects_the_currently_selected_tower() -> bool:
	var b := _ready_board()
	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)
	b._handle_tap(Grid.tile_to_world_center(tile.x, tile.y))
	assert_true(b._selected_tower != null, "precondition: a tower is selected")

	b.select_tower_kind(&"fast")

	assert_eq(b._selected_tower, null, "picking a different kind to build clears the current tower selection")
	b.free()
	return true

func test_handle_tap_with_no_kind_selected_deselects_and_does_not_place() -> bool:
	var b := _ready_board()
	var tiles := _find_buildable_tiles(b, 2)
	b.select_tower_kind(&"basic")
	b._try_place(tiles[0].x, tiles[0].y)
	b._handle_tap(Grid.tile_to_world_center(tiles[0].x, tiles[0].y))  # select it
	assert_true(b._selected_tower != null, "precondition: a tower is selected")

	b._selected_kind = &""
	b._handle_tap(Grid.tile_to_world_center(tiles[1].x, tiles[1].y))  # a different, empty buildable tile

	assert_eq(b._selected_tower, null, "tapping empty ground with nothing selected clears the tower selection")
	assert_eq(b._towers_root.get_child_count(), 1, "no new tower was placed")
	b.free()
	return true

func test_sell_selected_tower_refunds_decrements_frees_tile_and_deselects() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"long")
	b._try_place(tile.x, tile.y)
	var price_paid := EconomySim.tower_price(&"long", 0)
	var gold_after_placement := b.get_gold()

	b._handle_tap(Grid.tile_to_world_center(tile.x, tile.y))  # taps the occupied tile -> selects it
	assert_eq(b._selected_tower, b._occupied[tile], "precondition: the placed tower is selected")

	var gold_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	var expected_refund := EconomySim.sell_refund(price_paid)

	b.sell_selected_tower()

	assert_eq(b.get_gold(), gold_after_placement + expected_refund, "gold increased by exactly the refund")
	assert_eq(gold_events, [b.get_gold()], "gold_changed emitted exactly once")
	assert_eq(b.get_tower_count(&"long"), 0, "per-kind count decremented")
	assert_false(b._occupied.has(tile), "the tile is free again")
	assert_eq(b._selected_tower, null, "selling deselects")
	b.free()
	return true

func test_get_tower_count_starts_zero_rises_on_placement_falls_on_sell_and_is_zero_for_unknown_kinds() -> bool:
	var b := _ready_board()
	for kind in Towers.KINDS:
		assert_eq(b.get_tower_count(kind), 0, "%s starts at zero" % kind)
	assert_eq(b.get_tower_count(&"not_a_real_kind"), 0, "an unknown kind returns 0 rather than erroring")

	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"mortar")
	b._try_place(tile.x, tile.y)
	assert_eq(b.get_tower_count(&"mortar"), 1, "count rises on placement")

	b._handle_tap(Grid.tile_to_world_center(tile.x, tile.y))
	b.sell_selected_tower()
	assert_eq(b.get_tower_count(&"mortar"), 0, "count falls back to zero on sell")
	b.free()
	return true

# --------------------------------------------------------------------------
# Wave flow
# --------------------------------------------------------------------------

func test_start_next_wave_is_a_no_op_while_a_wave_is_active() -> bool:
	var b := _ready_board()
	b.start_next_wave()
	assert_eq(b.get_wave(), 1, "precondition: the first call starts wave 1")
	assert_true(b.is_wave_active(), "precondition: wave 1 is active")

	b.start_next_wave()

	assert_eq(b.get_wave(), 1, "a second call while still active does not advance the wave")
	b.free()
	return true

# Isolates `>` from `>=` on start_next_wave's own MAX_WAVES guard: the last
# wave itself (MAX_WAVES) must still be startable, and only a call past it
# is refused.
func test_start_next_wave_can_start_wave_max_waves_but_not_beyond() -> bool:
	var b := _ready_board()
	b._wave = Waves.MAX_WAVES - 1  # the upcoming call increments this to MAX_WAVES

	b.start_next_wave()

	assert_eq(b.get_wave(), Waves.MAX_WAVES, "the last wave (MAX_WAVES) can still be started (>, not >=)")
	assert_true(b.is_wave_active(), "wave MAX_WAVES is genuinely active, not silently refused")

	b._wave_active = false  # simulate that wave having cleared, without going through victory
	b.start_next_wave()

	assert_eq(b.get_wave(), Waves.MAX_WAVES + 1,
		"a call past the last wave still increments _wave (amendment 6's known edge)")
	assert_false(b.is_wave_active(), "...but does not actually start a wave beyond MAX_WAVES")
	b.free()
	return true

func test_start_next_wave_is_a_no_op_once_the_run_is_finished() -> bool:
	var b := _ready_board()
	b._run_finished = true
	b.start_next_wave()
	assert_eq(b.get_wave(), 0, "a finished run never starts a new wave")
	assert_false(b.is_wave_active(), "wave stays inactive")
	b.free()
	return true

func test_start_next_wave_emits_wave_changed_and_wave_state_changed() -> bool:
	var b := _ready_board()
	var wave_events: Array = []
	var state_events: Array = []
	b.wave_changed.connect(func(w, m): wave_events.append([w, m]))
	b.wave_state_changed.connect(func(a): state_events.append(a))

	b.start_next_wave()

	assert_eq(wave_events, [[1, Waves.MAX_WAVES]], "wave_changed carries the new wave number and MAX_WAVES")
	assert_eq(state_events, [true], "wave_state_changed(true) fires exactly once")
	b.free()
	return true

# Isolates `<=` from `<` in the spawn-schedule gate: a clock landing exactly
# on a spawn's at_ms must still spawn it this tick, not the next.
func test_physics_process_spawns_enemies_exactly_when_the_clock_reaches_at_ms() -> bool:
	var b := _ready_board()
	b.start_next_wave()  # wave 1: 5 slimes at at_ms 0, 500, 1000, 1500, 2000
	assert_eq(b._spawn_queue[0]["at_ms"], 0.0, "precondition: the first slime spawns at t=0")
	assert_eq(b._spawn_queue[1]["at_ms"], 500.0, "precondition: the second slime spawns at t=500")

	b._physics_process(0.0)  # delta 0: _wave_clock stays at 0.0, only the t=0 spawn is due
	assert_eq(b._enemies_root.get_child_count(), 1, "only the t=0 spawn has occurred")

	b._wave_clock = 499.0  # direct assignment avoids any float-accumulation risk in the pin below
	b._physics_process(0.0)
	assert_eq(b._enemies_root.get_child_count(), 1, "at 499ms the t=500 spawn is not yet due")

	b._wave_clock = 500.0
	b._physics_process(0.0)
	assert_eq(b._enemies_root.get_child_count(), 2, "the clock landing exactly on at_ms=500 spawns it too (<=, not <)")
	b.free()
	return true

func test_wave_clears_only_after_every_spawn_has_left_the_board() -> bool:
	var b := _ready_board()
	b.start_next_wave()
	b._spawn_queue = [{"kind": &"slime", "at_ms": 0.0}]
	b._wave_clock = 0.0
	b._spawned = 0

	var state_events: Array = []
	b.wave_state_changed.connect(func(a): state_events.append(a))

	b._physics_process(0.0)  # spawns the one enemy
	assert_eq(b._enemies_root.get_child_count(), 1, "precondition: the one scheduled enemy spawned")
	assert_true(b.is_wave_active(), "still active - the enemy has not left yet")

	b._physics_process(0.0)  # schedule exhausted, but the enemy is still present
	assert_true(b.is_wave_active(), "wave does not clear while an enemy remains, even once the schedule is exhausted")

	# In real play the enemy would leak or die and queue_free() itself, but
	# queue_free() only takes effect at the end of a frame, which never
	# arrives in this synchronous harness (amendment 6). A direct free()
	# stands in for "the deferred removal has now happened."
	b._enemies_root.get_child(0).free()

	b._physics_process(0.0)
	assert_false(b.is_wave_active(), "the wave clears once the schedule is exhausted and no enemies remain")
	assert_eq(state_events, [false], "wave_state_changed(false) fires exactly once")
	b.free()
	return true

# Isolates `>=` from `>`, and the `and not _run_finished` half, on the
# victory condition.
func test_clearing_wave_twenty_emits_victory_exactly_once() -> bool:
	var b := _ready_board()
	b._wave = Waves.MAX_WAVES
	b._wave_active = true

	var victory_count := {"n": 0}
	b.victory.connect(func(): victory_count["n"] += 1)

	b._on_wave_cleared()

	assert_eq(victory_count["n"], 1, "victory fires exactly once on clearing the last wave")
	assert_true(b._run_finished, "the run is marked finished")
	assert_false(b.is_wave_active(), "the wave is no longer active")

	b._on_wave_cleared()  # a spurious second clear must not double-fire
	assert_eq(victory_count["n"], 1, "victory does not fire again once the run is already finished")
	b.free()
	return true

func test_clearing_wave_nineteen_does_not_emit_victory() -> bool:
	var b := _ready_board()
	b._wave = Waves.MAX_WAVES - 1
	b._wave_active = true

	var victory_count := {"n": 0}
	b.victory.connect(func(): victory_count["n"] += 1)

	b._on_wave_cleared()

	assert_eq(victory_count["n"], 0, "clearing wave 19 (one short of MAX_WAVES) does not end the run")
	assert_false(b._run_finished, "the run is not finished yet")
	b.free()
	return true

# --------------------------------------------------------------------------
# Lives / leaks
# --------------------------------------------------------------------------

func test_enemy_leak_subtracts_lives_by_the_value_leak_resolve_produces() -> bool:
	var b := _ready_board()
	b.start_next_wave()
	b._spawn_queue = [{"kind": &"bee", "at_ms": 0.0}]
	b._wave_clock = 0.0
	b._spawned = 0
	b._physics_process(0.0)  # spawns the bee and wires its died/leaked signals to the board
	var enemy: Enemy = b._enemies_root.get_child(0)

	var lives_events: Array = []
	b.lives_changed.connect(func(l): lives_events.append(l))
	var lives_before := b.get_lives()

	var expected_loss := Leak.resolve(
		{"life_loss": Enemies.DEFS[&"bee"]["life_loss"], "health": enemy.sim["health"]}, b.get_wave())
	enemy.leaked.emit(expected_loss)

	assert_eq(b.get_lives(), lives_before - expected_loss, "lives dropped by exactly the value the leaked signal carried")
	assert_eq(lives_events, [b.get_lives()], "lives_changed fired exactly once")
	b.free()
	return true

func test_enemy_died_signal_adds_its_reward_to_gold() -> bool:
	var b := _ready_board()
	b.start_next_wave()
	b._spawn_queue = [{"kind": &"ogre", "at_ms": 0.0}]
	b._wave_clock = 0.0
	b._spawned = 0
	b._physics_process(0.0)  # spawns the ogre and wires its died/leaked signals to the board
	var enemy: Enemy = b._enemies_root.get_child(0)

	var gold_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	var gold_before := b.get_gold()
	var reward := int(Enemies.DEFS[&"ogre"]["reward"])

	enemy.died.emit(reward)

	assert_eq(b.get_gold(), gold_before + reward, "gold increased by exactly the enemy's reward")
	assert_eq(gold_events, [b.get_gold()], "gold_changed fired exactly once")
	b.free()
	return true

func test_leak_that_does_not_drain_all_lives_does_not_end_the_run() -> bool:
	var b := _ready_board()
	var lives_before := b.get_lives()
	var game_over_count := {"n": 0}
	b.game_over.connect(func(): game_over_count["n"] += 1)

	b._on_enemy_leaked(1)

	assert_eq(b.get_lives(), lives_before - 1, "lives reduced by the leak")
	assert_eq(game_over_count["n"], 0, "game_over does not fire while lives remain")
	assert_false(b._run_finished, "the run continues")
	b.free()
	return true

# Isolates `<=` from `<` at the game-over boundary: lives landing at
# exactly zero must still end the run.
func test_leak_that_reaches_exactly_zero_lives_emits_game_over_and_clamps_to_zero() -> bool:
	var b := _ready_board()
	b._lives = 1
	var game_over_count := {"n": 0}
	b.game_over.connect(func(): game_over_count["n"] += 1)

	b._on_enemy_leaked(1)  # exactly drains the last life

	assert_eq(b.get_lives(), 0, "lives land at exactly zero, not negative")
	assert_eq(game_over_count["n"], 1, "game_over fires exactly once")
	assert_true(b._run_finished, "the run is marked finished")
	b.free()
	return true

func test_leak_below_zero_clamps_lives_to_zero_not_negative() -> bool:
	var b := _ready_board()
	b._lives = 2
	var game_over_count := {"n": 0}
	b.game_over.connect(func(): game_over_count["n"] += 1)
	var lives_events: Array = []
	b.lives_changed.connect(func(l): lives_events.append(l))

	b._on_enemy_leaked(4)  # would take lives to -2 if not clamped

	assert_eq(b.get_lives(), 0, "lives clamp to zero rather than going negative")
	assert_eq(game_over_count["n"], 1, "game_over still fires exactly once")
	# The clamp must land before lives_changed fires, not after - otherwise
	# this same overdrawing leak broadcasts the pre-clamp negative value
	# (-2) to every listener (e.g. Task 20's HUD) for one frame before the
	# internal state is corrected. Asserting the getter alone can't catch
	# that: it only ever sees the final, already-clamped value.
	assert_eq(lives_events, [0], "lives_changed carries the already-clamped value, never a transient negative one")
	b.free()
	return true

# Isolates `and` from `or` on `_lives <= 0 and not _run_finished`: once the
# run is already finished, a further leak must not re-fire game_over (and
# must not re-run the clamp).
func test_game_over_does_not_fire_twice_for_a_second_leak_after_the_run_is_finished() -> bool:
	var b := _ready_board()
	b._lives = 1
	var game_over_count := {"n": 0}
	b.game_over.connect(func(): game_over_count["n"] += 1)

	b._on_enemy_leaked(1)  # first leak ends the run
	assert_eq(game_over_count["n"], 1, "precondition: game_over fired once")
	assert_eq(b.get_lives(), 0, "precondition: lives sit at exactly zero after the ending leak")

	b._on_enemy_leaked(1)  # a second enemy leaking after the run already ended

	assert_eq(game_over_count["n"], 1, "game_over does not fire a second time once the run is finished")
	# The clamp is unconditional (maxi(0, ...)), not gated on _run_finished,
	# so lives stay floored at zero even for leaks the board no longer
	# reacts to - Enemy nodes already in the tree keep running their own
	# _physics_process and can keep leaking after _run_finished is set,
	# since the board only stops spawning/ticking, it does not freeze or
	# free enemies already spawned.
	assert_eq(b.get_lives(), 0, "lives stay floored at zero, not driven negative, by a leak after the run has ended")
	b.free()
	return true

# --------------------------------------------------------------------------
# Splash / hit resolution
# --------------------------------------------------------------------------

func test_splash_hit_damages_enemies_inside_the_radius_and_spares_ones_outside() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"slime", Vector2(500, 500))
	var inside := _ready_enemy_under(b._enemies_root, &"slime", Vector2(530, 500))   # 30px away
	var outside := _ready_enemy_under(b._enemies_root, &"slime", Vector2(560, 500))  # 60px away
	var health_target: float = target.sim["health"]
	var health_inside: float = inside.sim["health"]
	var health_outside: float = outside.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 40.0)  # radius 40 catches "inside" (30), not "outside" (60)

	assert_true(target.sim["health"] < health_target, "the direct target takes damage")
	assert_true(inside.sim["health"] < health_inside, "an enemy inside the splash radius takes damage")
	assert_eq(outside.sim["health"], health_outside, "an enemy outside the splash radius is untouched")

	target.free(); inside.free(); outside.free(); b.free()
	return true

# Isolates `<=` from `<` on the splash distance check.
func test_splash_hit_includes_an_enemy_at_exactly_the_radius_boundary() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"slime", Vector2(0, 0))
	var at_boundary := _ready_enemy_under(b._enemies_root, &"slime", Vector2(40, 0))  # exactly 40px away
	var health_before: float = at_boundary.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 40.0)  # splash radius equals the distance exactly

	assert_true(at_boundary.sim["health"] < health_before, "an enemy exactly at the splash radius is hit (<=, not <)")
	target.free(); at_boundary.free(); b.free()
	return true

# Isolates `<= 0.0` from `< 0.0` on the "no splash" early return.
func test_zero_splash_radius_does_not_touch_a_co_located_enemy() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"slime", Vector2(200, 200))
	var co_located := _ready_enemy_under(b._enemies_root, &"slime", Vector2(200, 200))  # distance 0
	var health_before: float = co_located.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 0.0)

	assert_eq(co_located.sim["health"], health_before,
		"a splash radius of exactly zero touches nothing but the direct target (<= 0.0, not < 0.0)")
	target.free(); co_located.free(); b.free()
	return true

# Isolates the `enemy == target_node` exclusion: without it the direct
# target, which sits at distance 0 from itself, would take splash damage a
# second time on top of its direct hit.
func test_splash_hit_does_not_double_damage_the_direct_target() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"slime", Vector2(0, 0))
	var health_before: float = target.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 100.0)  # generous radius that trivially covers the target itself

	assert_eq(target.sim["health"], health_before - 1.0,
		"the target takes exactly one hit's worth of damage, not two, despite sitting at distance 0 from itself")
	target.free(); b.free()
	return true

# Isolates the `not enemy is Enemy` guard: a non-Enemy sibling under
# _enemies_root must be skipped rather than crashing take_damage() and
# aborting the rest of the splash resolution for enemies still to come.
func test_splash_hit_skips_non_enemy_children_of_the_enemies_root() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"slime", Vector2(0, 0))
	var decoy := Node2D.new()
	decoy.position = Vector2(5, 0)
	b._enemies_root.add_child(decoy)  # sits between target and neighbor in child order
	var neighbor := _ready_enemy_under(b._enemies_root, &"slime", Vector2(10, 0))
	var neighbor_health_before: float = neighbor.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 50.0)

	assert_true(neighbor.sim["health"] < neighbor_health_before,
		"a real Enemy after a non-Enemy sibling in iteration order still takes splash damage")

	target.free(); decoy.free(); neighbor.free(); b.free()
	return true

# Amendment 3's pin: sim/damage.gd's "not alive" guard makes a hit on an
# already-dying corpse an inert no-op, so a splash that also catches a
# corpse must not pay a second reward - while still reaching a genuinely
# alive neighbour in the same radius.
func test_splash_over_an_already_dying_enemy_pays_no_second_reward() -> bool:
	var b := _ready_board()
	var dying := _ready_enemy_under(b._enemies_root, &"slime", Vector2(0, 0))
	var alive_neighbor := _ready_enemy_under(b._enemies_root, &"slime", Vector2(10, 0))
	dying.died.connect(b._on_enemy_died)  # the same wiring _spawn() performs

	var gold_before := b.get_gold()
	dying.take_damage({"damage": 9999.0})  # a prior, already-resolved lethal hit
	var gold_after_first_kill := b.get_gold()
	assert_true(gold_after_first_kill > gold_before, "precondition: the first kill paid its reward")
	assert_false(dying.sim["alive"], "precondition: the enemy is now dying/not alive")

	var neighbor_health_before: float = alive_neighbor.sim["health"]

	# A second hit lands on the same corpse - e.g. a splash from another
	# projectile already in flight when the first one landed.
	b._on_projectile_hit(dying, {"damage": 5.0}, 20.0)  # radius also covers alive_neighbor

	assert_eq(b.get_gold(), gold_after_first_kill, "no second reward is paid for hitting an already-dying enemy")
	assert_true(alive_neighbor.sim["health"] < neighbor_health_before,
		"the splash still damages a genuinely alive neighbour in range")

	dying.free(); alive_neighbor.free(); b.free()
	return true

# --------------------------------------------------------------------------
# Targeting candidates
# --------------------------------------------------------------------------

func test_physics_process_excludes_dead_or_dying_enemies_but_offers_alive_ones() -> bool:
	var b := _ready_board()
	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"long")  # generous range so distance is never the limiting factor
	b._try_place(tile.x, tile.y)
	var tower: Tower = b._towers_root.get_child(0)
	var world_pos := Grid.tile_to_world_center(tile.x, tile.y)

	var dead := _ready_enemy_under(b._enemies_root, &"slime", world_pos + Vector2(10, 0))
	dead.sim["alive"] = false
	dead.sim["dying"] = true

	var fired := {"n": 0}
	tower.wants_to_fire.connect(func(_a, _b, _c): fired["n"] += 1)
	b._physics_process(0.016)
	assert_eq(fired["n"], 0, "with only a dead/dying enemy nearby, the tower does not fire")

	var alive := _ready_enemy_under(b._enemies_root, &"slime", world_pos + Vector2(10, 0))
	b._physics_process(0.016)
	assert_eq(fired["n"], 1, "once a genuinely alive enemy is nearby, the same tower fires")

	dead.free(); alive.free(); b.free()
	return true

# --------------------------------------------------------------------------
# Projectile spawning
# --------------------------------------------------------------------------

func test_tower_fired_spawns_a_projectile_with_the_towers_speed_and_arc_flag() -> bool:
	var b := _ready_board()
	var tile := _find_buildable_tiles(b, 1)[0]
	b.select_tower_kind(&"mortar")  # arcs=true, a non-default flag a "hardcode false" mutant would miss
	b._try_place(tile.x, tile.y)
	var tower: Tower = b._towers_root.get_child(0)
	var target := _ready_enemy_under(b._enemies_root, &"slime", tower.position + Vector2(10, 0))

	b._on_tower_fired(target, {"damage": 5, "pierce": 0}, 55.0, tower)

	assert_eq(b._projectiles_root.get_child_count(), 1, "one projectile spawned")
	var projectile: Projectile = b._projectiles_root.get_child(0)
	assert_eq(projectile.global_position, tower.global_position, "the projectile starts at the tower's position")
	assert_eq(projectile._speed, float(Towers.DEFS[&"mortar"]["projectile_speed"]), "speed comes from the tower's def")
	assert_true(projectile._arcs, "mortar's projectile_arcs (true) is threaded through, not hardcoded false")
	assert_eq(projectile._splash, 55.0, "splash is threaded through from the fired signal, not re-read from the def")

	target.free(); b.free()
	return true
