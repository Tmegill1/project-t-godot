extends TestCase

# Enemy's @onready fields (_sprite, _health_bar) only resolve once the node
# receives NOTIFICATION_READY. In a normal running game that happens the
# instant add_child() places a node under a live tree. It does NOT happen
# here: this harness runs its entire suite inside run_tests.gd's synchronous
# SceneTree._initialize() and quits before the engine ever processes a frame,
# so the tree's own root reports is_inside_tree() == false throughout the run
# (verified directly: adding an Enemy under Engine.get_main_loop().root and
# checking is_inside_tree()/onready state afterward shows nothing resolved).
# add_child() alone is therefore not sufficient here, matching neither engine
# guarantee nor the intuition "add it to the tree so @onready resolves"
# suggests. Sending NOTIFICATION_READY directly is the documented, public
# way to fire a node's ready-time initialization on demand, and it resolves
# @onready deterministically without ever touching the scene tree or an
# await. Confirmed empirically before writing any test below.
func _ready_enemy() -> Enemy:
	var e: Enemy = load("res://game/enemy.tscn").instantiate()
	e.notification(Node.NOTIFICATION_READY)
	return e

## The same enemy _ready_enemy builds, set up with a seeded Rng so the variant
## it picks is pinned rather than incidental.
func _ready_enemy_with_seed(seed_value: int) -> Enemy:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1, Rng.new(seed_value))
	return e

func _straight_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])

# --------------------------------------------------------------------------
# setup()
# --------------------------------------------------------------------------

func test_setup_populates_sim_with_scaled_health_and_speed_for_slime_at_wave_one() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)

	var modifiers := Waves.get_modifiers(1)
	var expected_health := float(Enemies.scaled_health(&"slime", modifiers["health_modifier"]))
	var expected_speed := Enemies.scaled_speed(&"slime", modifiers["speed_modifier"])

	assert_eq(e.sim["health"], expected_health, "health scaled via Enemies.scaled_health for the given wave")
	assert_eq(e.sim["max_health"], expected_health, "max_health mirrors starting health")
	assert_eq(e.sim["speed"], expected_speed, "speed scaled via Enemies.scaled_speed for the given wave")
	assert_eq(e.sim["alive"], true, "starts alive")
	assert_eq(e.sim["dying"], false, "starts not dying")
	assert_eq(e.sim["id"], e.get_instance_id(), "sim id is the node's own instance id")

	e.free()
	return true

# A later wave and a different kind together prove setup() actually threads
# both the kind argument and the wave argument through to Enemies/Waves,
# rather than e.g. always scaling as if for wave 1 or always as slime.
func test_setup_scales_health_and_speed_for_ogre_at_a_later_wave() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 10)

	var modifiers := Waves.get_modifiers(10)
	assert_true(modifiers["health_modifier"] > 1.0, "precondition: wave 10 is past the last authored wave, so modifiers are not 1.0")
	var expected_health := float(Enemies.scaled_health(&"ogre", modifiers["health_modifier"]))
	var expected_speed := Enemies.scaled_speed(&"ogre", modifiers["speed_modifier"])

	assert_eq(e.sim["health"], expected_health, "ogre health at wave 10 uses the ogre base and the wave-10 modifier")
	assert_eq(e.sim["speed"], expected_speed, "ogre speed at wave 10 uses the ogre base and the wave-10 modifier")
	assert_true(expected_health != float(Enemies.scaled_health(&"slime", modifiers["health_modifier"])),
		"precondition: ogre and slime scale to different health values, so a kind mix-up would be caught")

	e.free()
	return true

func test_setup_sets_position_kind_and_starting_path_index() -> bool:
	var e := _ready_enemy()
	# Deliberately not starting at the origin: Vector2.ZERO would silently
	# agree with a mutant that hardcodes the spawn position instead of
	# reading path[0] - confirmed by actually running that mutation against
	# a straight path starting at (0, 0) before switching to this one.
	var path := PackedVector2Array([Vector2(40, 25), Vector2(100, 0), Vector2(100, 100)])
	e.setup(&"bee", path, 1)

	assert_eq(e.kind, &"bee", "kind is stored")
	assert_eq(e.position, path[0], "enemy spawns at the first path point")
	assert_eq(e.sim["path_index"], Movement.starting_path_index(path[0], path),
		"path_index comes from Movement.starting_path_index, not a hardcoded 0 or 1")

	e.free()
	return true

# --------------------------------------------------------------------------
# _physics_process
# --------------------------------------------------------------------------

# Amendment 2's guard: sim starts as {} and a tick landing before setup()
# must not crash. Calling _physics_process directly on a freshly
# instantiated, never-setup enemy is exactly that scenario.
func test_physics_process_before_setup_is_a_safe_no_op() -> bool:
	var e := _ready_enemy()
	e._physics_process(0.016)
	assert_true(e.sim.is_empty(), "sim is still {} - the guard returned before touching it")
	e.free()
	return true

func test_physics_process_advances_position_toward_the_first_waypoint() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	assert_eq(e.sim["path_index"], 1, "precondition: spawning on path[0] skips straight to heading for path[1]")

	e._physics_process(0.1)  # 0.1s -> 100ms; speed 100px/s -> 10px moved
	assert_eq(e.position, Vector2(10, 0), "100px/s for 100ms (delta * 1000.0) moves 10px toward path[1]")
	assert_eq(e.sim["path_index"], 1, "still short of the waypoint")
	assert_eq(e.sim["alive"], true, "not at the goal yet")

	e.free()
	return true

# Mutation target: `if not sim["alive"] or sim["dying"]:`. _die() only ever
# produces dying == true alongside alive == false, so on the class's own
# code paths "or" and a mutated "and" agree. Setting the flags to a
# combination _die() itself would never produce (dying true, alive still
# true) isolates the "dying" half of the guard on its own: a correct "or"
# still skips (dying is true), while a mutated "and" would require *both*
# halves to demand a skip and would wrongly let the tick through.
func test_physics_process_skips_processing_while_dying_even_if_alive_flag_is_stale() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e.sim["dying"] = true
	var position_before := e.position
	var sim_before := e.sim.duplicate()

	e._physics_process(1.0)

	assert_eq(e.position, position_before, "a dying enemy does not move, even with a stale alive flag")
	assert_eq(e.sim, sim_before, "a dying enemy's sim state is untouched by the tick")

	e.free()
	return true

# Movement.advance's documented quirk: a tick that arrives at a waypoint
# consumes the whole tick and covers no real distance, so the moving_left it
# reports comes from the sub-pixel delta toward the waypoint just reached,
# not the direction travel actually continues in afterward. Engineered so
# that stale reading (rightward, toward path[1]) disagrees with the facing
# already established (leftward, as real prior travel would have set it) -
# if the `not result["advanced_waypoint"]` guard in _physics_process were
# dropped, this tick would flip the sprite back to match the stale reading.
func test_physics_process_does_not_flip_the_sprite_on_a_waypoint_arrival_tick() -> bool:
	var e := _ready_enemy()
	# Spawns on path[0]; path[1] sits 1px away, inside
	# Movement.WAYPOINT_ARRIVAL_RADIUS (2.0), so the very first tick arrives
	# without moving - and reads as moving right (dx = 1 > 0), even though
	# the path immediately continues sharply left afterward.
	var path := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(-100, 0)])
	e.setup(&"slime", path, 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	e.set_facing_from_travel(true)  # establishes "facing left", as ongoing travel would
	assert_true(sprite.flip_h, "precondition: facing left before the arrival tick")

	e._physics_process(0.016)

	assert_eq(e.sim["path_index"], 2, "the waypoint was still consumed")
	assert_true(sprite.flip_h,
		"the arrival tick's own stale (rightward) reading did not overwrite the established facing")

	e.free()
	return true

func test_physics_process_reaching_the_goal_emits_leaked_with_the_resolved_value_and_marks_dead() -> bool:
	var e := _ready_enemy()
	var single_point_path := PackedVector2Array([Vector2(0, 0)])
	# Bee at wave 6 (past Leak.LIFE_LOSS_SCALING_WAVE = 5) puts Leak.resolve on
	# its health-based branch with an uncapped result (health 3, life_loss 2 -
	# neither hits MAX_LIFE_LOSS_PER_LEAK = 4). That makes this scenario
	# sensitive to the two dict fields passed to Leak.resolve being swapped:
	# an ogre-at-wave-3 scenario tried first had both fields individually
	# exceed the cap, so a life_loss/health swap was invisible (both routes
	# saturated to the same capped value of 4) - confirmed by actually
	# running that mutation before settling on this scenario.
	e.setup(&"bee", single_point_path, 6)
	var starting_health: float = e.sim["health"]

	# GDScript lambdas capture locals by value, not by reference, so a plain
	# local var written from inside the callback would never be visible out
	# here - a Dictionary is a reference type, so mutating its contents (not
	# reassigning the variable) does propagate. Verified empirically.
	var captured := {"count": 0, "value": -1}
	e.leaked.connect(func(v): captured["count"] += 1; captured["value"] = v)

	e._physics_process(0.016)

	var expected: int = Leak.resolve(
		{"life_loss": Enemies.DEFS[&"bee"]["life_loss"], "health": starting_health}, 6)
	assert_true(expected < Leak.MAX_LIFE_LOSS_PER_LEAK, "precondition: this scenario's result is not cap-saturated")
	assert_eq(captured["count"], 1, "leaked fires exactly once")
	assert_eq(captured["value"], expected, "leaked carries whatever Leak.resolve computes for this enemy/wave")
	assert_eq(e.sim["alive"], false, "reaching the goal marks the enemy not-alive")

	e.free()
	return true

# --------------------------------------------------------------------------
# take_damage
# --------------------------------------------------------------------------

func test_take_damage_reduces_health_and_updates_health_bar() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)  # health 5

	var r1 := e.take_damage({"damage": 2.0})
	assert_eq(r1["remaining_health"], 3.0, "5 - 2 = 3")
	assert_eq(e.sim["health"], 3.0, "sim reflects the returned remaining_health")
	assert_almost_eq(e._health_bar.size.x, 32.0 * (3.0 / 5.0), 0.001, "health bar width tracks the new fraction")
	assert_false(r1["lethal"], "not lethal yet")

	e.free()
	return true

func test_take_damage_emits_died_exactly_once_on_the_lethal_hit_and_not_before() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)  # health 5, reward 5

	var captured := {"count": 0, "reward": -1, "kind": &""}
	e.died.connect(func(v, k): captured["count"] += 1; captured["reward"] = v; captured["kind"] = k)

	e.take_damage({"damage": 2.0})  # 5 -> 3
	assert_eq(captured["count"], 0, "died has not fired after a non-lethal hit")
	e.take_damage({"damage": 2.0})  # 3 -> 1
	assert_eq(captured["count"], 0, "still not fired one point of health above zero")

	var lethal := e.take_damage({"damage": 2.0})  # 1 -> 0, lethal
	assert_true(lethal["lethal"], "the resolve result reports lethal")
	assert_eq(captured["count"], 1, "died fired exactly once on the lethal hit")
	assert_eq(captured["reward"], int(Enemies.DEFS[&"slime"]["reward"]), "died carries the enemy's reward")
	assert_eq(captured["kind"], &"slime", "died carries the enemy's own kind, not a fixed/default value")
	assert_eq(e.sim["dying"], true, "sim marks dying")
	assert_eq(e.sim["alive"], false, "sim marks not alive")
	assert_false(e._health_bar.visible, "health bar is hidden once dying")

	# A further hit on a corpse must not pay the reward again.
	e.take_damage({"damage": 2.0})
	assert_eq(captured["count"], 1, "died does not fire again for a hit on an already-dying enemy")

	e.free()
	return true

# --------------------------------------------------------------------------
# variant selection, sizing, facing
# --------------------------------------------------------------------------

func test_an_enemy_draws_one_of_its_kind_s_variants() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	assert_true(sprite.texture != null, "a variant was chosen")
	assert_true(sprite.texture.resource_path.contains("/art/enemies/slime/"),
		"and it came from this kind's art directory")
	e.free()
	return true

func test_the_variant_choice_is_reproducible_from_the_seed() -> bool:
	# Runs must stay reproducible - the whole harness depends on it.
	var a := _ready_enemy_with_seed(1234)
	var b := _ready_enemy_with_seed(1234)
	assert_eq(a.get_node("Sprite").texture.resource_path,
		b.get_node("Sprite").texture.resource_path,
		"the same seed picks the same variant")
	a.free()
	b.free()
	return true

func test_different_seeds_reach_more_than_one_variant() -> bool:
	# Otherwise "pick a variant" could be a constant and every test above
	# would still pass.
	var seen := {}
	for s in 40:
		var e := _ready_enemy_with_seed(s + 1)
		seen[e.get_node("Sprite").texture.resource_path] = true
		e.free()
	assert_true(seen.size() > 1, "%d distinct variants over 40 seeds" % seen.size())
	return true

func test_an_enemy_is_drawn_at_its_kind_s_declared_height() -> bool:
	# The scale is derived from the chosen variant rather than fixed, because
	# the variants are not a uniform size - a fixed factor would draw the same
	# kind at a different size from one spawn to the next.
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _straight_path(), 1)
		var sprite: Sprite2D = e.get_node("Sprite")
		var drawn := float(sprite.texture.get_height()) * sprite.scale.y
		assert_almost_eq(drawn, float(Enemies.DEFS[kind]["sprite_px"]), 0.01,
			"%s draws at its declared height" % kind)
		assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001,
			"%s is scaled uniformly, not stretched" % kind)
		e.free()
	return true

func test_every_variant_of_a_kind_draws_at_the_same_height() -> bool:
	# The defect a fixed scale factor would leave: same kind, different size.
	for kind in Enemies.KINDS:
		for i in Enemies.variant_count(kind):
			var e := _ready_enemy()
			e.setup(kind, _straight_path(), 1)
			var sprite: Sprite2D = e.get_node("Sprite")
			sprite.texture = load("res://assets/art/enemies/%s/variant_%d.png" % [kind, i])
			e.apply_sprite_height()
			var drawn := float(sprite.texture.get_height()) * sprite.scale.y
			assert_almost_eq(drawn, float(Enemies.DEFS[kind]["sprite_px"]), 0.01,
				"%s variant %d draws at the declared height" % [kind, i])
			e.free()
	return true

func test_an_enemy_faces_the_way_it_travels() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	e.set_facing_from_travel(true)
	var left := sprite.flip_h
	e.set_facing_from_travel(false)
	assert_true(sprite.flip_h != left, "travelling the other way flips the sprite")
	e.free()
	return true

func test_the_declared_variant_count_matches_what_was_baked() -> bool:
	# The count is hand-written in data/enemies.gd while the bake decides the
	# real number. A count that is too high makes the spawn pick a file that
	# does not exist - a crash on a path only a live wave reaches.
	for kind in Enemies.KINDS:
		var on_disk := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/variant_%d.png" % [kind, on_disk]):
			on_disk += 1
		assert_eq(Enemies.variant_count(kind), on_disk,
			"%s declares %d variants and %d are baked"
				% [kind, Enemies.variant_count(kind), on_disk])
	return true

# --------------------------------------------------------------------------
# death: a tween replaces the death animation
# --------------------------------------------------------------------------

func test_death_despawns_after_the_tween_rather_than_an_animation() -> bool:
	assert_true(Enemy.DEATH_TWEEN_MS > 0.0, "the death tween has a duration")
	assert_true(Enemy.DEATH_TWEEN_MS < 1000.0,
		"and it is short enough not to hold a kill on screen")
	return true

func test_a_lethal_hit_off_the_tree_still_pays_and_hides_the_bar() -> bool:
	# Every enemy this suite builds is outside the scene tree (see this file's
	# header), and create_tween() requires one. _die must reach everything the
	# sim observes before it gives up on the presentation.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var captured := {"count": 0}
	e.died.connect(func(_v, _k): captured["count"] += 1)
	e.take_damage({"damage": 999.0})
	assert_eq(captured["count"], 1, "died fired on the lethal hit")
	assert_true(e.sim["dying"], "the enemy is marked dying")
	assert_false(e.sim["alive"], "and no longer alive")
	assert_false(e._health_bar.visible, "the health bar is hidden")
	e.free()
	return true

# --------------------------------------------------------------------------
# health bar fraction/colour
# --------------------------------------------------------------------------

func test_health_bar_fraction_and_color_at_full_half_and_zero_health() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)

	e.sim["health"] = 10.0
	e.sim["max_health"] = 10.0
	e._update_health_bar()
	assert_almost_eq(e._health_bar.size.x, 32.0, 0.001, "full health is a full-width bar")
	assert_almost_eq(e._health_bar.color.r, 0.0, 0.001, "full health is green (r=0)")
	assert_almost_eq(e._health_bar.color.g, 1.0, 0.001, "full health is green (g=1)")

	e.sim["health"] = 5.0
	e._update_health_bar()
	assert_almost_eq(e._health_bar.size.x, 16.0, 0.001, "half health is a half-width bar")
	assert_almost_eq(e._health_bar.color.r, 0.5, 0.001, "half health is halfway to red (r=0.5)")
	assert_almost_eq(e._health_bar.color.g, 0.5, 0.001, "half health is halfway from green (g=0.5)")

	e.sim["health"] = 0.0
	e._update_health_bar()
	assert_almost_eq(e._health_bar.size.x, 0.0, 0.001, "zero health is a zero-width bar")
	assert_almost_eq(e._health_bar.color.r, 1.0, 0.001, "zero health is red (r=1)")
	assert_almost_eq(e._health_bar.color.g, 0.0, 0.001, "zero health is red (g=0)")

	e.free()
	return true

# _update_health_bar's fraction is clamped: reachable in practice because
# nothing stops a caller (including a future one) from writing a sim state
# where health exceeds max_health or has gone negative, and the clamp is
# what keeps the bar from over- or under-drawing in that case.
func test_health_bar_fraction_clamps_outside_zero_to_one() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)

	e.sim["health"] = 15.0
	e.sim["max_health"] = 10.0
	e._update_health_bar()
	assert_almost_eq(e._health_bar.size.x, 32.0, 0.001, "health above max_health clamps the fraction to 1.0")
	assert_almost_eq(e._health_bar.color.g, 1.0, 0.001, "clamped fraction 1.0 is still pure green")

	e.sim["health"] = -5.0
	e._update_health_bar()
	assert_almost_eq(e._health_bar.size.x, 0.0, 0.001, "negative health clamps the fraction to 0.0")
	assert_almost_eq(e._health_bar.color.r, 1.0, 0.001, "clamped fraction 0.0 is still pure red")

	e.free()
	return true

# --------------------------------------------------------------------------
# to_candidate / get_sim_state
# --------------------------------------------------------------------------

func test_to_candidate_returns_documented_keys_with_node_pointing_at_the_enemy() -> bool:
	var e := _ready_enemy()
	e.setup(&"bee", _straight_path(), 1)
	e.take_damage({"damage": 1.0})
	e._physics_process(0.05)

	var candidate := e.to_candidate()
	assert_eq(candidate.keys().size(), 7, "exactly the documented keys, no more, no fewer")
	assert_eq(candidate["id"], e.sim["id"], "id matches sim")
	assert_eq(candidate["position"], e.position, "position matches the node's live position")
	assert_eq(candidate["health"], e.sim["health"], "health matches sim")
	assert_eq(candidate["path_index"], e.sim["path_index"], "path_index matches sim")
	assert_eq(candidate["alive"], e.sim["alive"], "alive matches sim")
	assert_eq(candidate["dying"], e.sim["dying"], "dying matches sim")
	assert_true(candidate["node"] == e, "node points at this exact enemy instance")

	e.free()
	return true

func test_get_sim_state_returns_the_live_sim_dictionary() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e.take_damage({"damage": 1.0})

	assert_eq(e.get_sim_state(), e.sim, "get_sim_state reflects the current sim contents")
	assert_eq(e.get_sim_state()["health"], 4.0, "reflects a mutation (the earlier hit), not a stale snapshot")

	e.free()
	return true

# --------------------------------------------------------------------------
# slow and gold
#
# Both arrive on the source dictionary a tower emits with its shot, and both
# reach every enemy a splash catches, not only the one aimed at - the
# reference's Projectile.applyTo does the same for its splash victims.
# --------------------------------------------------------------------------

func test_setup_starts_the_enemy_unslowed() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	assert_almost_eq(e.sim["slow"]["factor"], 1.0, 0.0001, "no slow to begin with")
	assert_almost_eq(e.sim["slow"]["remaining_ms"], 0.0, 0.0001, "and no clock running")
	assert_almost_eq(e.current_speed(), float(e.sim["speed"]), 0.0001, "so it moves at its full speed")
	e.free()
	return true

func test_taking_a_hit_from_a_slowing_source_slows_the_enemy() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	assert_almost_eq(e.current_speed(), full * 0.5, 0.0001, "moving at half speed")
	e.free()
	return true

# The slow lands on a hit that did no damage at all. Being hit is what chills
# the target, not being hurt by it - the reference says so at the same seam.
func test_a_slow_lands_even_when_the_hit_does_no_damage() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var health_before: float = e.sim["health"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	assert_almost_eq(e.sim["health"], health_before, 0.0001, "precondition: the hit did nothing to its health")
	assert_almost_eq(e.sim["slow"]["factor"], 0.5, 0.0001, "and it is slowed regardless")
	e.free()
	return true

func test_a_stronger_slow_replaces_a_weaker_one() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.7, "slow_duration_ms": 1500.0})
	e.take_damage({"damage": 0.0, "slow_factor": 0.45, "slow_duration_ms": 2500.0})
	assert_almost_eq(e.current_speed(), full * 0.45, 0.0001, "the deeper slow won")
	e.take_damage({"damage": 0.0, "slow_factor": 0.7, "slow_duration_ms": 1500.0})
	assert_almost_eq(e.current_speed(), full * 0.45, 0.0001, "and a weaker one after it does not undo it")
	e.free()
	return true

func test_a_hit_with_no_slow_leaves_a_running_slow_alone() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e.take_damage({"damage": 0.0})
	assert_almost_eq(e.current_speed(), full * 0.5, 0.0001, "a tower that cannot slow cannot cure one either")
	e.free()
	return true

func test_a_slow_expires_after_its_duration() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e.tick_slow(1000.0)
	assert_almost_eq(e.current_speed(), full, 0.0001, "back to full speed")
	e.free()
	return true

# The mechanic only exists if the movement step actually reads it. Slime moves
# 10px in 100ms unslowed (test_physics_process_advances_position_toward_the_
# first_waypoint pins that); half speed must cover half the ground.
func test_physics_process_moves_a_slowed_enemy_at_the_slowed_speed() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e._physics_process(0.1)
	assert_almost_eq(e.position.x, 5.0, 0.001, "5px, not the unslowed 10px")
	e.free()
	return true

# And the clock has to run down as the enemy moves, or a slow would be
# permanent.
func test_physics_process_counts_the_slow_down() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 100.0})
	e._physics_process(0.05)
	assert_almost_eq(e.sim["slow"]["remaining_ms"], 50.0, 0.001, "50ms of the 100 spent")
	e._physics_process(0.05)
	assert_almost_eq(e.current_speed(), float(e.sim["speed"]), 0.0001, "and the slow lapsed on the tick that used it up")
	e.free()
	return true

# died() carries (reward, kind) - both arguments. The handler below takes both
# deliberately; a one-argument lambda would fail to connect and this test would
# abort rather than fail.
func test_a_lethal_hit_pays_the_sources_gold_effects() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var rewards: Array = []
	e.died.connect(func(reward, _kind): rewards.append(reward))

	e.take_damage({"damage": 9999.0, "gold_multiplier": 2.0, "bonus_gold_per_kill": 1})

	var base := int(Enemies.DEFS[e.kind]["reward"])
	assert_eq(rewards.size(), 1, "one death, one payout")
	assert_eq(rewards[0], EconomySim.kill_reward(base, {"gold_multiplier": 2.0, "bonus_gold_per_kill": 1}),
		"the killing tower's gold effects applied")
	assert_eq(rewards[0], 11, "5 * 2 + 1, resolved not guessed")
	assert_true(rewards[0] > base, "and it is more than the plain reward")
	e.free()
	return true

func test_a_lethal_hit_from_a_plain_source_pays_the_base_reward() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var rewards: Array = []
	e.died.connect(func(reward, _kind): rewards.append(reward))

	e.take_damage({"damage": 9999.0})

	assert_eq(rewards[0], int(Enemies.DEFS[e.kind]["reward"]),
		"a source with no gold effects still pays exactly the table's reward")
	e.free()
	return true

# The kind still travels with the reward - the board plays a per-kind death
# sound off it.
func test_a_lethal_hit_still_reports_which_kind_died() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 1)
	var kinds: Array = []
	e.died.connect(func(_reward, kind): kinds.append(kind))

	e.take_damage({"damage": 9999.0, "gold_multiplier": 2.0})

	assert_eq(kinds, [&"ogre"], "died carries both arguments, not just the reward")
	e.free()
	return true

# A tower with no slow effect must not slow anything. The default the source
# is read with has to be 1.0 - "no slow" - and this is what says so.
func test_a_hit_with_no_slow_effect_leaves_the_enemy_at_full_speed() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e.take_damage({"damage": 1.0})
	assert_almost_eq(e.current_speed(), float(e.sim["speed"]), 0.0001, "still at full speed")
	assert_almost_eq(e.sim["slow"]["remaining_ms"], 0.0, 0.0001, "and no timer was started")
	e.free()
	return true

# A tower that cannot slow must leave no residue for the next slow to inherit.
# Nothing else would notice one: a factor with no duration on it is inert by
# itself (Slow.effective_speed gates on the timer), and it only surfaces when
# a real slow lands beside it and the strongest-wins rule reads the leftover.
# Reading slow_factor with a default of anything below 1.0 produces exactly
# that, which is why this test exists rather than an assertion on the default.
func test_a_plain_hit_leaves_no_residue_for_a_later_slow_to_inherit() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 1.0})
	e.take_damage({"damage": 0.0, "slow_factor": 0.7, "slow_duration_ms": 1500.0})
	assert_almost_eq(e.current_speed(), full * 0.7, 0.0001,
		"the weak slow is exactly as weak as it should be")
	e.free()
	return true

# --------------------------------------------------------------------------
# run cycle: stride phase, squash and stretch, lean
#
# Replaces the old timed bob (_bob_clock ticking at a fixed BOB_HZ regardless
# of the enemy's own speed). These tests pin that the cycle is driven by
# distance travelled instead - the thing that actually makes a slow enemy
# look slow and a fast enemy look fast, and that makes a stopped enemy stop.
# --------------------------------------------------------------------------

func test_the_stride_advances_with_distance_not_with_time() -> bool:
	# The whole point. A slow enemy and a fast one must not cycle at the same
	# rate, or neither looks like it is moving under its own power.
	var slow := _ready_enemy()
	slow.setup(&"ogre", _straight_path(), 1)
	var fast := _ready_enemy()
	fast.setup(&"bee", _straight_path(), 1)
	assert_true(Enemies.DEFS[&"bee"]["base_speed"] > Enemies.DEFS[&"ogre"]["base_speed"],
		"precondition: the bat is faster than the ogre")

	for i in 10:
		slow._physics_process(0.05)
		fast._physics_process(0.05)

	assert_true(fast.stride_phase() > slow.stride_phase(),
		"over the same elapsed time the faster enemy is further through its stride (%f vs %f)"
			% [fast.stride_phase(), slow.stride_phase()])
	slow.free()
	fast.free()
	return true

func test_a_stationary_enemy_does_not_cycle() -> bool:
	# A timed cycle keeps running when the enemy is held up. A travelled one
	# cannot.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e._physics_process(0.05)
	var moving := e.stride_phase()
	assert_true(moving > 0.0, "precondition: it cycled while it was moving")

	e.sim["speed"] = 0.0
	for i in 10:
		e._physics_process(0.05)
	assert_almost_eq(e.stride_phase(), moving, 0.0001,
		"a stopped enemy holds its phase instead of running on the spot")
	e.free()
	return true

func test_a_slowed_enemy_cycles_more_slowly() -> bool:
	var normal := _ready_enemy()
	normal.setup(&"slime", _straight_path(), 1)
	var slowed := _ready_enemy()
	slowed.setup(&"slime", _straight_path(), 1)
	slowed.sim["slow"] = Slow.apply(Slow.none(), 0.5, 5000.0)

	for i in 8:
		normal._physics_process(0.05)
		slowed._physics_process(0.05)

	assert_true(slowed.stride_phase() < normal.stride_phase(),
		"a slowed enemy is less far through its stride (%f vs %f)"
			% [slowed.stride_phase(), normal.stride_phase()])
	normal.free()
	slowed.free()
	return true

func test_the_stride_squashes_and_stretches_the_sprite() -> bool:
	# A rigid sprite moved up and down still reads as a cut-out. The
	# compression at footfall is what makes it read as weight.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	var seen_squashed := false
	var seen_neutral := false
	var base := sprite.scale.y
	for i in 40:
		e._physics_process(0.02)
		if sprite.scale.y < base * 0.995:
			seen_squashed = true
		if absf(sprite.scale.y - base) < base * 0.005:
			seen_neutral = true
		assert_true(sprite.scale.y <= base + 0.0001,
			"the stride never stretches past the sprite's declared height")
	assert_true(seen_squashed, "the sprite compresses somewhere in the stride")
	assert_true(seen_neutral, "and returns to its declared height somewhere in it")
	e.free()
	return true

func test_the_stride_leans_the_sprite_into_its_travel() -> bool:
	# Spec section 6 asked for this and the art swap dropped it without ruling
	# on it.
	#
	# A manual set_facing_from_travel() call ahead of a tick does NOT
	# exercise this: _physics_process re-derives facing from the REAL travel
	# direction on every tick that does not arrive at a waypoint (see
	# test_physics_process_does_not_flip_the_sprite_on_a_waypoint_arrival_tick
	# above), so a manual override is clobbered on the very next tick before
	# _apply_stride ever reads it - confirmed by running the straight-path,
	# manual-override version of this test and watching the second assertion
	# fail because the tick silently put facing back the way it was. A path
	# that genuinely turns the enemy around is what actually exercises the
	# lean's sign. Sampling across many ticks (rather than pinning two exact
	# ones) keeps the test from depending on the precise tick where arrival
	# consumes a whole step and travels zero distance.
	var e := _ready_enemy()
	var path := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(-500, 0)])
	e.setup(&"slime", path, 1)
	var sprite: Sprite2D = e.get_node("Sprite")

	var right_lean := 0.0
	var left_lean := 0.0
	for i in 20:
		e._physics_process(0.05)
		if sprite.rotation < -0.01:
			right_lean = sprite.rotation
		elif sprite.rotation > 0.01:
			left_lean = sprite.rotation

	assert_true(right_lean < 0.0, "the enemy leans one way while heading toward path[1] (%f)" % right_lean)
	assert_true(left_lean > 0.0, "and the other way once it turns around toward path[2] (%f)" % left_lean)
	e.free()
	return true

func test_every_kind_declares_a_stride() -> bool:
	for kind in Enemies.KINDS:
		assert_true(float(Enemies.DEFS[kind]["stride_px"]) > 0.0,
			"%s declares a stride length" % kind)
	return true

# --------------------------------------------------------------------------
# Sprite filtering
# --------------------------------------------------------------------------

# The illustrated variants are painted art, minified between 1.3x and 1.6x to
# reach their declared sprite_px (the ogre 79x76 into 58 tall, the goblin
# 60x52 into 34, the bat 100x44 into 28) - the same regime map_renderer.gd's
# _place already filters LINEAR_WITH_MIPMAPS for the props, for the same
# reason. NEAREST was right for the Kenney sheets this replaced (48px
# hand-placed pixel art, hard edges, a handful of colours per sprite); a
# linear filter on THOSE smeared them. Painted art minified by a non-integer
# factor wants the opposite: NEAREST would produce dropped-pixel aliasing,
# and a mipmap chain keeps it clean at any distance the game ends up using.
#
# The chain now exists. Task 10 of the illustrated art swap turned
# mipmaps/generate=true on for every variant .import sidecar (pinned by
# test_art_import.gd), completing the pair this assertion started: the
# filter was set to sample a chain before the chain existed to sample, and
# now both halves are true together.
#
# This is set on the node in enemy.tscn rather than in setup(), so it holds
# for an enemy that is instantiated but never set up too, and so it costs
# nothing at runtime. The assertion reads the node property rather than the
# scene file's text, so it stays true however the value comes to be set.
func test_enemy_sprites_use_a_linear_mipmap_filter_for_the_minified_painted_art() -> bool:
	var e := _ready_enemy()
	var sprite: Sprite2D = e.get_node("Sprite")

	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"the enemy sprite filters LINEAR_WITH_MIPMAPS, matching the minified painted props")
	assert_false(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE,
		"the filter is stated on the sprite itself, not inherited from a parent that may not set one")

	e.free()
	return true
