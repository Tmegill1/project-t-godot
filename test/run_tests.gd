extends SceneTree

# Fails closed. Any of the following forces a non-zero exit:
#   - an assertion failure recorded via TestCase (assert_eq/assert_true/...)
#   - a script that failed to compile. On this engine build load() does NOT
#     return null on a parse error (verified empirically) - it returns a
#     non-null GDScript whose can_instantiate() is false and whose
#     get_script_method_list() is empty, so the file's tests would
#     otherwise vanish silently (0 methods to iterate, no error). Detect
#     this via can_instantiate() instead of a null check.
#   - a test method that recorded zero assertions. GDScript has no
#     try/catch, so a runtime error (e.g. out-of-bounds access) partway
#     through a test method aborts that method and returns control to the
#     caller silently - there is no exception object to inspect. A test
#     that crashed before its first assert_* call is therefore
#     indistinguishable, from the outside, from one that never asserts
#     anything. Both are defects, so both fail the run.
#   - zero test methods discovered/executed in the whole run (catches an
#     empty/misconfigured test/ dir, and is a last line of defense if every
#     file above failed to load or every test crashed pre-assert).
#
# Known gap: a test method that records one or more PASSING assertions and
# then crashes later in the same method is not detectable from here. The
# assertions that ran before the crash look like a normal pass, and
# GDScript gives this script no way to observe that the method was cut
# short. Keep test methods small and prefer one assertion-bearing
# expectation per crash-prone operation to limit the blast radius.
func _initialize() -> void:
	var files := _discover("res://test")
	var checks := 0
	var failing_assertions := 0
	var failing_tests := 0
	var load_errors := 0
	var zero_assertion_tests := 0
	var tests_run := 0

	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			# Parse error. Godot has already printed
			# 'ERROR: Failed to load script "..." with error "Parse error".'
			# to stderr. load() returns a non-null-but-broken GDScript here
			# (empirically confirmed on 4.7.1: can_instantiate() == false,
			# get_script_method_list() == []), not null - so a plain
			# `script == null` check alone would miss this. Without either
			# check the file would silently contribute 0 tests and 0
			# failures.
			load_errors += 1
			printerr("LOAD ERROR %s: script failed to load (parse error?) - 0 tests run from this file" % path)
			continue

		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			tests_run += 1
			case.call(test_name)
			checks += case.check_count()
			var fails := case.failures()

			if case.check_count() == 0:
				zero_assertion_tests += 1
				failing_tests += 1
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				printerr("    zero assertions recorded (crashed before first assert_*, or asserts nothing)")
			elif not fails.is_empty():
				failing_tests += 1
				failing_assertions += fails.size()
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				for f in fails:
					printerr("    " + f)

	if tests_run == 0:
		printerr("ERROR: 0 test methods discovered/executed - failing closed")

	print("%d checks across %d files | %d failing assertions in %d tests | %d load errors | %d zero-assertion tests" % [
		checks, files.size(), failing_assertions, failing_tests, load_errors, zero_assertion_tests])

	var ok := failing_assertions == 0 and load_errors == 0 and zero_assertion_tests == 0 and tests_run > 0
	quit(0 if ok else 1)

# Discovers test_*.gd files recursively under dir_path. The "test_" prefix
# match is case-insensitive so e.g. Test_Foo.gd is discovered rather than
# silently skipped with no diagnostic.
#
# Helper/base-class scripts (e.g. test/case.gd) must intentionally avoid
# this prefix so they are not mistaken for a test suite - see the comment
# atop test/case.gd.
func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		else:
			var lower := entry.to_lower()
			if lower.begins_with("test_") and lower.ends_with(".gd"):
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
