extends TestCase

# AudioManager is registered as an autoload (project.godot), but the test
# harness runs the whole suite inside SceneTree._initialize() under
# `godot --headless --script`, which never starts a real game loop -
# confirmed directly with a throwaway probe before writing anything below
# (see task-22-report.md for the transcript). Two consequences follow:
#
#   1. Autoload singletons are never instantiated under this harness, and
#      their global identifier does not even resolve at *compile* time - a
#      bare `AudioManager` reference anywhere would abort compilation of
#      whatever script contains it (this is why game_board.gd looks the
#      singleton up via get_node_or_null instead of referencing it by
#      name). These tests therefore load and instantiate
#      audio/audio_manager.gd directly, the same way test_enemy.gd
#      instantiates enemy.tscn rather than relying on the scene tree, and
#      fire NOTIFICATION_READY by hand (add_child() alone does not resolve
#      @onready/_ready() in this harness either).
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
