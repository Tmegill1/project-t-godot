extends TestCase

## sim/ and data/ must never touch the engine's scene layer, or the headless
## harness becomes impossible and balance stops being testable.

const FORBIDDEN := [
	"extends Node", "extends Node2D", "extends Control", "extends Sprite2D",
	"extends Area2D", "extends CharacterBody2D", "extends CanvasItem",
	"get_tree()", "preload(", "@onready", "@export", "get_node(",
	"randf(", "randi(", "RandomNumberGenerator",
]

const GUARDED_DIRS := ["res://sim", "res://data"]

func test_no_engine_or_scene_references_in_sim_or_data() -> bool:
	var offences: Array[String] = []
	for dir in GUARDED_DIRS:
		for path in _gd_files(dir):
			var text: String = FileAccess.get_file_as_string(path)
			for token in FORBIDDEN:
				if _contains_outside_comments(text, token):
					offences.append("%s contains %s" % [path, token])
	assert_eq(offences, [] as Array[String],
		"sim/ and data/ must stay engine-free")
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
