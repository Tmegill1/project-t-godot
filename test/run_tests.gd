extends SceneTree

# ---------------------------------------------------------------------------
# Contract for every test_* method (enforced, not just a convention):
#
#   Every test_* method MUST be declared `-> bool` and end with
#   `return true`. Every early `return` inside a test_* method must also
#   `return true` - the return value is a pure "did I run to completion"
#   sentinel, never a pass/fail signal (assert_* calls carry pass/fail; see
#   case.gd).
#
#   This is what makes a mid-test crash detectable. When a GDScript
#   function aborts partway through due to a runtime error (out-of-bounds
#   index, null dereference, division by zero, ...), Godot does not run
#   that function's own `return` statement - it substitutes the *declared
#   return type's default* and resumes execution in the caller. For
#   `-> bool` that default is `false`. So: a test that completes normally
#   returns `true`; a test that aborts before reaching `return true`
#   returns `false`; and a test with no `-> bool` declaration returns
#   `null` either way (Variant's default) - which also fails the check
#   below, so the contract enforces itself on authors who forget it. This
#   behavior is pinned by a permanent self-test - see
#   test_harness_selfcheck.gd's test_sentinel_catches_mid_test_crash and
#   test/support/crash_probe.gd.
#
# Fails closed. Any of the following forces a non-zero exit:
#   - an assertion failure recorded via TestCase (assert_eq/assert_true/...)
#   - a script that failed to compile. On this engine build load() does NOT
#     return null on a parse error (verified empirically) - it returns a
#     non-null GDScript whose can_instantiate() is false and whose
#     get_script_method_list() is empty, so the file's tests would
#     otherwise vanish silently (0 methods to iterate, no error). Detect
#     this via can_instantiate() instead of a null check.
#   - a test method whose return value is not exactly `true` (see contract
#     above). Catches a crash on any statement running directly in the
#     test method's own body - including one after assertions already
#     passed - and catches an author who forgot the `-> bool` /
#     `return true` contract.
#   - a test method that recorded zero assertions despite completing
#     normally (returned true, but never called assert_*). A test that
#     checks nothing is a defect in its own right.
#   - zero test methods discovered/executed in the whole run (catches an
#     empty/misconfigured test/ dir, and is a last line of defense if every
#     file above failed to load or every test crashed pre-assert).
#
# Known gap: the sentinel only sees a crash on a statement running directly
# in the test method's own function body. Godot's script-error recovery
# does not unwind the call stack - it substitutes a default for the one
# aborting call frame and lets that frame's *caller* carry on normally
# (verified empirically). So if a test method calls a helper function and
# the helper crashes, only the helper's call frame aborts (its call
# expression evaluates to a default, e.g. null); the test method itself is
# NOT aborted, keeps running, and can still legitimately reach
# `return true` - the sentinel is blind to that case. Mitigation: assert on
# the result of any helper call that could fail, so a crashed helper's
# default/null return produces an ordinary, clearly-diagnosed assertion
# failure instead of silence. Prefer flat test_* bodies (a sequence of
# assert_* calls) over ones that delegate to helper functions, to keep
# this gap as narrow as possible.
# ---------------------------------------------------------------------------
func _initialize() -> void:
	var files := _discover("res://test")
	var checks := 0
	var failing_assertions := 0
	var failing_tests := 0
	var load_errors := 0
	var zero_assertion_tests := 0
	var aborted_tests := 0
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
			var completed = case.call(test_name)
			checks += case.check_count()
			var fails := case.failures()

			if completed != true:
				aborted_tests += 1
				failing_tests += 1
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				printerr("    did not return true (returned: %s) - aborted mid-execution, or missing the '-> bool' / 'return true' contract" % [completed])
			elif case.check_count() == 0:
				zero_assertion_tests += 1
				failing_tests += 1
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				printerr("    zero assertions recorded (test completed but asserts nothing)")
			elif not fails.is_empty():
				failing_tests += 1
				failing_assertions += fails.size()
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				for f in fails:
					printerr("    " + f)

	if tests_run == 0:
		printerr("ERROR: 0 test methods discovered/executed - failing closed")

	print("%d checks across %d files | %d failing assertions in %d tests | %d load errors | %d zero-assertion tests | %d aborted tests" % [
		checks, files.size(), failing_assertions, failing_tests, load_errors, zero_assertion_tests, aborted_tests])

	var ok := failing_assertions == 0 and load_errors == 0 and zero_assertion_tests == 0 and aborted_tests == 0 and tests_run > 0
	quit(0 if ok else 1)

# Discovers test_*.gd files recursively under dir_path. The "test_" prefix
# match is case-insensitive so e.g. Test_Foo.gd is discovered rather than
# silently skipped with no diagnostic.
#
# Helper/base-class scripts (e.g. test/case.gd, test/support/crash_probe.gd)
# must intentionally avoid this prefix so they are not mistaken for a test
# suite - see the comment atop test/case.gd.
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
