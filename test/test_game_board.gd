extends TestCase

# GameBoard is the hub that wires sim to views, so most of these tests read
# and mutate its private state directly (Grid tile scans, _counts,
# _selected_tower, ...) the same way test_enemy.gd and
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
# board-owned field setup() assigns BEFORE that line - kind, price_paid,
# _def, tiers, _stats, position for Tower; kind, sim (fully
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

## First `count` world positions the board will actually accept, found by
## asking the real rule rather than by reimplementing it. Scans tile centres
## in row-major order purely as a convenient sweep of the map; the tiles carry
## no meaning here beyond being evenly spaced sample points. The demo map is
## seeded and deterministic, so this is stable across runs without hardcoding
## coordinates that would silently go stale if the map or its seed changed.
func _find_placeable_positions(b: GameBoard, count: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(b._map_name)))
	var radius := Placement.tower_radius(&"basic")
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			var pos := Grid.tile_to_world_center(c, r)
			var verdict := Placement.can_place(
				pos, radius, b._map_renderer.prop_footprints(), found, b._paths, bounds)
			if verdict["ok"]:
				found.append(pos)
				if found.size() >= count:
					return found
	return found

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

func test_handle_tap_off_grid_is_rejected_as_out_of_bounds() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	var gold_before := b.get_gold()

	# _handle_tap no longer special-cases out-of-bounds via a tile lookup - it
	# routes every tap without a tower hit straight into _try_place(), so an
	# off-map point is caught by Placement.can_place's own bounds check
	# instead of being silently swallowed beforehand.
	b._handle_tap(Vector2(-24, -24))

	assert_eq(rejected["count"], 1, "an off-grid tap is rejected through the same path as any other illegal spot")
	assert_eq(rejected["reason"], "That is off the edge of the map.", "reason names the bounds violation")
	assert_eq(b.get_gold(), gold_before, "no gold spent")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower placed")
	b.free()
	return true

func test_try_place_rejects_a_spot_on_the_road() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var gold_before := b._gold
	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)

	# The first point of the first spawn path is the road itself.
	b._try_place(b._paths[0][0])

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "You cannot build on the road.",
		"the road rule is what fired, not some other check that happens to also reject this point")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower was built on the road")
	assert_eq(b._gold, gold_before, "and no gold was spent")
	b.free()
	return true

# Pins that _try_place actually wires _map_renderer.prop_footprints() into
# Placement.can_place, rather than passing it an empty list. A mutation that
# did the latter would leave this suite green with no other test noticing:
# _find_placeable_positions steers away from props on purpose (see this
# file's own helper), so nothing else in this suite ever lands a tap on one.
func test_try_place_rejects_a_spot_on_a_prop() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var gold_before := b._gold
	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)

	var footprint: Dictionary = b._map_renderer.prop_footprints()[0]
	b._try_place(footprint["pos"])

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "Something is already in the way there.",
		"the prop rule is what fired, not some other check that happens to also reject this point")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower was built on top of the prop")
	assert_eq(b._gold, gold_before, "and no gold was spent")
	b.free()
	return true

# Pins that _try_place actually wires _tower_positions() into
# Placement.can_place, rather than passing it an empty list. A mutation that
# did the latter would leave this suite green with no other test noticing:
# every other placement test either places just one tower or places several
# tests apart with plenty of spacing.
func test_try_place_rejects_a_spot_too_close_to_another_tower() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"basic")
	b._try_place(pos)
	assert_eq(b._towers_root.get_child_count(), 1, "precondition: the first tower was placed")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b.select_tower_kind(&"basic")
	b._try_place(pos + Vector2(30.0, 0.0))  # 30px away, inside the 44px MIN_TOWER_SPACING

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "That is too close to another tower.",
		"the spacing rule is what fired, not some other check that happens to also reject this point")
	assert_eq(b._towers_root.get_child_count(), 1, "the child count stayed at 1 - no second tower snuck in")
	b.free()
	return true

# Isolates `>=` from `>`: exactly at budget, the next placement must be
# rejected; a mutation to `>` would let it through.
func test_try_place_enforces_the_tower_budget_at_the_boundary() -> bool:
	var b := _ready_board()
	b._gold = 1000000
	var budget := int(Maps.get_def(Maps.FIRST)["tower_budget"])
	assert_eq(budget, 16, "precondition: demoMap's tower_budget is 16")
	var positions := _find_placeable_positions(b, budget + 1)
	assert_eq(positions.size(), budget + 1, "precondition: enough placeable positions exist for this test")

	# basic's per-kind limit is 8 and fast's is 8 (8 + 8 = 16), so filling
	# the budget exactly does not also trip the per-kind limit check first.
	for i in budget:
		b.select_tower_kind(&"basic" if i < 8 else &"fast")
		b._try_place(positions[i])
	assert_eq(b._towers_root.get_child_count(), budget, "precondition: exactly `budget` towers placed")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b.select_tower_kind(&"basic")
	b._try_place(positions[budget])

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
	var positions := _find_placeable_positions(b, limit + 1)
	for i in limit:
		# Re-arm each time: a successful placement now consumes the selection.
		b.select_tower_kind(kind)
		b._try_place(positions[i])
	assert_eq(b.get_tower_count(kind), limit, "precondition: exactly the limit placed")

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b.select_tower_kind(kind)
	b._try_place(positions[limit])

	assert_eq(rejected["count"], 1, "the (limit + 1)th placement of the same kind is rejected")
	assert_eq(rejected["reason"], "You cannot build any more of that tower.", "per-kind limit message")
	assert_eq(b.get_tower_count(kind), limit, "count did not exceed the limit")
	b.free()
	return true

func test_try_place_rejects_when_gold_is_insufficient() -> bool:
	var b := _ready_board()
	b._gold = 5  # below basic's base price of 20
	b.select_tower_kind(&"basic")
	var pos := _find_placeable_positions(b, 1)[0]
	var expected_price := EconomySim.tower_price(&"basic", 0)

	var rejected := {"count": 0, "reason": ""}
	b.placement_rejected.connect(func(r): rejected["count"] += 1; rejected["reason"] = r)
	b._try_place(pos)

	assert_eq(rejected["count"], 1, "rejected exactly once")
	assert_eq(rejected["reason"], "Not enough gold — that costs %d." % expected_price,
		"reason includes the exact price the tower would have cost")
	assert_eq(b._towers_root.get_child_count(), 0, "no tower placed")
	assert_eq(b.get_gold(), 5, "gold untouched")
	b.free()
	return true

# --------------------------------------------------------------------------
# Ghost preview
#
# _update_ghost is reachable synchronously without any input dispatch - it is
# called directly here, the same way _handle_tap()/_try_place() are called
# directly elsewhere in this file. The invariant under test is that the
# ghost asks Placement.can_place the same question _try_place asks, so the
# preview can never tell the player a spot is legal when it is not.
# --------------------------------------------------------------------------

func test_update_ghost_at_a_legal_spot_shows_the_green_tint_and_the_range_ring() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")
	var pos := _find_placeable_positions(b, 1)[0]

	b._update_ghost(pos)

	assert_true(b._ghost.visible, "the ghost sprite is shown at a legal spot")
	assert_eq(b._ghost.modulate, Color(0.4, 1.0, 0.4, 0.5), "a legal spot tints the ghost green")
	assert_true(b._ghost_range.visible, "the range ring is shown at a legal spot")
	b.free()
	return true

func test_update_ghost_on_the_road_shows_the_red_tint_and_hides_the_range_ring() -> bool:
	var b := _ready_board()
	b.select_tower_kind(&"basic")

	b._update_ghost(b._paths[0][0])

	assert_eq(b._ghost.modulate, Color(1.0, 0.3, 0.3, 0.5), "an illegal spot tints the ghost red")
	assert_false(b._ghost_range.visible, "the range ring is hidden at an illegal spot - its absence is a second signal")
	b.free()
	return true

func test_update_ghost_with_no_kind_armed_hides_both_the_sprite_and_the_range_ring() -> bool:
	var b := _ready_board()
	assert_eq(b._selected_kind, &"", "precondition: nothing is armed")

	b._update_ghost(_find_placeable_positions(b, 1)[0])

	assert_false(b._ghost.visible, "no kind armed means no ghost to show")
	assert_false(b._ghost_range.visible, "and no range ring either")
	b.free()
	return true

# --------------------------------------------------------------------------
# Successful placement
# --------------------------------------------------------------------------

func test_try_place_success_deducts_gold_and_emits_signals() -> bool:
	var b := _ready_board()
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"fast")
	var gold_before := b.get_gold()
	var expected_price := EconomySim.tower_price(&"fast", 0)

	var gold_events: Array = []
	var placed_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	b.tower_placed.connect(func(k): placed_events.append(k))

	b._try_place(pos)

	assert_eq(b.get_gold(), gold_before - expected_price, "gold reduced by exactly the price")
	assert_eq(gold_events, [b.get_gold()], "gold_changed emitted exactly once with the new total")
	assert_eq(placed_events, [&"fast"], "tower_placed emitted exactly once with the placed kind")
	assert_eq(b.get_tower_count(&"fast"), 1, "per-kind count incremented")
	assert_eq(b._towers_root.get_child_count(), 1, "one tower node added")
	var tower: Tower = b._towers_root.get_child(0)
	assert_eq(tower.kind, &"fast", "the placed tower is the kind that was selected")
	assert_eq(tower.position, pos, "the tower sits exactly where it was placed - its position is the only record")
	b.free()
	return true

func test_placing_a_second_tower_of_a_kind_charges_the_escalated_price() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var positions := _find_placeable_positions(b, 2)
	b.select_tower_kind(&"basic")

	var first_price := EconomySim.tower_price(&"basic", 0)
	var second_price := EconomySim.tower_price(&"basic", 1)
	assert_true(second_price > first_price, "precondition: the second tower costs strictly more than the first")

	b._try_place(positions[0])
	var gold_after_first := b.get_gold()
	# Re-arm: a successful placement now consumes the selection.
	b.select_tower_kind(&"basic")
	b._try_place(positions[1])

	assert_eq(gold_after_first, 1000 - first_price, "the first tower was charged the base price")
	assert_eq(b.get_gold(), gold_after_first - second_price, "the second tower was charged the escalated price, not the base again")
	b.free()
	return true

# --------------------------------------------------------------------------
# Placing consumes the selection
# --------------------------------------------------------------------------

func test_a_successful_placement_clears_the_selected_kind() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"basic")
	assert_eq(b._selected_kind, &"basic", "precondition: the kind is armed")

	b._try_place(pos)

	assert_eq(b._selected_kind, &"", "placing a tower disarms the selected kind")
	b.free()
	return true

# The selection must survive a rejection, or a mis-tap on the road would
# silently disarm you and the next tap would do nothing.
func test_a_rejected_placement_leaves_the_selection_armed() -> bool:
	var b := _ready_board()
	b._gold = 1000
	b.select_tower_kind(&"basic")

	# The first point of the first spawn path is the road itself - guaranteed
	# to be refused regardless of map layout.
	b._try_place(b._paths[0][0])

	assert_eq(b._selected_kind, &"basic", "a rejected placement leaves the kind armed to retry")
	b.free()
	return true

func test_a_rejection_for_insufficient_gold_also_leaves_the_selection_armed() -> bool:
	var b := _ready_board()
	b._gold = 5  # below basic's base price of 20
	b.select_tower_kind(&"basic")
	var pos := _find_placeable_positions(b, 1)[0]

	b._try_place(pos)

	assert_eq(b._selected_kind, &"basic", "an unaffordable placement leaves the kind armed")
	assert_eq(b.get_tower_count(&"basic"), 0, "precondition: nothing was placed")
	b.free()
	return true

# tower_placed must still carry the kind that was placed, even though the
# selection is cleared before it fires — the panel reads that payload.
func test_tower_placed_still_reports_the_kind_despite_the_selection_clearing() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var pos := _find_placeable_positions(b, 1)[0]
	var seen := {"kind": &"unset", "count": 0}
	b.tower_placed.connect(func(k): seen["kind"] = k; seen["count"] += 1)

	b.select_tower_kind(&"mortar")
	b._try_place(pos)

	assert_eq(seen["count"], 1, "tower_placed fired exactly once")
	assert_eq(seen["kind"], &"mortar", "tower_placed carries the placed kind, not the cleared empty selection")
	b.free()
	return true

# --------------------------------------------------------------------------
# Selection / selling
# --------------------------------------------------------------------------

func test_select_tower_kind_deselects_the_currently_selected_tower() -> bool:
	var b := _ready_board()
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"basic")
	b._try_place(pos)
	b._handle_tap(pos)
	assert_true(b._selected_tower != null, "precondition: a tower is selected")

	b.select_tower_kind(&"fast")

	assert_eq(b._selected_tower, null, "picking a different kind to build clears the current tower selection")
	b.free()
	return true

func test_handle_tap_with_no_kind_selected_deselects_and_does_not_place() -> bool:
	var b := _ready_board()
	var positions := _find_placeable_positions(b, 2)
	b.select_tower_kind(&"basic")
	b._try_place(positions[0])
	b._handle_tap(positions[0])  # select it
	assert_true(b._selected_tower != null, "precondition: a tower is selected")

	b._selected_kind = &""
	b._handle_tap(positions[1])  # a different, empty placeable spot

	assert_eq(b._selected_tower, null, "tapping empty ground with nothing selected clears the tower selection")
	assert_eq(b._towers_root.get_child_count(), 1, "no new tower was placed")
	b.free()
	return true

func test_sell_selected_tower_refunds_decrements_and_deselects() -> bool:
	var b := _ready_board()
	b._gold = 1000
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"long")
	b._try_place(pos)
	var tower: Tower = b._towers_root.get_child(0)
	var price_paid := EconomySim.tower_price(&"long", 0)
	var gold_after_placement := b.get_gold()

	b._handle_tap(pos)  # taps the tower's own position -> selects it
	assert_eq(b._selected_tower, tower, "precondition: the placed tower is selected")

	var gold_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	var expected_refund := EconomySim.sell_refund(price_paid)

	b.sell_selected_tower()

	assert_eq(b.get_gold(), gold_after_placement + expected_refund, "gold increased by exactly the refund")
	assert_eq(gold_events, [b.get_gold()], "gold_changed emitted exactly once")
	assert_eq(b.get_tower_count(&"long"), 0, "per-kind count decremented")
	# queue_free() defers the actual removal to end-of-frame, which this
	# synchronous harness never reaches (see this file's header note), so
	# get_child_count() would still read 1 here. is_queued_for_deletion() is
	# the synchronously observable proof that freeing the node is the whole
	# removal now - _towers_root is the only registry.
	assert_true(tower.is_queued_for_deletion(), "the tower node is freed on sell")
	assert_eq(b._selected_tower, null, "selling deselects")
	b.free()
	return true

func test_get_tower_count_starts_zero_rises_on_placement_falls_on_sell_and_is_zero_for_unknown_kinds() -> bool:
	var b := _ready_board()
	for kind in Towers.KINDS:
		assert_eq(b.get_tower_count(kind), 0, "%s starts at zero" % kind)
	assert_eq(b.get_tower_count(&"not_a_real_kind"), 0, "an unknown kind returns 0 rather than erroring")

	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"mortar")
	b._try_place(pos)
	assert_eq(b.get_tower_count(&"mortar"), 1, "count rises on placement")

	b._handle_tap(pos)
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
	b.start_next_wave()  # wave 1: 5 goblins at at_ms 0, 500, 1000, 1500, 2000
	# One queue per path; demoMap has a single entrance, so queue 0 is the wave.
	assert_eq(b._spawn_queues[0][0]["at_ms"], 0.0, "precondition: the first goblin spawns at t=0")
	assert_eq(b._spawn_queues[0][1]["at_ms"], 500.0, "precondition: the second goblin spawns at t=500")

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
	b._spawn_queues = [[{"kind": &"goblin", "at_ms": 0.0}]]
	b._wave_clock = 0.0
	b._spawned_per_path = [0]

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
	b._spawn_queues = [[{"kind": &"bat", "at_ms": 0.0}]]
	b._wave_clock = 0.0
	b._spawned_per_path = [0]
	b._physics_process(0.0)  # spawns the bat and wires its died/leaked signals to the board
	var enemy: Enemy = b._enemies_root.get_child(0)

	var lives_events: Array = []
	b.lives_changed.connect(func(l): lives_events.append(l))
	var lives_before := b.get_lives()

	var expected_loss := Leak.resolve(
		{"life_loss": Enemies.DEFS[&"bat"]["life_loss"], "health": enemy.sim["health"]}, b.get_wave())
	enemy.leaked.emit(expected_loss)

	assert_eq(b.get_lives(), lives_before - expected_loss, "lives dropped by exactly the value the leaked signal carried")
	assert_eq(lives_events, [b.get_lives()], "lives_changed fired exactly once")
	b.free()
	return true

func test_enemy_died_signal_adds_its_reward_to_gold() -> bool:
	var b := _ready_board()
	b.start_next_wave()
	b._spawn_queues = [[{"kind": &"ogre", "at_ms": 0.0}]]
	b._wave_clock = 0.0
	b._spawned_per_path = [0]
	b._physics_process(0.0)  # spawns the ogre and wires its died/leaked signals to the board
	var enemy: Enemy = b._enemies_root.get_child(0)

	var gold_events: Array = []
	b.gold_changed.connect(func(g): gold_events.append(g))
	var died_events: Array = []
	enemy.died.connect(func(r, k): died_events.append([r, k]))
	var gold_before := b.get_gold()
	var reward := int(Enemies.DEFS[&"ogre"]["reward"])

	enemy.died.emit(reward, &"ogre")

	assert_eq(b.get_gold(), gold_before + reward, "gold increased by exactly the enemy's reward")
	assert_eq(gold_events, [b.get_gold()], "gold_changed fired exactly once")
	assert_eq(died_events, [[reward, &"ogre"]],
		"died carries both the reward and the kind unchanged to every listener, including the board's own _on_enemy_died")
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
	var target := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(500, 500))
	var inside := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(530, 500))   # 30px away
	var outside := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(560, 500))  # 60px away
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
	var target := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(0, 0))
	var at_boundary := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(40, 0))  # exactly 40px away
	var health_before: float = at_boundary.sim["health"]

	b._on_projectile_hit(target, {"damage": 1.0}, 40.0)  # splash radius equals the distance exactly

	assert_true(at_boundary.sim["health"] < health_before, "an enemy exactly at the splash radius is hit (<=, not <)")
	target.free(); at_boundary.free(); b.free()
	return true

# Isolates `<= 0.0` from `< 0.0` on the "no splash" early return.
func test_zero_splash_radius_does_not_touch_a_co_located_enemy() -> bool:
	var b := _ready_board()
	var target := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(200, 200))
	var co_located := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(200, 200))  # distance 0
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
	var target := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(0, 0))
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
	var target := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(0, 0))
	var decoy := Node2D.new()
	decoy.position = Vector2(5, 0)
	b._enemies_root.add_child(decoy)  # sits between target and neighbor in child order
	var neighbor := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(10, 0))
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
	var dying := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(0, 0))
	var alive_neighbor := _ready_enemy_under(b._enemies_root, &"goblin", Vector2(10, 0))
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
	var world_pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"long")  # generous range so distance is never the limiting factor
	b._try_place(world_pos)
	var tower: Tower = b._towers_root.get_child(0)

	var dead := _ready_enemy_under(b._enemies_root, &"goblin", world_pos + Vector2(10, 0))
	dead.sim["alive"] = false
	dead.sim["dying"] = true

	var fired := {"n": 0}
	tower.wants_to_fire.connect(func(_a, _b, _c): fired["n"] += 1)
	b._physics_process(0.016)
	assert_eq(fired["n"], 0, "with only a dead/dying enemy nearby, the tower does not fire")

	var alive := _ready_enemy_under(b._enemies_root, &"goblin", world_pos + Vector2(10, 0))
	b._physics_process(0.016)
	assert_eq(fired["n"], 1, "once a genuinely alive enemy is nearby, the same tower fires")

	dead.free(); alive.free(); b.free()
	return true

# --------------------------------------------------------------------------
# Projectile spawning
# --------------------------------------------------------------------------

func test_tower_fired_spawns_a_projectile_with_the_towers_speed_and_arc_flag() -> bool:
	var b := _ready_board()
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(&"mortar")  # arcs=true, a non-default flag a "hardcode false" mutant would miss
	b._try_place(pos)
	var tower: Tower = b._towers_root.get_child(0)
	var target := _ready_enemy_under(b._enemies_root, &"goblin", tower.position + Vector2(10, 0))

	b._on_tower_fired(target, {"damage": 5, "pierce": 0}, 55.0, tower)

	assert_eq(b._projectiles_root.get_child_count(), 1, "one projectile spawned")
	var projectile: Projectile = b._projectiles_root.get_child(0)
	assert_eq(projectile.global_position, tower.global_position, "the projectile starts at the tower's position")
	assert_eq(projectile._speed, float(Towers.DEFS[&"mortar"]["projectile_speed"]), "speed comes from the tower's def")
	assert_true(projectile._arcs, "mortar's projectile_arcs (true) is threaded through, not hardcoded false")
	assert_eq(projectile._splash, 55.0, "splash is threaded through from the fired signal, not re-read from the def")

	target.free(); b.free()
	return true

# --------------------------------------------------------------------------
# upgrades
#
# The board is where an upgrade is paid for, so these tests care about the
# gate and the gold as much as the tier. The rules themselves belong to
# sim/upgrades.gd and are pinned there; what is pinned here is that the board
# actually consults them instead of trusting its caller.
# --------------------------------------------------------------------------

func _place_and_select(b: GameBoard, kind: StringName) -> Tower:
	b._gold = 5000
	var pos := _find_placeable_positions(b, 1)[0]
	b.select_tower_kind(kind)
	b._try_place(pos)
	b._handle_tap(pos)
	return b._selected_tower

func test_upgrade_selected_tower_advances_the_branch_and_charges_for_it() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var gold_before := b.get_gold()

	b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 1, "the branch advanced")
	assert_eq(b.get_gold(), gold_before - 30, "and the tier's cost was deducted")
	b.free()
	return true

func test_upgrade_selected_tower_announces_the_new_gold() -> bool:
	var b := _ready_board()
	_place_and_select(b, &"basic")
	var events: Array = []
	b.gold_changed.connect(func(g): events.append(g))

	b.upgrade_selected_tower(&"sustained")

	assert_eq(events, [b.get_gold()], "gold_changed emitted exactly once, carrying the new total")
	b.free()
	return true

func test_upgrade_selected_tower_is_a_no_op_with_nothing_selected() -> bool:
	var b := _ready_board()
	b._gold = 5000
	var gold_before := b.get_gold()

	b.upgrade_selected_tower(&"sustained")

	assert_eq(b.get_gold(), gold_before, "no selection means no purchase")
	b.free()
	return true

func test_upgrade_selected_tower_refuses_when_gold_is_short() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	b._gold = 5

	b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 0, "the branch did not advance")
	assert_eq(b.get_gold(), 5, "and nothing was spent")
	assert_eq(tower.price_paid, EconomySim.tower_price(&"basic", 0),
		"nor was anything recorded against the tower")
	b.free()
	return true

# The cross-path rule has to be enforced at the purchase point, not only in
# the UI - a board method that trusts its caller is one bug away from a tower
# with both branches maxed.
func test_upgrade_selected_tower_enforces_the_cross_path_rule() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var gold_before := b.get_gold()
	for i in 3:
		b.upgrade_selected_tower(&"burst")
	assert_eq(tower.tiers[&"burst"], 3, "precondition: burst is committed")

	for i in 3:
		b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 2,
		"sustained stopped at the cross-path cap despite ample gold")
	assert_eq(b.get_gold(), gold_before - (30 + 65 + 145) - (30 + 60),
		"and the refused tier cost nothing - only the five legal ones were charged")
	b.free()
	return true

# A maxed branch is the other way can_upgrade says no, and the one a player
# reaches by clicking the same button once too often.
func test_upgrade_selected_tower_refuses_past_the_top_tier() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	for i in 4:
		b.upgrade_selected_tower(&"burst")
	assert_eq(tower.tiers[&"burst"], UpgradesSim.MAX_TIER, "precondition: the branch is maxed")
	var gold_before := b.get_gold()

	b.upgrade_selected_tower(&"burst")

	assert_eq(tower.tiers[&"burst"], UpgradesSim.MAX_TIER, "a fifth buy adds nothing")
	assert_eq(b.get_gold(), gold_before, "and costs nothing")
	b.free()
	return true

func test_upgrade_selected_tower_emits_tower_upgraded() -> bool:
	var b := _ready_board()
	_place_and_select(b, &"basic")
	var seen: Array = []
	b.tower_upgraded.connect(func(branch): seen.append(branch))

	b.upgrade_selected_tower(&"sustained")

	assert_eq(seen.size(), 1, "one signal per purchase")
	assert_eq(seen[0], &"sustained", "carrying the branch bought")
	b.free()
	return true

# A refusal must be silent on tower_upgraded, or the inspector redraws a tier
# the player did not get.
func test_upgrade_selected_tower_emits_nothing_when_it_refuses() -> bool:
	var b := _ready_board()
	_place_and_select(b, &"basic")
	b._gold = 5
	var seen: Array = []
	b.tower_upgraded.connect(func(branch): seen.append(branch))

	b.upgrade_selected_tower(&"sustained")

	assert_eq(seen.size(), 0, "no purchase, no signal")
	b.free()
	return true

func test_upgrade_selected_tower_reports_why_it_refused() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var messages: Array = []
	b.placement_rejected.connect(func(text): messages.append(text))

	b._gold = 5
	b.upgrade_selected_tower(&"sustained")
	assert_eq(messages.size(), 1, "the player is told why")
	assert_true(String(messages[0]).contains("30"),
		"a refusal for gold names the price, so the two reasons cannot be swapped: %s" % messages[0])

	b._gold = 5000
	for i in 3:
		b.upgrade_selected_tower(&"burst")
	for i in 3:
		b.upgrade_selected_tower(&"sustained")
	assert_eq(messages.size(), 2, "and once more when the cross-path rule refuses")
	assert_false(String(messages[1]).contains("gold"),
		"a locked branch is not a gold problem: %s" % messages[1])
	assert_eq(tower.tiers[&"sustained"], 2, "precondition: it really was the cross-path refusal")
	b.free()
	return true

func test_selling_an_upgraded_tower_refunds_half_of_everything_sunk_in() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	b.upgrade_selected_tower(&"sustained")   # 30
	b.upgrade_selected_tower(&"sustained")   # 60
	var invested := tower.price_paid
	assert_eq(invested, EconomySim.tower_price(&"basic", 0) + 30 + 60,
		"precondition: price_paid carries placement plus both tiers")
	var gold_before := b.get_gold()

	b.sell_selected_tower()

	assert_eq(b.get_gold(), gold_before + EconomySim.sell_refund(invested),
		"refund covers placement and upgrades together")
	b.free()
	return true

# --------------------------------------------------------------------------
# priority
# --------------------------------------------------------------------------

func test_cycling_priority_advances_the_selected_tower() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var before := tower.get_priority()
	b.cycle_selected_tower_priority()
	assert_eq(tower.get_priority(), Targeting.next_priority(before),
		"the board advances the tower one step through the cycle")
	b.free()
	return true

func test_cycling_priority_with_nothing_selected_is_a_no_op() -> bool:
	# The inspector is hidden with no selection, but the board must not crash
	# if the call arrives anyway - every other board mutator guards this.
	var b := _ready_board()
	b.cycle_selected_tower_priority()
	assert_eq(b.get_gold(), Maps.get_def(Maps.FIRST)["starting_gold"],
		"a fresh board with nothing selected was left untouched")
	b.free()
	return true

# --------------------------------------------------------------------------
# Wave-clear payout (spec 2026-08-24-slice-0-design.md section 4)
# --------------------------------------------------------------------------

func test_clearing_a_wave_pays_the_base_bonus() -> bool:
	var board := _ready_board()
	var before := board.get_gold()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(board.get_last_wave_reward()["base"], 25, "wave 1 base bonus is 20 + 1*5")
	assert_true(board.get_gold() > before, "and the gold actually landed")
	board.free()
	return true

func test_clearing_a_wave_pays_interest_on_the_bank() -> bool:
	var board := _ready_board()
	board.set_gold_for_test(200)
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(board.get_last_wave_reward()["interest"], 10, "5% of 200")
	board.free()
	return true

func test_a_thin_bank_earns_no_interest() -> bool:
	var board := _ready_board()
	board.set_gold_for_test(10)
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(board.get_last_wave_reward()["interest"], 0, "below the minimum balance")
	board.free()
	return true

# Interest is computed on the bank BEFORE the clear bonus is added, or the
# player earns interest on money they were paid in the same instant.
func test_interest_is_taken_on_the_bank_before_the_clear_bonus_lands() -> bool:
	var board := _ready_board()
	board.set_gold_for_test(200)
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(board.get_last_wave_reward()["interest"], 10,
		"5% of the 200 held going in, not of 200 plus the bonus")
	board.free()
	return true

func test_the_wave_reward_signal_carries_all_three_parts() -> bool:
	var board := _ready_board()
	board.set_gold_for_test(200)
	var seen := []
	board.wave_reward.connect(func(b, s, i): seen.append([b, s, i]))
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(seen.size(), 1, "emitted exactly once")
	assert_eq(seen[0][0], 25, "base")
	assert_eq(seen[0][2], 10, "interest")
	board.free()
	return true

# --------------------------------------------------------------------------
# The prep timer (spec section 4.5)
# --------------------------------------------------------------------------

# The clock does NOT run before wave 1. A countdown on an empty board, with
# 100 gold and no information, is hostile to a new player, and the payout is
# meaningless when there is nothing yet to spend it on.
func test_no_prep_timer_before_the_first_wave() -> bool:
	var board := _ready_board()
	assert_false(board.is_prepping(), "a fresh board is not counting down")
	board.free()
	return true

func test_clearing_a_wave_starts_the_prep_timer() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_true(board.is_prepping(), "the clock runs between waves")
	assert_almost_eq(board.get_prep_remaining_ms(), 20000.0, 0.001, "a full window")
	board.free()
	return true

func test_the_prep_timer_counts_down() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	board._physics_process(1.0)
	assert_almost_eq(board.get_prep_remaining_ms(), 19000.0, 0.001, "a second gone")
	board.free()
	return true

func test_the_prep_timer_starts_the_next_wave_on_its_own() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_eq(board.get_wave(), 1, "still on wave 1 while prepping")
	board._physics_process(21.0)
	assert_eq(board.get_wave(), 2, "the timer started the next wave")
	assert_false(board.is_prepping(), "and the clock stopped")
	board.free()
	return true

func test_calling_early_pays_for_the_time_given_up() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	var before := board.get_gold()
	board._physics_process(10.0)
	board.start_next_wave()
	assert_eq(board.get_gold() - before, 30, "10 seconds left * 3 gold")
	board.free()
	return true

func test_letting_the_clock_expire_pays_no_call_early_bonus() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	var before := board.get_gold()
	board._physics_process(21.0)
	assert_eq(board.get_gold(), before, "the timer's own start earns nothing")
	board.free()
	return true

# Winning must not arm the clock. _on_wave_cleared sets _run_finished and
# emits victory BEFORE arming, or a won run starts a twenty-first wave.
func test_clearing_the_final_wave_does_not_start_a_prep_timer() -> bool:
	var board := _ready_board()
	board.set_wave_for_test(Waves.MAX_WAVES)
	board.force_wave_cleared_for_test()
	assert_false(board.is_prepping(), "a won run is not counting down to wave 21")
	board.free()
	return true

func test_losing_stops_the_prep_timer() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	assert_true(board.is_prepping(), "prepping before the loss")
	board.force_game_over_for_test()
	board._physics_process(1.0)
	assert_false(board.is_prepping(), "a lost run is not counting down")
	board.free()
	return true

# Calling early must CLEAR the clock, not merely pay for it.
#
# Found by mutation testing, and by nothing else: deleting the reset in
# start_next_wave left every other test green. The damage is not a double
# spawn - start_next_wave's own _wave_active guard stops that - it is that
# the countdown keeps running underneath the live wave, so is_prepping()
# stays true and the HUD counts down during a fight.
func test_calling_early_clears_the_clock_rather_than_only_paying_for_it() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	board.force_wave_cleared_for_test()
	board._physics_process(10.0)
	board.start_next_wave()
	assert_false(board.is_prepping(), "the countdown stopped when the wave started")
	assert_almost_eq(board.get_prep_remaining_ms(), 0.0, 0.001, "and the clock is at zero")
	board.free()
	return true

func test_selling_a_tower_announces_the_kind() -> bool:
	var board := _ready_board()
	var seen := []
	board.tower_sold.connect(func(kind): seen.append(kind))
	board.select_tower_kind(&"basic")
	board._try_place(_find_placeable_positions(board, 1)[0])
	board._select_tower(board._towers_root.get_child(0))
	board.sell_selected_tower()
	assert_eq(seen, [&"basic"], "the sale named the kind that was sold")
	board.free()
	return true

# --------------------------------------------------------------------------
# Multi-spawn (spec section 6.2)
# --------------------------------------------------------------------------

## Like _ready_board, but on a named map rather than Maps.FIRST.
func _ready_board_for_map(map_name: StringName) -> GameBoard:
	var b := _instantiate_board()
	b.set_map_for_test(map_name)
	b.notification(Node.NOTIFICATION_READY)
	return b

# The full wave composition runs down EVERY path, not divided between them.
# Ported faithfully from upstream, which computes totalEnemies * paths.length.
# That is what makes The Fork harder than The Pass at the same wave number,
# and why it opens with 250 gold rather than 100.
func test_a_two_path_map_spawns_the_whole_wave_down_each_path() -> bool:
	var one := _ready_board_for_map(&"demoMap")
	var two := _ready_board_for_map(&"map2")
	one.start_next_wave()
	two.start_next_wave()
	for i in 600:
		one._physics_process(0.05)
		two._physics_process(0.05)
	assert_true(one.get_spawned_count() > 0, "precondition: the one-path map spawned at all")
	assert_eq(two.get_spawned_count(), one.get_spawned_count() * 2,
		"two entrances field twice the wave")
	one.free()
	two.free()
	return true

func test_enemies_enter_from_both_entrances() -> bool:
	var board := _ready_board_for_map(&"map2")
	board.start_next_wave()
	for i in 60:
		board._physics_process(0.05)
	var starts := {}
	for child in board._enemies_root.get_children():
		starts[child.position] = true
	assert_true(starts.size() >= 2,
		"enemies entered from more than one place on the board")
	board.free()
	return true

func test_a_one_path_map_is_unchanged_by_the_per_path_queues() -> bool:
	var board := _ready_board_for_map(&"demoMap")
	board.start_next_wave()
	for i in 600:
		board._physics_process(0.05)
	assert_eq(board.get_spawned_count(), Waves.build_schedule(1).size(),
		"one path issues exactly one schedule, as it always did")
	board.free()
	return true

# _all_spawns_issued must check EVERY queue, not just the first.
#
# Today's two paths always finish together - identical schedules, one clock -
# so a queue-0-only check passes the whole suite. Mutation testing showed
# exactly that. This test stages queues of different lengths directly, which
# is the only way to tell the two implementations apart, and it matters the
# moment anything gives one entrance a different composition from another.
func test_the_wave_does_not_clear_while_any_path_still_has_spawns_pending() -> bool:
	var b := _ready_board_for_map(&"map2")
	b.start_next_wave()
	# Path 0 is finished; path 1 still has one enemy to send.
	b._spawn_queues = [
		[{"kind": &"goblin", "at_ms": 0.0}],
		[{"kind": &"goblin", "at_ms": 0.0}, {"kind": &"goblin", "at_ms": 999999.0}],
	]
	b._spawned_per_path = [1, 1]
	assert_false(b._all_spawns_issued(),
		"path 1 has an enemy left, so the wave is not done issuing")
	b._spawned_per_path = [1, 2]
	assert_true(b._all_spawns_issued(), "and it is once every path has finished")
	b.free()
	return true

# --------------------------------------------------------------------------
# Per-map base resolution (spec section 6.3)
# --------------------------------------------------------------------------

func test_the_content_size_is_the_map_plus_the_panel() -> bool:
	var size := GameBoard.required_content_size(&"demoMap")
	assert_eq(size.x, 1104 + GameBoard.PANEL_WIDTH, "map width plus the build panel")
	assert_eq(size.y, 672, "and the map's own height")
	return true

func test_larger_maps_ask_for_a_larger_content_size() -> bool:
	var pass_size := GameBoard.required_content_size(&"demoMap")
	var fork := GameBoard.required_content_size(&"map2")
	var coils := GameBoard.required_content_size(&"map3")
	assert_true(fork.y > pass_size.y, "The Fork is taller than the design box")
	assert_true(coils.x > pass_size.x, "The Coils is wider")
	return true

# The whole point of resizing the base viewport rather than adding a camera:
# a tower's world position stays a map-pixel position, so every placement,
# targeting and splash calculation is untouched by which map is loaded.
func test_world_space_still_equals_map_pixel_space_on_a_large_map() -> bool:
	var board := _ready_board_for_map(&"map3")
	board.select_tower_kind(&"basic")
	var spot := _find_placeable_positions(board, 1)[0]
	board._try_place(spot)
	assert_eq(board._towers_root.get_child_count(), 1, "the tower was placed")
	assert_eq(board._towers_root.get_child(0).position, spot,
		"at exactly the world coordinate asked for, on a map larger than the viewport")
	board.free()
	return true

# Every map must fit its own declared pixel size, or the panel overlaps the
# board on one of them.
func test_every_map_asks_for_room_for_its_own_pixels() -> bool:
	for name in Maps.DEFS:
		var px := Maps.pixel_size(name)
		var need := GameBoard.required_content_size(name)
		assert_eq(need.y, px.y, "%s height is the map's own" % name)
		assert_true(need.x > px.x, "%s leaves room for the panel" % name)
	return true

# --------------------------------------------------------------------------
# The board runs the shaman aura (spec 2026-08-25 section 5)
# --------------------------------------------------------------------------
#
# The harness has its own witness for this. The board needs one too: three
# times now a rule has been wired into one runner and not the other with the
# suite staying green, and "the board runs it" is exactly the half that a
# pure-module test cannot see.
func test_the_board_grants_shield_charges_around_a_shaman() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	var shaman := _spawn_enemy_at(board, &"shaman", Vector2(300, 300))
	var goblin := _spawn_enemy_at(board, &"goblin", Vector2(320, 300))
	assert_eq(int(goblin.sim["shield"]), 0, "precondition: goblins carry no shield")
	# The aura fires on its beat, which _wave_clock reaches on the first tick.
	board._physics_process(0.0)
	assert_eq(int(goblin.sim["shield"]), 1, "the escort was shielded")
	assert_true(int(shaman.sim["shield"]) <= 1,
		"and the shaman did not top itself up beyond its own table value")
	board.free()
	return true

func test_the_board_leaves_a_distant_enemy_unshielded() -> bool:
	var board := _ready_board()
	board.start_next_wave()
	_spawn_enemy_at(board, &"shaman", Vector2(100, 100))
	var far := _spawn_enemy_at(board, &"goblin", Vector2(100 + Aura.RADIUS + 40.0, 100))
	board._physics_process(0.0)
	assert_eq(int(far.sim["shield"]), 0, "out of range, no charge")
	board.free()
	return true

## Puts a live enemy of a kind at a position, bypassing the spawn schedule.
func _spawn_enemy_at(board: GameBoard, kind: StringName, at: Vector2) -> Enemy:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	e.notification(Node.NOTIFICATION_READY)
	board._enemies_root.add_child(e)
	e.setup(kind, PackedVector2Array([at, at + Vector2(1, 0)]), 1)
	e.position = at
	return e

# --------------------------------------------------------------------------
# The board spawns bosses (spec 2026-08-25 section 6)
# --------------------------------------------------------------------------
#
# The harness has its own boss coverage. This is the board half - the fourth
# time in this slice a rule needed wiring into two runners, and the three
# before it all shipped green with only one side done.

func test_the_board_spawns_a_boss_on_wave_ten() -> bool:
	var board := _ready_board()
	board.set_wave_for_test(9)
	board.start_next_wave()
	# Long enough for the whole schedule, boss included, to have been issued.
	for i in 2000:
		board._physics_process(0.05)
	var bosses := 0
	for child in board._enemies_root.get_children():
		if child is Enemy and child.is_boss:
			bosses += 1
	assert_eq(board.get_wave(), 10, "precondition: on wave 10")
	assert_eq(bosses + _bosses_already_dead(board, 10), 1,
		"exactly one boss was issued")
	board.free()
	return true

## The boss may already have leaked by the time the schedule finishes, so
## count what the schedule promised rather than only what is still standing.
func _bosses_already_dead(board: GameBoard, wave: int) -> int:
	var still_alive := 0
	for child in board._enemies_root.get_children():
		if child is Enemy and child.is_boss:
			still_alive += 1
	return (1 if Bosses.has_boss(wave) else 0) - still_alive

func test_a_boss_carries_its_own_numbers_not_its_kinds() -> bool:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	e.notification(Node.NOTIFICATION_READY)
	e.setup(&"troll", PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), 20)
	var definition := Bosses.on_wave(20)
	e.make_boss(definition)
	assert_true(e.is_boss, "flagged as a boss")
	assert_eq(float(e.sim["health"]), float(definition["health"]), "its own health")
	assert_eq(float(e.sim["speed"]), float(definition["speed"]), "its own speed")
	assert_eq(int(e.sim["armor"]), int(definition["armor"]), "its own armour")
	assert_eq(e.boss_reward, int(definition["reward"]), "and its own bounty")
	e.free()
	return true

# make_boss lands its RULES state before it touches the sprite, matching
# Tower.setup and Enemy.setup. A board-instantiated node aborts at the first
# unresolved @onready in this harness, and a boss whose health never landed
# would be an ordinary troll wearing a boss's name.
func test_make_boss_lands_its_stats_even_when_the_sprite_half_aborts() -> bool:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	# Deliberately NOT notified, so @onready fields stay unresolved.
	e.setup(&"troll", PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), 20)
	e.make_boss(Bosses.on_wave(20))
	assert_true(e.is_boss, "the flag landed")
	assert_eq(float(e.sim["health"]), float(Bosses.on_wave(20)["health"]),
		"and so did the health, before the sprite work could abort")
	e.free()
	return true

func test_a_boss_pays_its_own_bounty() -> bool:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	e.notification(Node.NOTIFICATION_READY)
	e.setup(&"troll", PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), 20)
	e.make_boss(Bosses.on_wave(20))
	var paid := []
	e.died.connect(func(reward, _kind): paid.append(reward))
	e.take_damage({"damage": 99999.0, "pierce": 999})
	assert_eq(paid.size(), 1, "it died")
	assert_true(int(paid[0]) > int(Enemies.DEFS[&"troll"]["reward"]) / 2,
		"and paid a bounty in the boss's league, not a rank-and-file reward")
	e.free()
	return true
