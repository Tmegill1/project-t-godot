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
