extends TestCase

# Projectile's only @onready field (_dot) only resolves on
# NOTIFICATION_READY, which add_child() does NOT deliver in this harness -
# see test_enemy.gd and test_tower.gd for the same, verified pattern.
func _ready_projectile() -> Projectile:
	var p: Projectile = load("res://game/projectile.tscn").instantiate()
	p.notification(Node.NOTIFICATION_READY)
	return p

func _target_at(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = pos
	return n

# --------------------------------------------------------------------------
# launch()
# --------------------------------------------------------------------------

func test_launch_records_origin_and_total_distance() -> bool:
	var p := _ready_projectile()
	p.global_position = Vector2(5, 5)
	var target := _target_at(Vector2(105, 5))

	p.launch(target, {"damage": 4}, 200.0, false, 0.0)

	assert_eq(p._origin, Vector2(5, 5), "origin captured at launch, from global_position")
	assert_eq(p._total_distance, 100.0, "total distance is the straight-line distance to the target at launch")
	assert_true(p._launched, "the launched guard is set once launch() has run")

	p.free()
	target.free()
	return true

func test_launch_floors_total_distance_at_one_when_target_starts_on_the_projectile() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2.ZERO)  # same position as the projectile (also (0,0))
	p.launch(target, {}, 200.0, false, 0.0)
	assert_eq(p._total_distance, 1.0, "maxf(1.0, ...) floors a zero distance instead of leaving 0")
	p.free()
	target.free()
	return true

# --------------------------------------------------------------------------
# _physics_process before launch (amendment 3's defect fix)
# --------------------------------------------------------------------------

# Before launch() runs, _target is null. Without the _launched guard,
# is_instance_valid(null) is false and the projectile would silently free
# itself the moment a stray tick landed between add_child() and launch() -
# same class of bug, and same silent-failure reason, as Enemy's
# sim.is_empty() guard.
func test_physics_process_before_launch_is_a_safe_no_op() -> bool:
	var p := _ready_projectile()
	var start := p.global_position
	p._physics_process(0.016)
	assert_eq(p.global_position, start, "an un-launched projectile does not move")
	assert_false(p.is_queued_for_deletion(), "an un-launched projectile is not freed, even though _target is null")
	p.free()
	return true

# --------------------------------------------------------------------------
# movement
# --------------------------------------------------------------------------

func test_physics_process_moves_speed_times_delta_toward_the_target() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(1000, 0))
	p.launch(target, {}, 100.0, false, 0.0)

	p._physics_process(0.1)  # step = 100 * 0.1 = 10

	assert_eq(p.global_position, Vector2(10, 0), "moved exactly speed * delta toward the target")
	assert_false(p.is_queued_for_deletion(), "far from the target - no hit yet")

	p.free()
	target.free()
	return true

# --------------------------------------------------------------------------
# hit - HIT_RADIUS branch, exact boundary (amendment 6 names the <= as a
# mutation target; these two tests bracket it on both sides)
# --------------------------------------------------------------------------

func test_hit_fires_at_exactly_hit_radius_even_with_a_small_step() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(Projectile.HIT_RADIUS, 0))  # distance == HIT_RADIUS exactly
	p.launch(target, {"damage": 5}, 1.0, false, 12.5)  # step = 1, well under HIT_RADIUS(6)

	var captured := {"count": 0, "target": null, "source": {}, "splash": -1.0}
	p.hit.connect(func(tn, src, sp):
		captured["count"] += 1
		captured["target"] = tn
		captured["source"] = src
		captured["splash"] = sp)

	p._physics_process(1.0)

	assert_eq(captured["count"], 1, "hit fires exactly once when distance == HIT_RADIUS (<=, not <)")
	assert_true(captured["target"] == target, "hit carries the target node")
	assert_eq(captured["source"], {"damage": 5}, "hit carries the source dict unchanged")
	assert_eq(captured["splash"], 12.5, "hit carries the splash radius launch() was given")
	assert_true(p.is_queued_for_deletion(), "the projectile frees itself after a hit")

	p.free()
	target.free()
	return true

func test_no_hit_one_unit_beyond_hit_radius_with_a_step_that_also_falls_short() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(Projectile.HIT_RADIUS + 1.0, 0))
	p.launch(target, {}, 1.0, false, 0.0)  # step 1: distance 7 clears neither threshold

	var count := {"n": 0}
	p.hit.connect(func(_a, _b, _c): count["n"] += 1)
	p._physics_process(1.0)

	assert_eq(count["n"], 0, "one unit beyond HIT_RADIUS, with a step that doesn't reach it either: no hit")
	assert_false(p.is_queued_for_deletion(), "not freed")

	p.free()
	target.free()
	return true

# --------------------------------------------------------------------------
# hit - step-overshoot branch, isolated from the HIT_RADIUS branch (distance
# is well beyond HIT_RADIUS in both tests below, so only the step condition
# can be responsible for a hit)
# --------------------------------------------------------------------------

func test_hit_fires_when_step_exactly_covers_a_distance_beyond_hit_radius() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(50, 0))  # distance 50, well beyond HIT_RADIUS(6)
	p.launch(target, {}, 50.0, false, 0.0)  # speed 50, delta 1 -> step == distance exactly

	var count := {"n": 0}
	p.hit.connect(func(_a, _b, _c): count["n"] += 1)
	p._physics_process(1.0)

	assert_eq(count["n"], 1, "step == remaining distance triggers a hit via <=, isolated from the HIT_RADIUS branch")
	assert_true(p.is_queued_for_deletion(), "frees itself")

	p.free()
	target.free()
	return true

func test_no_hit_when_step_falls_one_unit_short_of_a_distance_beyond_hit_radius() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(50, 0))
	p.launch(target, {}, 49.0, false, 0.0)  # step 49, one short of distance 50

	var count := {"n": 0}
	p.hit.connect(func(_a, _b, _c): count["n"] += 1)
	p._physics_process(1.0)

	assert_eq(count["n"], 0, "step one short of the distance does not trigger a hit")
	assert_false(p.is_queued_for_deletion(), "not freed")

	p.free()
	target.free()
	return true

# --------------------------------------------------------------------------
# target becomes invalid mid-flight
# --------------------------------------------------------------------------

func test_physics_process_frees_itself_when_the_target_becomes_invalid() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(1000, 0))
	p.launch(target, {}, 100.0, false, 0.0)
	target.free()  # simulate the enemy being freed elsewhere before the next tick

	var count := {"n": 0}
	p.hit.connect(func(_a, _b, _c): count["n"] += 1)
	p._physics_process(0.1)

	assert_eq(count["n"], 0, "no hit is emitted for an invalid target")
	assert_true(p.is_queued_for_deletion(), "the projectile frees itself instead of erroring on a dangling target")

	p.free()
	return true

# --------------------------------------------------------------------------
# arc offset (amendment 2's defect fix: offset from a captured centred base,
# not a raw assignment that destroys the ColorRect's -3,-3 centring)
# --------------------------------------------------------------------------

func test_arc_offset_at_t_zero_matches_a_non_arcing_dot() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(400, 0))
	p.launch(target, {}, 100.0, true, 55.0)

	# t == 0: right after launch, before any tick has moved the projectile.
	assert_eq(p._dot.position, p._dot_base, "at t==0 the dot sits at its centred base position, same as a non-arcing dot")

	p.free()
	target.free()
	return true

func test_arc_offset_at_t_half_differs_by_exactly_arc_height() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(400, 0))  # total_distance 400
	p.launch(target, {}, 100.0, true, 55.0)

	p._physics_process(2.0)  # step 200 -> travelled 200 -> t = 200/400 = 0.5

	assert_almost_eq(p._dot.position.y, p._dot_base.y - Projectile.ARC_HEIGHT, 0.001,
		"at t==0.5 the dot is offset upward by exactly ARC_HEIGHT")
	assert_eq(p._dot.position.x, p._dot_base.x, "the arc only ever offsets y, never x")

	p.free()
	target.free()
	return true

# t == 1 is not reachable through a single tick against a stationary target:
# the tick that would complete the journey always lands inside the hit
# branch first (remaining distance <= step, or <= HIT_RADIUS), before the
# arc code even runs - the hit check runs on the position from BEFORE this
# tick's move. It is reachable in a real game when the target is a live,
# moving Enemy: the projectile can still be short of total_distance-from-
# origin while the enemy has walked far enough that the *current* remaining
# distance is nowhere near a hit. Simulated directly here without a
# multi-tick chase: teleport the projectile to one unit short of
# total_distance and move the target further down the same line, so a
# single small step both avoids the hit branch and lands travelled exactly
# on total_distance.
func test_arc_offset_at_t_one_matches_a_non_arcing_dot() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(1000, 0))  # total_distance fixed at 1000 by launch()
	p.launch(target, {}, 1.0, true, 55.0)

	p.global_position = Vector2(999, 0)  # simulates 999 of 1000 already travelled
	target.global_position = Vector2(2000, 0)  # target has since moved further away -
	                                             # remaining distance stays well above
	                                             # both hit thresholds
	p._physics_process(1.0)  # step = 1 * 1 = 1, lands travelled exactly on total_distance

	assert_eq(p.global_position, Vector2(1000, 0), "precondition: travelled landed exactly on total_distance")
	assert_almost_eq(p._dot.position.y, p._dot_base.y, 0.001,
		"at t==1 sin(PI) collapses back to ~0, matching a non-arcing dot")

	p.free()
	target.free()
	return true

func test_non_arcing_projectile_never_moves_its_dot() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(400, 0))
	p.launch(target, {}, 100.0, false, 0.0)  # arcs = false

	p._physics_process(2.0)  # same step as the t==0.5 arcing test above

	assert_eq(p._dot.position, p._dot_base, "a non-arcing projectile's dot stays at its centred base position")

	p.free()
	target.free()
	return true

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------

func test_arc_height_and_hit_radius_constants_match_the_brief() -> bool:
	assert_eq(Projectile.ARC_HEIGHT, 28.0, "ARC_HEIGHT")
	assert_eq(Projectile.HIT_RADIUS, 6.0, "HIT_RADIUS")
	return true

func test_each_tower_kind_maps_to_its_own_projectile_sprite() -> bool:
	for kind in Towers.KINDS:
		var expected := "res://assets/art/projectiles/%s.png" % kind
		assert_eq(Projectile.texture_path_for(kind), expected,
			"%s uses its themed projectile" % kind)
		assert_true(ResourceLoader.exists(expected), "%s projectile asset exists" % kind)
	return true

func test_launch_applies_the_firing_towers_projectile_sprite() -> bool:
	var p := _ready_projectile()
	var target := _target_at(Vector2(100, 0))
	p.launch(target, {}, 100.0, false, 0.0, &"mortar")
	assert_eq(p._dot.texture.resource_path, "res://assets/art/projectiles/mortar.png",
		"launch selects the mortar shell rather than a generic dot")
	p.free()
	target.free()
	return true
