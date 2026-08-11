extends TestCase

# Golden values generated from the reference implementation in
# reference/project-t/td-browser/src/game/sim/rng.ts with seed 12345.
# If these ever change, map layouts diverge from the Phaser build.
const GOLDEN_12345 := [
	0.97972826776094735,
	0.30675226449966431,
	0.48420542152598500,
	0.81793441250920296,
	0.50942836934700608,
	0.34747186047025025,
	0.07375754183158278,
	0.76639646734111011,
]

func test_matches_javascript_reference() -> bool:
	var r := Rng.new(12345)
	for i in GOLDEN_12345.size():
		assert_almost_eq(r.next(), GOLDEN_12345[i], 1e-15,
			"draw %d matches the JS mulberry32 stream" % i)
	return true

func test_same_seed_same_sequence() -> bool:
	var a := Rng.new(777)
	var b := Rng.new(777)
	for i in 20:
		assert_almost_eq(a.next(), b.next(), 1e-15, "draw %d reproducible" % i)
	return true

func test_next_stays_in_unit_interval() -> bool:
	var r := Rng.new(4242)
	for i in 500:
		var v := r.next()
		assert_true(v >= 0.0 and v < 1.0, "draw %d within [0,1)" % i)
	return true

func test_int_range_is_inclusive_both_ends() -> bool:
	var r := Rng.new(9)
	var seen_lo := false
	var seen_hi := false
	for i in 400:
		var v := r.int_range(1, 3)
		assert_true(v >= 1 and v <= 3, "int_range stays in bounds")
		if v == 1:
			seen_lo = true
		if v == 3:
			seen_hi = true
	assert_true(seen_lo, "low bound is reachable")
	assert_true(seen_hi, "high bound is reachable")
	return true

func test_shuffle_does_not_mutate_input() -> bool:
	var source := [1, 2, 3, 4, 5]
	var r := Rng.new(31337)
	var out := r.shuffle(source)
	assert_eq(source, [1, 2, 3, 4, 5], "input array untouched")
	assert_eq(out.size(), 5, "output has same length")
	out.sort()
	assert_eq(out, [1, 2, 3, 4, 5], "output is a permutation")
	return true

func test_fork_is_independent_and_reproducible() -> bool:
	var parent_a := Rng.new(2024)
	var forked_a := parent_a.fork()
	var parent_b := Rng.new(2024)
	var forked_b := parent_b.fork()
	for i in 10:
		assert_almost_eq(forked_a.next(), forked_b.next(), 1e-15,
			"forked stream %d reproducible" % i)
	return true
