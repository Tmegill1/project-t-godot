# Support script for test_harness_selfcheck.gd's
# test_sentinel_catches_mid_test_crash. Deliberately aborts mid-execution
# via three different runtime-error mechanisms, each declared `-> bool` and
# ending in `return true` per the contract documented in test/case.gd and
# test/run_tests.gd.
#
# Under correct GDScript script-error-recovery behavior, each of these
# calls should return `false` (the bool default) because the abort happens
# on the statement before `return true`, and Godot substitutes the
# declared return type's default rather than running that final return.
# If a future engine version ever changed this - for example, by letting
# the crash propagate an exception instead, or by returning something
# other than the type default - the self-test that calls these methods
# would start failing loudly with a clear assertion diff, instead of the
# mid-test-crash detection hole reopening silently.
#
# NOTE: intentionally not named test_*.gd - this is test support
# infrastructure invoked by a real test, not a suite to be discovered and
# executed on its own (see test/case.gd for the same convention).
extends RefCounted

func crash_out_of_bounds() -> bool:
	var arr := [1, 2, 3]
	var v = arr[5]
	return true

func crash_null_dereference() -> bool:
	var o = null
	o.nonexistent_method()
	return true

func crash_division_by_zero() -> bool:
	var a := 1
	var b := 0
	var c = a / b
	return true
