# Base class for test suites. Test suite scripts `extends TestCase` and
# define `test_*` methods; test/run_tests.gd discovers and calls them.
#
# NOTE: this file is intentionally named "case.gd", not "test_case.gd". The
# runner discovers every test_*.gd file under test/ and treats it as a
# suite; if this base class carried that prefix it would be discovered too
# and immediately trip run_tests.gd's "zero test methods" guard (it defines
# no test_* methods of its own). Keep this filename off the test_* pattern.
class_name TestCase
extends RefCounted

var _failures: Array[String] = []
var _checks := 0

func check_count() -> int:
	return _checks

func failures() -> Array[String]:
	return _failures

func assert_eq(actual, expected, msg: String) -> void:
	_checks += 1
	if not _values_equal(actual, expected):
		_failures.append("%s\n      expected: %s\n      actual:   %s" % [msg, expected, actual])

func assert_true(actual: bool, msg: String) -> void:
	assert_eq(actual, true, msg)

func assert_false(actual: bool, msg: String) -> void:
	assert_eq(actual, false, msg)

func assert_almost_eq(actual: float, expected: float, epsilon: float, msg: String) -> void:
	_checks += 1
	if absf(actual - expected) > epsilon:
		_failures.append("%s\n      expected: %f (+/- %f)\n      actual:   %f" % [msg, expected, epsilon, actual])

func _values_equal(a, b) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b
