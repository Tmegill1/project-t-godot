extends TestCase

func test_assertions_pass() -> void:
	assert_eq(2 + 2, 4, "arithmetic works")
	assert_true(true, "true is true")
	assert_almost_eq(0.1 + 0.2, 0.3, 0.0001, "floats compare with epsilon")
