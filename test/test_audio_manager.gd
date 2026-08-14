extends TestCase

# AudioManager is registered as an autoload (project.godot), but the test
# harness runs the whole suite inside SceneTree._initialize() under
# `godot --headless --script`, which never starts a real game loop. Two
# things below were probed directly, not assumed:
#
#   1. The autoload node IS instantiated under this harness - probed
#      directly: Engine.get_main_loop().root has exactly one child and it
#      is AudioManager - and a bare `AudioManager` reference compiles and
#      runs without error in a script loaded via load() the way this file
#      and every other test file are loaded by run_tests.gd (confirmed with
#      a throwaway probe shaped exactly like game_board.gd's
#      _ready_board() pattern: a Node2D with an @onready field, never added
#      to a live tree, NOTIFICATION_READY fired by hand). What actually
#      breaks is that NOTIFICATION_READY never reaches the autoload node:
#      is_inside_tree() on it is false, so its own _ready() never runs and
#      _streams/_players never get populated - a live AudioManager under
#      this harness is permanently pre-_ready(). game_board.gd routes
#      through get_node_or_null on the tree root instead of the bare name
#      for an unrelated, real reason (see its own comment), not because the
#      bare name fails to compile. These tests load and instantiate
#      audio/audio_manager.gd directly instead of touching the live
#      singleton, the same way test_enemy.gd instantiates enemy.tscn rather
#      than relying on the scene tree, and fire NOTIFICATION_READY by hand
#      (add_child() alone does not resolve @onready/_ready() in this
#      harness either) - this also sidesteps the live singleton's pool
#      state (_next) leaking between tests, which a fresh instance per test
#      avoids for free.
#
#   2. Nothing in this harness is ever "inside the scene tree" - not even
#      the SceneTree's own root (matches test_enemy.gd's documented
#      finding; reconfirmed here with a throwaway probe: parenting a fresh
#      AudioManager under Engine.get_main_loop().root still leaves
#      is_inside_tree() false). A real AudioStreamPlayer refuses to
#      actually start playback outside a live tree and prints "ERROR:
#      Playback can only happen when a node is inside the scene tree" from
#      the engine every time AudioManager.play() reaches player.play().
#      This does not abort the calling function (verified: _next still
#      advances correctly afterward) and it is not a "SCRIPT ERROR", so it
#      does not trip run_tests.gd's crash sentinel. It is the same
#      category of noise as test_enemy.gd's
#      test_build_frames_skips_a_missing_sheet_without_crashing, which
#      already prints 12 "ERROR: Resource file not found" lines by
#      deliberately exercising a real code path in an environment that
#      can't fully back it - deliberate, understood, non-aborting, and the
#      only way to exercise the *real* production play() rather than a
#      re-implemented copy of its wrap-around logic. The pool test below
#      calls play() POOL_SIZE + 1 times (13) to prove the wrap; the mute
#      test calls it once more to prove unmuting restores playback - 14
#      such lines total from this file.

const AUDIO_MANAGER_SCRIPT := "res://audio/audio_manager.gd"

# Sounds that exist in assets/audio/ but belong to phases after the core
# slice - see task-22-amendments.md #1 and #6. Pinned here so a later phase
# adding one of these to SOUNDS has to do it deliberately, not by accident.
const _DEFERRED_SOUNDS: Array[StringName] = [
	&"boss", &"insignia", &"lieutenant", &"power", &"upgrade",
]

func _manager_script() -> GDScript:
	return load(AUDIO_MANAGER_SCRIPT)

# Deliberately untyped return (Variant): a script loaded by path with no
# class_name has no static type the compiler can check members against, so
# a typed `-> Node` return here would make every `_streams`/`_players`/
# `_next` access below a compile error. Matches game_board.gd's own
# `_play_sound` helper, which the same constraint applies to.
func _ready_manager():
	var mgr = _manager_script().new()
	mgr.notification(Node.NOTIFICATION_READY)
	return mgr

func _sounds() -> Array:
	return _manager_script().get_script_constant_map().get("SOUNDS", [])

func _pool_size() -> int:
	return _manager_script().get_script_constant_map().get("POOL_SIZE", 0)

# --------------------------------------------------------------------------
# SOUNDS content
# --------------------------------------------------------------------------

func test_every_sound_in_sounds_resolves_to_a_real_asset_file() -> bool:
	var sounds := _sounds()
	assert_true(sounds.size() > 0, "SOUNDS is not empty")
	for sound in sounds:
		var sound_name: String = sound
		var found := false
		for ext in [".ogg", ".wav"]:
			if ResourceLoader.exists("res://assets/audio/%s%s" % [sound_name, ext]):
				found = true
				break
		assert_true(found, "assets/audio/%s.(ogg|wav) exists on disk - a silent push_warning is not enough" % sound_name)
	return true

func test_sounds_contains_no_name_outside_the_core_slice() -> bool:
	var sounds := _sounds()
	for deferred in _DEFERRED_SOUNDS:
		assert_false(deferred in sounds,
			"%s belongs to a deferred phase and must not be wired into the core slice yet" % deferred)
	return true

# --------------------------------------------------------------------------
# SOUNDS vs. game data - a kind missing from SOUNDS is a silent future no-op
# --------------------------------------------------------------------------

# _ready()'s push_warning only fires for a name that IS in SOUNDS but has no
# asset file on disk - it says nothing about a kind that is missing FROM
# SOUNDS entirely. Adding a fifth tower or enemy kind without adding its
# "fire-<kind>" / "death-<kind>" entry would compile fine and silently
# no-op forever (play()'s has() guard swallows the unknown name with no
# warning anywhere). Correct today by inspection; this pins it so it stays
# correct.
func test_every_tower_kind_has_a_matching_fire_sound() -> bool:
	var sounds := _sounds()
	for kind in Towers.KINDS:
		var expected: StringName = &"fire-%s" % kind
		assert_true(expected in sounds,
			"%s (the fire sound for tower kind %s) is present in SOUNDS" % [expected, kind])
	return true

func test_every_enemy_kind_has_a_matching_death_sound() -> bool:
	var sounds := _sounds()
	for kind in Enemies.KINDS:
		var expected: StringName = &"death-%s" % kind
		assert_true(expected in sounds,
			"%s (the death sound for enemy kind %s) is present in SOUNDS" % [expected, kind])
	return true

# --------------------------------------------------------------------------
# POOL_SIZE - a real value, not just an internally-consistent one
# --------------------------------------------------------------------------

# Every other test in this file derives its expectation for POOL_SIZE from
# the script's own constant via _pool_size() (get_script_constant_map()
# reflection), so none of them would notice POOL_SIZE regressing to
# something too small to do its job - proved by mutation testing: with
# POOL_SIZE changed from 12 to 1, every assertion in this file still
# passed. This test pins the literal directly, and separately pins the
# property that actually matters: the pool must survive the most
# concurrent-fire scenario the game can produce without one shot's sound
# cutting off an earlier one still playing.
#
# The floor is the largest per-kind tower cap (data/towers.gd's
# base_limit) - currently 8, for both "basic" and "fast" - the scenario
# audio_manager.gd's own module comment cites ("with eight towers firing, a
# single player would drop most shots"). Same-kind towers share one
# fire_rate, so a full complement of one kind is the concrete, plausible
# way to get that many "fire-<kind>" sounds clustered together. The map's
# total tower_budget (16, data/maps.gd, enforced by game_board.gd's
# `total >= tower_budget` placement check) is a harder ceiling, but
# reaching it as a simultaneous *fire* burst needs four different kinds'
# independently-phased cooldowns (500/1000/1500/2000 ms, data/towers.gd's
# fire_rate) to land in the same tick - a real but much rarer coincidence
# than one kind's synchronized cooldown, and not the scenario POOL_SIZE=12
# was chosen against. The floor is computed from Towers.DEFS rather than
# hardcoded, so a future per-kind limit increase forces this test to be
# re-justified instead of silently going stale.
func test_pool_size_is_pinned_and_covers_the_documented_worst_case() -> bool:
	var pool_size := _pool_size()
	assert_eq(pool_size, 12,
		"POOL_SIZE literal - changing the constant must be a deliberate edit to this test too")

	var floor_size := 0
	for kind in Towers.KINDS:
		floor_size = maxi(floor_size, int(Towers.get_def(kind)["base_limit"]))
	assert_eq(floor_size, 8,
		"sanity-check the data this floor is built on: the largest per-kind tower cap is 8 (basic, fast)")
	assert_true(pool_size >= floor_size,
		"POOL_SIZE (%d) must be at least the largest per-kind tower cap (%d) so a full complement of one kind's synchronized volley does not steal playback from itself" % [pool_size, floor_size])

	return true

# --------------------------------------------------------------------------
# _ready()
# --------------------------------------------------------------------------

func test_ready_loads_a_stream_for_every_sound_and_builds_the_full_pool() -> bool:
	var mgr = _ready_manager()
	var sounds := _sounds()
	var streams: Dictionary = mgr._streams
	for sound in sounds:
		assert_true(streams.has(sound), "%s has a loaded stream after _ready()" % sound)
		assert_true(streams.get(sound) != null, "%s's loaded stream is non-null" % sound)

	var players: Array = mgr._players
	assert_eq(players.size(), _pool_size(), "the pool has exactly POOL_SIZE players")
	for player in players:
		assert_true(player is AudioStreamPlayer, "every pool slot is a real AudioStreamPlayer")

	mgr.free()
	return true

# --------------------------------------------------------------------------
# play() - the pool
# --------------------------------------------------------------------------

# Calls the real play() POOL_SIZE + 1 times - the only way to exercise the
# production wrap-around logic itself rather than a re-implemented copy of
# it. See the file header for why this prints benign engine ERROR noise and
# why that is accepted here.
func test_pool_cycles_through_pool_size_distinct_players_then_wraps() -> bool:
	var mgr = _ready_manager()
	var pool_size := _pool_size()
	var place_stream = mgr._streams[&"place"]

	var used_indices := {}
	for i in pool_size:
		var next_before: int = mgr._next
		mgr.play(&"place")
		used_indices[next_before] = true
		assert_eq(mgr._players[next_before].stream, place_stream,
			"player %d received the played stream" % next_before)

	assert_eq(used_indices.size(), pool_size,
		"POOL_SIZE consecutive play() calls used POOL_SIZE distinct players")
	assert_eq(int(mgr._next), 0, "_next wrapped back to 0 after exactly POOL_SIZE calls")

	mgr.play(&"place")
	assert_eq(int(mgr._next), 1, "the (POOL_SIZE + 1)th call reuses player 0 and advances _next to 1")

	mgr.free()
	return true

func test_muted_suppresses_playback_without_touching_the_pool_and_unmuting_restores_it() -> bool:
	var mgr = _ready_manager()
	mgr.set_muted(true)

	var next_before: int = mgr._next
	var player_before = mgr._players[next_before]
	var stream_before = player_before.stream
	mgr.play(&"place")

	assert_eq(int(mgr._next), next_before, "muted play() does not advance the pool index")
	assert_eq(player_before.stream, stream_before,
		"muted play() does not even touch the next player's stream")

	mgr.set_muted(false)
	mgr.play(&"place")
	assert_eq(int(mgr._next), (next_before + 1) % _pool_size(), "unmuted play() advances the pool again")

	mgr.free()
	return true

func test_unknown_sound_name_is_a_no_op_not_a_crash() -> bool:
	var mgr = _ready_manager()
	var next_before: int = mgr._next
	mgr.play(&"not-a-real-sound")
	assert_eq(int(mgr._next), next_before, "an unrecognised sound name does not advance the pool")
	mgr.free()
	return true
