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
	assert_eq(e._sprite.scale, Vector2.ONE * float(Enemies.DEFS[&"ogre"]["sprite_scale"]),
		"the sprite is scaled by the enemy's sprite_scale (1.2 for the ogre, not left at 1.0)")

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

# The comment above the brief's guard explains why: a tick that consumes
# itself arriving at a waypoint covers no real distance, so its "direction"
# is noise from a sub-pixel delta and must not be allowed to flip the sprite.
# A vertical micro-step (spawn 1px from the second waypoint, comfortably
# inside Movement.WAYPOINT_ARRIVAL_RADIUS = 2.0) reaches "down" on the very
# first tick while the enemy's facing is still its "side" default - if the
# guard were dropped, this tick would visibly flip it to "down".
func test_physics_process_does_not_update_facing_on_a_waypoint_arrival_tick() -> bool:
	var e := _ready_enemy()
	var path := PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(0, 100)])
	e.setup(&"slime", path, 1)
	assert_eq(e._facing, &"side", "precondition: default facing is side")
	assert_eq(e._sprite.animation, &"walk_side", "precondition: default animation is walk_side")

	e._physics_process(0.016)

	assert_eq(e.sim["path_index"], 2, "the waypoint was still consumed")
	assert_eq(e.sim["alive"], true, "goal not yet reached (path has a third point)")
	assert_eq(e._facing, &"side", "facing was not touched on the arrival tick")
	assert_eq(e._sprite.animation, &"walk_side", "animation was not replayed on the arrival tick")

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

# _die() plays "death_%s" % _facing *before* its `await`, so it is observable
# synchronously (see the walk-facing assertions at test_physics_process_does_
# not_update_facing_on_a_waypoint_arrival_tick and the flip-matrix test
# above). Both prior death-related tests deal their lethal hit while _facing
# is still its class default (&"side"), so a mutation that hardcodes
# "death_side" - or drops the "%s" interpolation entirely - would agree with
# the correct code on every existing assertion. Driving the enemy to a
# non-side facing first, via a real physics tick, closes that gap.
func test_die_plays_the_death_animation_for_the_enemys_current_facing() -> bool:
	var e := _ready_enemy()
	var vertical_path := PackedVector2Array([Vector2(0, 0), Vector2(0, 100), Vector2(0, 200)])
	e.setup(&"slime", vertical_path, 1)

	e._physics_process(0.016)  # distance to (0, 100) is 100px, well past WAYPOINT_ARRIVAL_RADIUS - no arrival, so facing updates
	assert_eq(e._facing, &"down", "precondition: the tick actually turned the enemy to face down")

	e.take_damage({"damage": 999.0})  # one hit, comfortably lethal for a 5-health slime
	assert_eq(e._sprite.animation, &"death_down", "the death animation matches the enemy's facing at the moment it died, not a fixed direction")

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
# _set_facing / flip matrix (amendment 3: the brief's behaviour is accepted
# as-is, deliberately not matching the reference's sticky flip on up/down)
# --------------------------------------------------------------------------

# One enemy per kind: each assertion within a kind's block deliberately
# changes at least one of (direction, flip) from the previous call, so none
# of these calls hit _set_facing's own "nothing changed" early return - that
# path is exercised separately below.
func test_set_facing_flip_matrix_for_all_three_creatures_and_directions() -> bool:
	for entry in [
		{"kind": &"slime", "flip_h": false},
		{"kind": &"bee", "flip_h": false},
		{"kind": &"ogre", "flip_h": true},
	]:
		var kind: StringName = entry["kind"]
		assert_eq(Enemies.DEFS[kind]["flip_horizontally"], entry["flip_h"],
			"precondition: %s's flip_horizontally is what this test assumes" % kind)

		var e := _ready_enemy()
		e.setup(kind, _straight_path(), 1)

		e._set_facing(&"side", true)
		var expected_side_left: bool = true if not entry["flip_h"] else false
		assert_eq(e._sprite.flip_h, expected_side_left, "%s facing side, moving left" % kind)

		e._set_facing(&"side", false)
		var expected_side_right: bool = false if not entry["flip_h"] else true
		assert_eq(e._sprite.flip_h, expected_side_right, "%s facing side, moving right" % kind)

		e._set_facing(&"up", true)
		var expected_up: bool = entry["flip_h"]
		assert_eq(e._sprite.flip_h, expected_up, "%s facing up ignores moving_left (brief's non-sticky reset)" % kind)

		e._set_facing(&"down", false)
		var expected_down: bool = entry["flip_h"]
		assert_eq(e._sprite.flip_h, expected_down, "%s facing down ignores moving_left (brief's non-sticky reset)" % kind)

		e.free()
	return true

# Mutation target: `if direction == _facing and flip == _flip: return`.
# Swapping `and` for `or` would make the guard fire whenever *either* half
# matches. Each case below holds exactly one half equal to the enemy's
# current state and changes the other, so a correct `and` must update and a
# mutated `or` would wrongly skip - each case independently kills that
# mutation.
func test_set_facing_updates_when_only_one_of_direction_or_flip_differs() -> bool:
	# Case 1: same direction ("side" -> "side"), different flip.
	var e1 := _ready_enemy()
	e1.setup(&"slime", _straight_path(), 1)  # starts at facing=side, flip=false
	e1._set_facing(&"side", true)  # direction unchanged, flip becomes true
	assert_eq(e1._sprite.flip_h, true, "flip alone changing is enough to update - an 'or' guard would wrongly skip this")
	e1.free()

	# Case 2: different direction ("side" -> "up"), same flip (false).
	var e2 := _ready_enemy()
	e2.setup(&"slime", _straight_path(), 1)  # starts at facing=side, flip=false
	e2._set_facing(&"up", false)  # direction changes; flip stays false either way
	assert_eq(e2._facing, &"up", "direction alone changing is enough to update - an 'or' guard would wrongly skip this")
	assert_eq(e2._sprite.animation, &"walk_up", "the walk animation was replayed for the new direction")
	e2.free()
	return true

# --------------------------------------------------------------------------
# _build_frames
# --------------------------------------------------------------------------

func test_build_frames_produces_six_animations_with_correct_speed_and_loop_flags() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var frames: SpriteFrames = e._sprite.sprite_frames

	assert_false(frames.has_animation("default"), "the default SpriteFrames animation was removed")
	var names := frames.get_animation_names()
	assert_eq(names.size(), 6, "exactly six animations")
	for anim in ["walk_up", "walk_side", "walk_down", "death_up", "death_side", "death_down"]:
		assert_true(anim in names, "%s animation exists" % anim)
		assert_eq(frames.get_frame_count(anim), Enemy.FRAMES_PER_SHEET, "%s has FRAMES_PER_SHEET frames" % anim)

	for anim in ["walk_up", "walk_side", "walk_down"]:
		assert_eq(frames.get_animation_speed(anim), Enemy.WALK_FPS, "%s plays at WALK_FPS" % anim)
		assert_true(frames.get_animation_loop(anim), "%s loops" % anim)
	for anim in ["death_up", "death_side", "death_down"]:
		assert_eq(frames.get_animation_speed(anim), Enemy.DEATH_FPS, "%s plays at DEATH_FPS" % anim)
		assert_false(frames.get_animation_loop(anim), "%s does not loop" % anim)

	e.free()
	return true

func test_build_frames_frame_regions_and_source_sheet_match_the_reference() -> bool:
	var e := _ready_enemy()
	e.setup(&"ogre", _straight_path(), 1)  # ogre to also exercise a non-default texture_key
	var frames: SpriteFrames = e._sprite.sprite_frames

	var first: AtlasTexture = frames.get_frame_texture(&"walk_down", 0)
	assert_eq(first.region, Rect2(0, 0, Enemy.FRAME_SIZE, Enemy.FRAME_SIZE), "frame 0 region starts at x=0")
	assert_eq(first.atlas.resource_path, "res://assets/enemies/ogre/D_Walk.png", "walk_down reads the D_Walk sheet for ogre")

	var last: AtlasTexture = frames.get_frame_texture(&"walk_down", Enemy.FRAMES_PER_SHEET - 1)
	assert_eq(last.region, Rect2(5 * Enemy.FRAME_SIZE, 0, Enemy.FRAME_SIZE, Enemy.FRAME_SIZE),
		"the last frame's region starts at 5 * FRAME_SIZE = 240")

	var death_side: AtlasTexture = frames.get_frame_texture(&"death_side", 2)
	assert_eq(death_side.region, Rect2(2 * Enemy.FRAME_SIZE, 0, Enemy.FRAME_SIZE, Enemy.FRAME_SIZE),
		"a middle frame's region starts at index * FRAME_SIZE")
	assert_eq(death_side.atlas.resource_path, "res://assets/enemies/ogre/S_Death.png", "death_side reads the S_Death sheet")

	var walk_up: AtlasTexture = frames.get_frame_texture(&"walk_up", 0)
	assert_eq(walk_up.atlas.resource_path, "res://assets/enemies/ogre/U_Walk.png", "walk_up reads the U_Walk sheet")

	e.free()
	return true

# All three real creatures have valid sheets on disk, so the "missing sheet"
# branch never fires for any reachable production kind - exercising it
# means calling _build_frames directly with a texture_key nothing on disk
# matches. Pins that a missing sheet is skipped cleanly (continue) rather
# than an unguarded null Texture2D getting wired into an AtlasTexture.
func test_build_frames_skips_a_missing_sheet_without_crashing() -> bool:
	var e := _ready_enemy()
	var frames: SpriteFrames = e._build_frames("no_such_creature")

	assert_true(frames.has_animation("walk_down"), "the animation slot still exists")
	assert_eq(frames.get_frame_count("walk_down"), 0, "no frames were added for a sheet that failed to load")
	assert_eq(frames.get_frame_count("death_up"), 0, "every animation is affected, not just one")

	e.free()
	return true

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------

# A script-level const on a class_name script is directly readable as
# ClassName.CONST_NAME with no tree, no node, and no draw pass involved -
# the same technique test_tower.gd/test_projectile.gd use for their own
# constants. This pins the literal values even though every one of them is
# also exercised indirectly above (frame math, animation speeds).
func test_frame_size_frames_per_sheet_and_fps_constants_match_the_brief() -> bool:
	assert_eq(Enemy.FRAME_SIZE, 48, "FRAME_SIZE")
	assert_eq(Enemy.FRAMES_PER_SHEET, 6, "FRAMES_PER_SHEET")
	assert_eq(Enemy.WALK_FPS, 8.0, "WALK_FPS")
	assert_eq(Enemy.DEATH_FPS, 10.0, "DEATH_FPS")
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
# Sprite filtering
# --------------------------------------------------------------------------

# The enemy sheets are 48x48 hand-placed pixel art (hard edges, a handful of
# colours per sprite) drawn at sprite_scale 0.7 or 1.2. Godot's project-wide
# default canvas filter is LINEAR, which bilinearly blends those hard edges
# into mush at any scale other than 1.0 - so the enemies rendered blurry
# while every neighbouring element stayed sharp.
#
# This is set on the node in enemy.tscn rather than in setup(), so it holds
# for an enemy that is instantiated but never set up too, and so it costs
# nothing at runtime. The assertion reads the node property rather than the
# scene file's text, so it stays true however the value comes to be set.
#
# Deliberately NOT applied project-wide: assets/map/*.png and towers.png are
# painted, high-resolution art downscaled hard (stone.png 216px -> 48px, a
# 22% reduction), and NEAREST on that produces dropped-pixel aliasing. Only
# the genuine pixel art wants a nearest filter. See map_renderer.gd.
func test_enemy_sprites_use_a_nearest_filter_so_the_pixel_art_stays_sharp() -> bool:
	var e := _ready_enemy()
	var sprite: AnimatedSprite2D = e.get_node("Sprite")

	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"the enemy sprite filters NEAREST, keeping 48px pixel art crisp at sprite_scale 0.7 and 1.2")
	assert_false(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE,
		"the filter is stated on the sprite itself, not inherited from a parent that may not set one")

	e.free()
	return true
