extends TestCase

## sim/ and data/ must never touch the engine's scene layer, or the headless
## harness becomes impossible and balance stops being testable.
##
## The ban covers two things, not one. Scene types and resource loading break
## the *headless* claim (the harness could not run at all). Engine RNG, wall
## clocks and process/platform state break the *reproducible* claim, which is
## the more insidious of the two: a sim module that reads Time.get_ticks_msec()
## still runs headlessly and still passes every test — until the day two runs
## of the same wave disagree and no test says why. Both classes belong here.

const FORBIDDEN := [
	"extends Node", "extends Node2D", "extends Control", "extends Sprite2D",
	"extends Area2D", "extends CharacterBody2D", "extends CanvasItem",
	"get_tree()", "preload(", "@onready", "@export", "get_node(",
	"randf(", "randi(", "RandomNumberGenerator",
	"load(", "ResourceLoader",
	"randi_range(", "randf_range(", "randfn(", "randomize()", "seed(",
	# Nondeterminism that is not RNG. Time.* is a wall/monotonic clock, so a
	# result derived from it is unreproducible by construction. Engine.* leaks
	# frame counts, physics/process deltas, time scale and editor-vs-runtime
	# state — the sim is handed its delta by its caller and must never ask.
	# OS.* leaks platform, locale, environment, command line and process id.
	# All three would sail past every check above while making a balance result
	# depend on when and where it ran.
	"Time.", "Engine.", "OS.",
]

const GUARDED_DIRS := ["res://sim", "res://data"]

func test_no_engine_or_scene_references_in_sim_or_data() -> bool:
	var offences: Array[String] = []
	for dir in GUARDED_DIRS:
		for path in _gd_files(dir):
			var text: String = FileAccess.get_file_as_string(path)
			offences.append_array(_scan_text_for_offences(path, text))
	assert_eq(offences, [] as Array[String],
		"sim/ and data/ must stay engine-free")
	return true

# Runs every detector against one file's text and returns its offences.
# Factored out of the test above so a dedicated test can exercise this
# exact pipeline (see test_scan_pipeline_reports_every_detector_kind
# below) rather than only the individual detector functions in isolation.
#
# Exception: data/biomes.gd is a resource index that intentionally couples to
# textures via load() - this is a specific design, not a violation.
func _scan_text_for_offences(path: String, text: String) -> Array[String]:
	var offences: Array[String] = []
	var is_biomes := path == "res://data/biomes.gd"
	for token in FORBIDDEN:
		if is_biomes and token == "load(":
			continue
		if _contains_outside_comments(text, token):
			offences.append("%s contains %s" % [path, token])
	if _has_node_shorthand_outside_comments(text):
		offences.append(path + " contains $/% node-path shorthand")
	return offences

# The detector functions are unit-tested directly above, but that alone
# does not prove the real scan actually calls them: deleting the "for
# token in FORBIDDEN: ..." loop or the node-shorthand call from
# _scan_text_for_offences (while leaving the detectors themselves intact
# and passing their own unit tests) would still leave
# test_no_engine_or_scene_references_in_sim_or_data green today, since
# sim/ and data/ are clean and produce zero offences either way. Confirmed
# empirically: this exact mutation was applied and the suite stayed green
# until this test was added. Exercising _scan_text_for_offences directly
# with synthetic violations pins the wiring itself, not just the
# detectors it calls.
func test_scan_pipeline_reports_every_detector_kind() -> bool:
	assert_eq(_scan_text_for_offences("res://sim/fake.gd", "var x = get_tree()").size(), 1,
		"the scan pipeline surfaces a plain forbidden-token violation")
	assert_eq(_scan_text_for_offences("res://sim/fake.gd", "var x = $Sprite").size(), 1,
		"the scan pipeline surfaces a node-shorthand violation")
	assert_eq(_scan_text_for_offences("res://sim/fake.gd", "var x = 1 + 2").size(), 0,
		"the scan pipeline reports nothing for clean code")
	return true

func test_the_guard_finds_at_least_one_file() -> bool:
	var count := 0
	for dir in GUARDED_DIRS:
		count += _gd_files(dir).size()
	assert_true(count >= 8, "the guard actually scanned files, found %d" % count)
	return true

# sim/ and data/ happen to be flat today, so a scan that silently stopped
# descending into subdirectories would still find the same file count and
# this guard would pass vacuously the moment either directory grows a
# subdirectory. Exercise recursion directly against a throwaway nested
# fixture under user:// (writable in headless test runs, and never part of
# the tracked project tree) so this is caught now, not discovered later.
func test_the_guard_recurses_into_subdirectories() -> bool:
	var root := "user://purity_recursion_probe"
	var nested := root.path_join("nested")
	DirAccess.make_dir_recursive_absolute(nested)
	var f := FileAccess.open(nested.path_join("probe.gd"), FileAccess.WRITE)
	f.store_string("# fixture file for test_the_guard_recurses_into_subdirectories\n")
	f.close()

	var found := _gd_files(root)

	DirAccess.remove_absolute(nested.path_join("probe.gd"))
	DirAccess.remove_absolute(nested)
	DirAccess.remove_absolute(root)

	assert_eq(found.size(), 1, "the guard must descend into subdirectories, not just scan the top level")
	return true

# Without this, deleting every entry from FORBIDDEN (or silently dropping
# one) makes test_no_engine_or_scene_references_in_sim_or_data pass
# vacuously - zero tokens checked means zero offences found, no matter what
# sim/ or data/ contain. The detector-behaviour tests above do not catch
# this: they call _contains_outside_comments() with literal strings, never
# through FORBIDDEN itself.
func test_forbidden_token_list_is_not_empty() -> bool:
	assert_true(FORBIDDEN.size() >= 10,
		"the forbidden-token list must not be emptied, found %d entries" % FORBIDDEN.size())
	assert_true(FORBIDDEN.has("get_tree()"), "get_tree() must remain a forbidden token")
	assert_true(FORBIDDEN.has("preload("), "preload( must remain a forbidden token")
	assert_true(FORBIDDEN.has("extends Node2D"), "extends Node2D must remain a forbidden token")
	# One representative of each ban class, so dropping a whole class is loud.
	assert_true(FORBIDDEN.has("randf("), "engine RNG must remain forbidden")
	assert_true(FORBIDDEN.has("Time."), "Time. must remain forbidden (wall clock)")
	assert_true(FORBIDDEN.has("Engine."), "Engine. must remain forbidden (frame/process state)")
	assert_true(FORBIDDEN.has("OS."), "OS. must remain forbidden (platform/process state)")
	return true

# The detector must be able to detect. Without these, the guard above could
# pass simply by never matching anything.
func test_detector_flags_a_positive_sample() -> bool:
	assert_true(_contains_outside_comments("var x = get_tree()", "get_tree()"),
		"detects a real call")
	assert_true(_contains_outside_comments("extends Node2D", "extends Node2D"),
		"detects a scene base class")
	return true

func test_detector_ignores_comments() -> bool:
	assert_false(_contains_outside_comments("# never call get_tree() here", "get_tree()"),
		"a mention in a comment is not a violation")
	assert_false(_contains_outside_comments("## preload( is forbidden", "preload("),
		"a mention in a doc comment is not a violation")
	return true

func test_detector_rejects_a_negative_sample() -> bool:
	assert_false(_contains_outside_comments("var x = 1 + 2", "get_tree()"),
		"clean code is not flagged")
	return true

# load( is the same resource-coupling class as the already-banned preload(
# - a plain load(...) call bypasses that ban with identical effect.
func test_detector_flags_load_and_resource_loader() -> bool:
	assert_true(_contains_outside_comments("var x = load(\"res://foo.tres\")", "load("),
		"a plain load() call is detected")
	assert_true(_contains_outside_comments("var x = ResourceLoader.load(path)", "ResourceLoader"),
		"ResourceLoader is detected")
	return true

# randf(/randi( only match the exact zero-arg spelling; every underscored
# sibling and the seeding/randomizing calls need their own tokens.
func test_detector_flags_the_remaining_rng_entry_points() -> bool:
	assert_true(_contains_outside_comments("var x = randi_range(1, 5)", "randi_range("),
		"randi_range is detected")
	assert_true(_contains_outside_comments("var x = randf_range(0.0, 1.0)", "randf_range("),
		"randf_range is detected")
	assert_true(_contains_outside_comments("var x = randfn(0.0, 1.0)", "randfn("),
		"randfn is detected")
	assert_true(_contains_outside_comments("randomize()", "randomize()"),
		"randomize() is detected")
	assert_true(_contains_outside_comments("seed(12345)", "seed("),
		"seed( is detected")
	return true

# The non-RNG nondeterminism sources. Without these the guard bans dice but not
# clocks: a sim module reading the wall time, the frame counter or the platform
# would pass every other detector while breaking reproducibility just as
# thoroughly. The trailing "." is what makes each token specific — it matches
# the static-class access that is the only way to reach these in GDScript.
func test_detector_flags_the_non_rng_nondeterminism_sources() -> bool:
	assert_true(_contains_outside_comments("var t = Time.get_ticks_msec()", "Time."),
		"Time.get_ticks_msec is detected")
	assert_true(_contains_outside_comments("var d = Engine.get_physics_frames()", "Engine."),
		"Engine.get_physics_frames is detected")
	assert_true(_contains_outside_comments("var n = OS.get_unix_time()", "OS."),
		"OS. static access is detected")
	assert_true(_contains_outside_comments("if Engine.is_editor_hint():", "Engine."),
		"Engine.is_editor_hint is detected")
	# And they route through the real scan pipeline, not just the detector.
	assert_eq(_scan_text_for_offences("res://sim/fake.gd", "var t = Time.get_ticks_msec()").size(), 1,
		"the scan pipeline surfaces a wall-clock violation")
	return true

# The new tokens are bare substrings, so they must not fire on ordinary code
# that merely contains those letters. Confirms the ban is specific enough to
# live in a guard that fails the build.
func test_detector_does_not_false_positive_on_the_new_tokens() -> bool:
	assert_false(_contains_outside_comments("var elapsed_time = 0.0", "Time."),
		"a snake_case local named elapsed_time is not a clock read")
	assert_false(_contains_outside_comments("var engine := 5", "Engine."),
		"a lowercase identifier is not Engine.")
	assert_false(_contains_outside_comments("var cost = 5", "OS."),
		"clean arithmetic is not OS access")
	assert_eq(_scan_text_for_offences("res://sim/fake.gd", "var elapsed_time = 0.0").size(), 0,
		"the scan pipeline stays quiet on clean time-ish code")
	return true

# $ and % are Godot's node-path and unique-name shorthand ($Sprite,
# %HealthBar) - more idiomatic in view-layer code than get_node(), and
# sharing no substring with it, so a straightforward substring ban would
# miss them entirely.
func test_node_shorthand_detector_flags_dollar_and_percent_node_paths() -> bool:
	assert_true(_has_node_shorthand_outside_comments("var x = $Sprite"),
		"$ node-path shorthand is detected")
	assert_true(_has_node_shorthand_outside_comments("var y = %HealthBar"),
		"% unique-name shorthand is detected")
	return true

# The bare characters must not false-positive: % is also the modulo
# operator, and both characters legitimately appear inside string literals
# (a percentage value, a dollar amount, or data/maps.gd's own "%s" format
# placeholder).
func test_node_shorthand_detector_ignores_modulo_and_string_literals() -> bool:
	assert_false(_has_node_shorthand_outside_comments("var r = a % b"),
		"the modulo operator is not a node reference")
	assert_false(_has_node_shorthand_outside_comments("var s = \"100%\""),
		"a percent sign inside a string literal is not a node reference")
	assert_false(_has_node_shorthand_outside_comments("var s = \"$5\""),
		"a dollar sign inside a string literal is not a node reference")
	return true

func test_node_shorthand_detector_ignores_comments() -> bool:
	assert_false(_has_node_shorthand_outside_comments("# do not reach for $Sprite here"),
		"a mention in a comment is not a violation")
	return true

func _contains_outside_comments(text: String, token: String) -> bool:
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var code: String = stripped
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if code.contains(token):
			return true
	return false

func _has_node_shorthand_outside_comments(text: String) -> bool:
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var code: String = stripped
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if _has_node_shorthand(code):
			return true
	return false

# $ and % introduce node-path/unique-name shorthand only when they are NOT
# already inside a string literal (a bare "%" inside "100%" or a data-table
# format placeholder like "%s" is ordinary text, not code). This walks the
# line character by character tracking whether a quote is currently open,
# so the shorthand check below only runs on real code. A match requires the
# very next character to be an identifier-start character (a bare "$"/"%"
# used as an operator or in running prose does not match) or a quote (the
# quoted-path form, e.g. %"Health Bar" - only recognised when it opens a
# new string, not when it is itself inside one already).
func _has_node_shorthand(code: String) -> bool:
	var in_string := false
	var quote_char := ""
	var i := 0
	var n := code.length()
	while i < n:
		var c: String = code.substr(i, 1)
		if in_string:
			if c == "\\":
				i += 2
				continue
			if c == quote_char:
				in_string = false
			i += 1
			continue
		if c == "\"" or c == "'":
			in_string = true
			quote_char = c
			i += 1
			continue
		if c == "$" or c == "%":
			if i + 1 < n:
				var following: String = code.substr(i + 1, 1)
				if following == "\"" or following == "'" or _is_identifier_start(following):
					return true
			i += 1
			continue
		i += 1
	return false

func _is_identifier_start(c: String) -> bool:
	return c == "_" or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")

func _gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
