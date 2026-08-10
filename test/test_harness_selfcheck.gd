extends TestCase

func test_assertions_pass() -> bool:
	assert_eq(2 + 2, 4, "arithmetic works")
	assert_true(true, "true is true")
	assert_almost_eq(0.1 + 0.2, 0.3, 0.0001, "floats compare with epsilon")
	return true

# Pins the mid-test-crash detection mechanism documented in
# test/run_tests.gd and test/case.gd. This does NOT crash itself - it
# calls a separate probe script (test/support/crash_probe.gd) and inspects
# the probe's return values, so a regression here surfaces as a normal
# assertion failure rather than tripping run_tests.gd's own crash-handling
# path. See test/support/crash_probe.gd for why each call is expected to
# return false.
func test_sentinel_catches_mid_test_crash() -> bool:
	var probe = load("res://test/support/crash_probe.gd").new()
	assert_eq(probe.call("crash_out_of_bounds"), false,
		"an aborted -> bool call must yield the bool default (false), not true - out-of-bounds index")
	assert_eq(probe.call("crash_null_dereference"), false,
		"an aborted -> bool call must yield the bool default (false), not true - null dereference")
	assert_eq(probe.call("crash_division_by_zero"), false,
		"an aborted -> bool call must yield the bool default (false), not true - division by zero")
	return true
