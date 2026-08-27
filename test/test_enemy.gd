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


func _straight_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])

# --------------------------------------------------------------------------
# setup()
# --------------------------------------------------------------------------

func test_setup_populates_sim_with_scaled_health_and_speed_for_goblin_at_wave_one() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)

	var modifiers := Waves.get_modifiers(1)
	var expected_health := float(Enemies.scaled_health(&"goblin", modifiers["health_modifier"]))
	var expected_speed := Enemies.scaled_speed(&"goblin", modifiers["speed_modifier"])

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
# rather than e.g. always scaling as if for wave 1 or always as goblin.
func test_setup_scales_health_and_speed_for_ogre_at_a_later_wave() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 10)

	var modifiers := Waves.get_modifiers(10)
	assert_true(modifiers["health_modifier"] > 1.0, "precondition: wave 10 is past the last authored wave, so modifiers are not 1.0")
	var expected_health := float(Enemies.scaled_health(&"ogre", modifiers["health_modifier"]))
	var expected_speed := Enemies.scaled_speed(&"ogre", modifiers["speed_modifier"])

	assert_eq(e.sim["health"], expected_health, "ogre health at wave 10 uses the ogre base and the wave-10 modifier")
	assert_eq(e.sim["speed"], expected_speed, "ogre speed at wave 10 uses the ogre base and the wave-10 modifier")
	assert_true(expected_health != float(Enemies.scaled_health(&"goblin", modifiers["health_modifier"])),
		"precondition: ogre and goblin scale to different health values, so a kind mix-up would be caught")

	e.free()
	return true

func test_setup_sets_position_kind_and_starting_path_index() -> bool:
	var e := _ready_enemy()
	# Deliberately not starting at the origin: Vector2.ZERO would silently
	# agree with a mutant that hardcodes the spawn position instead of
	# reading path[0] - confirmed by actually running that mutation against
	# a straight path starting at (0, 0) before switching to this one.
	var path := PackedVector2Array([Vector2(40, 25), Vector2(100, 0), Vector2(100, 100)])
	e.setup(&"bat", path, 1)

	assert_eq(e.kind, &"bat", "kind is stored")
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", path, 1)
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
	# Bat at wave 6 (past Leak.LIFE_LOSS_SCALING_WAVE = 5) puts Leak.resolve on
	# its health-based branch with an uncapped result (health 3, life_loss 2 -
	# neither hits MAX_LIFE_LOSS_PER_LEAK = 4). That makes this scenario
	# sensitive to the two dict fields passed to Leak.resolve being swapped:
	# an ogre-at-wave-3 scenario tried first had both fields individually
	# exceed the cap, so a life_loss/health swap was invisible (both routes
	# saturated to the same capped value of 4) - confirmed by actually
	# running that mutation before settling on this scenario.
	e.setup(&"bat", single_point_path, 6)
	var starting_health: float = e.sim["health"]

	# GDScript lambdas capture locals by value, not by reference, so a plain
	# local var written from inside the callback would never be visible out
	# here - a Dictionary is a reference type, so mutating its contents (not
	# reassigning the variable) does propagate. Verified empirically.
	var captured := {"count": 0, "value": -1}
	e.leaked.connect(func(v): captured["count"] += 1; captured["value"] = v)

	e._physics_process(0.016)

	var expected: int = Leak.resolve(
		{"life_loss": Enemies.DEFS[&"bat"]["life_loss"], "health": starting_health}, 6)
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
	e.setup(&"goblin", _straight_path(), 1)  # health 5

	var r1 := e.take_damage({"damage": 2.0})
	assert_eq(r1["remaining_health"], 3.0, "5 - 2 = 3")
	assert_eq(e.sim["health"], 3.0, "sim reflects the returned remaining_health")
	assert_almost_eq(e._health_bar.size.x, 32.0 * (3.0 / 5.0), 0.001, "health bar width tracks the new fraction")
	assert_false(r1["lethal"], "not lethal yet")

	e.free()
	return true

func test_take_damage_emits_died_exactly_once_on_the_lethal_hit_and_not_before() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)  # health 5, reward 5

	var captured := {"count": 0, "reward": -1, "kind": &""}
	e.died.connect(func(v, k): captured["count"] += 1; captured["reward"] = v; captured["kind"] = k)

	e.take_damage({"damage": 2.0})  # 5 -> 3
	assert_eq(captured["count"], 0, "died has not fired after a non-lethal hit")
	e.take_damage({"damage": 2.0})  # 3 -> 1
	assert_eq(captured["count"], 0, "still not fired one point of health above zero")

	var lethal := e.take_damage({"damage": 2.0})  # 1 -> 0, lethal
	assert_true(lethal["lethal"], "the resolve result reports lethal")
	assert_eq(captured["count"], 1, "died fired exactly once on the lethal hit")
	assert_eq(captured["reward"], int(Enemies.DEFS[&"goblin"]["reward"]), "died carries the enemy's reward")
	assert_eq(captured["kind"], &"goblin", "died carries the enemy's own kind, not a fixed/default value")
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


func test_an_enemy_faces_the_way_it_travels() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	e.set_facing_from_travel(true)
	var left := sprite.flip_h
	e.set_facing_from_travel(false)
	assert_true(sprite.flip_h != left, "travelling the other way flips the sprite")
	e.free()
	return true


# --------------------------------------------------------------------------
# death: a tween replaces the death animation
# --------------------------------------------------------------------------

# Named for what it now is. It read "after the tween rather than an animation"
# when a death was a fade-and-shrink, which is exactly backwards after the art
# arrived with a fall drawn into it.
func test_death_runs_for_a_duration_this_file_owns() -> bool:
	assert_true(Enemy.DEATH_MS > 0.0, "the death sequence has a duration")
	assert_true(Enemy.DEATH_MS < 1000.0,
		"and it is short enough not to hold a kill on screen")
	assert_true(Enemy.DEATH_MS / float(Enemies.death_frames(&"goblin")) >= 60.0,
		"and each drawn frame gets long enough to be seen")
	return true

func test_a_lethal_hit_off_the_tree_still_pays_and_hides_the_bar() -> bool:
	# Every enemy this suite builds is outside the scene tree (see this file's
	# header), and create_tween() requires one. _die must reach everything the
	# sim observes before it gives up on the presentation.
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)

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
	e.setup(&"goblin", _straight_path(), 1)

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
	e.setup(&"bat", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
	assert_almost_eq(e.sim["slow"]["factor"], 1.0, 0.0001, "no slow to begin with")
	assert_almost_eq(e.sim["slow"]["remaining_ms"], 0.0, 0.0001, "and no clock running")
	assert_almost_eq(e.current_speed(), float(e.sim["speed"]), 0.0001, "so it moves at its full speed")
	e.free()
	return true

func test_taking_a_hit_from_a_slowing_source_slows_the_enemy() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	assert_almost_eq(e.current_speed(), full * 0.5, 0.0001, "moving at half speed")
	e.free()
	return true

# The slow lands on a hit that did no damage at all. Being hit is what chills
# the target, not being hurt by it - the reference says so at the same seam.
func test_a_slow_lands_even_when_the_hit_does_no_damage() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	var health_before: float = e.sim["health"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	assert_almost_eq(e.sim["health"], health_before, 0.0001, "precondition: the hit did nothing to its health")
	assert_almost_eq(e.sim["slow"]["factor"], 0.5, 0.0001, "and it is slowed regardless")
	e.free()
	return true

func test_a_stronger_slow_replaces_a_weaker_one() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e.take_damage({"damage": 0.0})
	assert_almost_eq(e.current_speed(), full * 0.5, 0.0001, "a tower that cannot slow cannot cure one either")
	e.free()
	return true

func test_a_slow_expires_after_its_duration() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e.tick_slow(1000.0)
	assert_almost_eq(e.current_speed(), full, 0.0001, "back to full speed")
	e.free()
	return true

# The mechanic only exists if the movement step actually reads it. Goblin moves
# 10px in 100ms unslowed (test_physics_process_advances_position_toward_the_
# first_waypoint pins that); half speed must cover half the ground.
func test_physics_process_moves_a_slowed_enemy_at_the_slowed_speed() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	e.take_damage({"damage": 0.0, "slow_factor": 0.5, "slow_duration_ms": 1000.0})
	e._physics_process(0.1)
	assert_almost_eq(e.position.x, 5.0, 0.001, "5px, not the unslowed 10px")
	e.free()
	return true

# And the clock has to run down as the enemy moves, or a slow would be
# permanent.
func test_physics_process_counts_the_slow_down() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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
	e.setup(&"goblin", _straight_path(), 1)
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

## A path long enough to walk several cycles without reaching the goal.
func _long_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(4000, 0)])

func test_the_walk_frame_advances_with_distance_not_with_time() -> bool:
	# The property the synthesised stride was rewritten for, kept now that the
	# frames are real. A timed cycle would move a 60px/s ogre's legs at the
	# same rate as a 150px/s bat's.
	var slow := _ready_enemy()
	slow.setup(&"ogre", _straight_path(), 1)
	var fast := _ready_enemy()
	fast.setup(&"bat", _straight_path(), 1)
	assert_true(Enemies.DEFS[&"bat"]["base_speed"] > Enemies.DEFS[&"ogre"]["base_speed"],
		"precondition: the bat is faster than the ogre")

	# Count CYCLES completed, not distinct frames seen: the bat's cycle is
	# seven frames where the ogre's is eight, so a distinct-frame count
	# saturates at the shorter cycle and would compare nothing.
	var slow_steps := 0
	var fast_steps := 0
	var slow_last := slow.walk_frame()
	var fast_last := fast.walk_frame()
	for i in 60:
		slow._physics_process(1.0 / 60.0)
		fast._physics_process(1.0 / 60.0)
		if slow.walk_frame() != slow_last:
			slow_steps += 1
			slow_last = slow.walk_frame()
		if fast.walk_frame() != fast_last:
			fast_steps += 1
			fast_last = fast.walk_frame()

	assert_true(fast_steps > slow_steps,
		"over the same time the faster enemy steps through more frames (%d against %d)"
			% [fast_steps, slow_steps])
	slow.free()
	fast.free()
	return true

func test_a_stationary_enemy_holds_its_frame() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _straight_path(), 1)
	for i in 4:
		e._physics_process(0.05)
	var held := e.walk_frame()
	e.sim["speed"] = 0.0
	for i in 20:
		e._physics_process(0.05)
	assert_eq(e.walk_frame(), held, "a stopped enemy does not walk on the spot")
	e.free()
	return true

func test_the_walk_frame_wraps_and_never_leaves_the_cycle() -> bool:
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _long_path(), 1)
		var n := Enemies.walk_frames(kind)
		var seen := {}
		# The game's own tick, not a coarser one: at 0.05s a 100px/s enemy
		# covers 5px, which is more than one frame's worth of a 30px stride,
		# so the test would step over frames the game never skips.
		#
		# 200 ticks is several full cycles for every kind - eleven for the
		# goblin, four for the ogre, fifteen for the bat - which is what makes
		# "reaches every frame" a fair thing to ask.
		for i in 200:
			e._physics_process(1.0 / 60.0)
			var f := e.walk_frame()
			assert_true(f >= 0 and f < n,
				"%s frame %d is inside its %d-frame cycle" % [kind, f, n])
			seen[f] = true
		assert_eq(seen.size(), n, "%s reaches every one of its %d frames" % [kind, n])
		e.free()
	return true

func test_the_sprite_shows_the_frame_the_cycle_names() -> bool:
	var e := _ready_enemy()
	e.setup(&"goblin", _long_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	for i in 120:
		e._physics_process(1.0 / 60.0)
		assert_true(sprite.texture.resource_path.ends_with(
			"walk_%d.png" % e.walk_frame()),
			"the sprite draws walk_%d" % e.walk_frame())
	e.free()
	return true

func test_the_bat_has_a_shorter_cycle_than_the_others() -> bool:
	# Its eighth frame is broken art the bake drops. Pinned here so a
	# regenerated sheet that fixes it shows up as a failing number rather than
	# as nothing.
	assert_eq(Enemies.walk_frames(&"bat"), 7, "the bat walks on seven frames")
	assert_eq(Enemies.walk_frames(&"goblin"), 8, "the goblin walks on eight")
	assert_eq(Enemies.walk_frames(&"ogre"), 8, "the ogre walks on eight")
	return true

func test_the_declared_frame_counts_match_what_was_baked() -> bool:
	for kind in Enemies.KINDS:
		var walk := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/walk_%d.png" % [kind, walk]):
			walk += 1
		var death := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/death_%d.png" % [kind, death]):
			death += 1
		assert_eq(Enemies.walk_frames(kind), walk, "%s declares its walk frames" % kind)
		assert_eq(Enemies.death_frames(kind), death, "%s declares its death frames" % kind)
	return true

# --------------------------------------------------------------------------
# every frame draws at one size
# --------------------------------------------------------------------------

# The bug this gates: apply_sprite_height used to divide sprite_px by EACH
# frame's own height, which is only sensible while the creature is upright. A
# death sequence ends with the creature lying down, so its last frames are
# short and wide - and dividing by a short height scaled them UP. Measured on
# the committed art, the goblin's final death frame drew 2.1x the standing
# creature and the ogre's went from 57px wide to 147. The corpse ballooned.
#
# The scale is now taken once from the creature's standing height and used for
# every frame, so a frame that is short draws short instead of drawing big.
func test_every_frame_of_a_kind_draws_at_the_same_scale() -> bool:
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _long_path(), 1)
		var sprite: Sprite2D = e.get_node("Sprite")
		var standing := sprite.scale.x
		assert_true(standing > 0.0, "%s has a scale to compare against" % kind)
		for action in ["walk", "death"]:
			var n := Enemies.walk_frames(kind) if action == "walk" \
				else Enemies.death_frames(kind)
			for i in n:
				sprite.texture = load(
					"res://assets/art/enemies/%s/%s_%d.png" % [kind, action, i])
				e.apply_sprite_height()
				assert_almost_eq(sprite.scale.x, standing, 0.0001,
					"%s %s_%d draws at the standing scale" % [kind, action, i])
				assert_almost_eq(sprite.scale.y, sprite.scale.x, 0.0001,
					"%s %s_%d is not stretched" % [kind, action, i])
		e.free()
	return true

func test_a_frame_keeps_its_feet_on_the_ground() -> bool:
	# A creature that lies down is shorter than one standing up, and the
	# sprite is centred - so without this the corpse floats where the torso
	# used to be instead of settling where the feet were.
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _long_path(), 1)
		var sprite: Sprite2D = e.get_node("Sprite")
		var baseline := sprite.position.y + sprite.texture.get_height() * sprite.scale.y / 2.0
		for i in Enemies.death_frames(kind):
			sprite.texture = load("res://assets/art/enemies/%s/death_%d.png" % [kind, i])
			e.apply_sprite_height()
			var bottom := sprite.position.y + sprite.texture.get_height() * sprite.scale.y / 2.0
			assert_almost_eq(bottom, baseline, 0.01,
				"%s death_%d rests on the same line it stood on" % [kind, i])
		e.free()
	return true

func test_the_death_frames_are_the_case_this_covers() -> bool:
	# The precondition. If every frame were the same shape, one scale and one
	# baseline would be the same thing and neither test above would prove
	# anything.
	var ratios := []
	for i in Enemies.death_frames(&"goblin"):
		var bytes := FileAccess.get_file_as_bytes(
			"res://assets/art/enemies/goblin/death_%d.png" % i)
		assert_false(bytes.is_empty(), "goblin death_%d exists" % i)
		var img := Image.new()
		assert_eq(img.load_png_from_buffer(bytes), OK, "goblin death_%d decodes" % i)
		ratios.append(float(img.get_width()) / float(img.get_height()))
	assert_true(ratios.size() >= 2, "there is a sequence to compare")
	if ratios.size() < 2:
		return true
	# Not "some are upright and some are flat" - measured, all four of the
	# goblin's death frames are already wider than tall, because it starts the
	# sequence lunging. What matters is that it ends much flatter than it
	# starts, which is what makes one scale for all frames a real constraint
	# rather than a tautology.
	assert_true(float(ratios[ratios.size() - 1]) > float(ratios[0]) * 1.5,
		"the goblin ends its death far flatter than it starts (%.2f against %.2f)"
			% [float(ratios[ratios.size() - 1]), float(ratios[0])])
	return true

# A late-wave enemy pays less than the same enemy early, because the wave's
# gold modifier reaches the payout. The pure function is tested in
# test_economy.gd; this pins that the enemy threads its own wave through to it.
func test_a_late_wave_kill_pays_less_than_an_early_one() -> bool:
	var base := int(Enemies.DEFS[&"goblin"]["reward"])
	var early := EconomySim.kill_reward(base, {},
		float(Waves.get_modifiers(1)["gold_modifier"]))
	var late := EconomySim.kill_reward(base, {},
		float(Waves.get_modifiers(20)["gold_modifier"]))
	assert_true(late < early, "the same goblin is worth less on wave 20 than on wave 1")
	return true

# --------------------------------------------------------------------------
# Resistance reaches the sim state (spec 2026-08-25 section 3)
# --------------------------------------------------------------------------

func test_an_enemy_carries_its_resistance_into_its_sim_state() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 20)
	assert_true(int(e.sim["armor"]) > 0, "the ogre spawned armoured at wave 20")
	assert_eq(int(e.sim["shield"]), 0, "and unshielded")
	e.free()
	return true

# Written before damage types existed, when a shield absorbed the whole hit.
# It is a reduction now, so the claim is that a shielded enemy survives a hit
# it would otherwise die to - not that it survives anything at all.
func test_a_shielded_enemy_survives_a_hit_that_would_otherwise_kill_it() -> bool:
	var e := _ready_enemy()
	e.setup(&"bat", _straight_path(), 20)
	var before: float = e.sim["health"]
	assert_true(int(e.sim["shield"]) > 0, "precondition: the bat spawned shielded")
	# A hit slightly larger than its health: lethal unshielded, survivable with
	# a charge, because only the leak fraction lands.
	e.take_damage({"damage": before + 1.0, "damage_type": &"physical"})
	assert_true(e.sim["alive"], "the charge carried it through")
	assert_true(e.sim["health"] < before, "though not without a scratch")
	e.free()
	return true

# The shield must be WRITTEN BACK or it absorbs every hit forever, which is
# the difference between a charge and invulnerability.
func test_a_shield_charge_is_spent_when_it_absorbs() -> bool:
	var e := _ready_enemy()
	e.setup(&"bat", _straight_path(), 20)
	var charges: int = e.sim["shield"]
	assert_true(charges > 0, "precondition: the bat spawned shielded")
	for i in charges:
		e.take_damage({"damage": 1.0})
	assert_eq(int(e.sim["shield"]), 0, "every charge was spent")
	var before: float = e.sim["health"]
	e.take_damage({"damage": 1.0})
	assert_true(e.sim["health"] < before, "and the next hit lands on health")
	e.free()
	return true

func test_armour_reduces_a_hit_without_stopping_it() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 20)
	var armor: float = float(e.sim["armor"])
	assert_true(armor > 0.0, "precondition: armoured")
	var before: float = e.sim["health"]
	e.take_damage({"damage": armor + 5.0})
	assert_almost_eq(float(e.sim["health"]), before - 5.0, 0.001,
		"armour absorbed exactly its own value")
	e.free()
	return true
