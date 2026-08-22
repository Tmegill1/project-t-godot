extends TestCase

# --------------------------------------------------------------------------
# Brief's tests (converted from -> void to -> bool per the harness contract).
# --------------------------------------------------------------------------

func _tower(priority: StringName, extra := {}) -> Dictionary:
	var t := {"position": Vector2(0, 0), "range": 100.0, "priority": priority}
	t.merge(extra, true)
	return t

func _enemy(id: int, pos: Vector2, health: float, path_index: int, extra := {}) -> Dictionary:
	var e := {"id": id, "position": pos, "health": health,
		"path_index": path_index, "alive": true, "dying": false}
	e.merge(extra, true)
	return e

func test_default_priority_is_closest() -> bool:
	assert_eq(Targeting.DEFAULT_PRIORITY, &"closest", "matches pre-upgrade behaviour")
	return true

func test_out_of_range_enemies_are_not_targetable() -> bool:
	assert_false(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(200, 0), 5.0, 0)),
		"beyond range")
	assert_true(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(50, 0), 5.0, 0)),
		"within range")
	return true

func test_range_boundary_is_inclusive() -> bool:
	assert_true(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(100, 0), 5.0, 0)),
		"exactly at range counts")
	return true

func test_dead_and_dying_enemies_are_not_targetable() -> bool:
	assert_false(Targeting.is_targetable(_tower(&"closest"),
		_enemy(1, Vector2(10, 0), 5.0, 0, {"alive": false})), "dead")
	assert_false(Targeting.is_targetable(_tower(&"closest"),
		_enemy(1, Vector2(10, 0), 5.0, 0, {"dying": true})), "dying")
	return true

func test_phasing_is_a_hard_gate_not_a_penalty() -> bool:
	var phased := _enemy(1, Vector2(10, 0), 5.0, 0, {"phased": true})
	assert_false(Targeting.is_targetable(_tower(&"closest"), phased),
		"invisible without detection")
	assert_true(Targeting.is_targetable(_tower(&"closest", {"detection": true}), phased),
		"visible with detection")
	return true

func test_closest_picks_the_nearest() -> bool:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "nearest wins")
	return true

func test_first_picks_the_one_furthest_along() -> bool:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"first"), enemies)["id"], 1, "highest path index")
	return true

func test_last_picks_the_one_least_far_along() -> bool:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"last"), enemies)["id"], 2, "lowest path index")
	return true

func test_strongest_picks_the_highest_health() -> bool:
	var enemies := [_enemy(1, Vector2(90, 0), 3.0, 9), _enemy(2, Vector2(10, 0), 20.0, 1)]
	assert_eq(Targeting.select(_tower(&"strongest"), enemies)["id"], 2, "most health")
	return true

func test_ties_break_on_lowest_id_so_results_are_reproducible() -> bool:
	var enemies := [_enemy(7, Vector2(50, 0), 5.0, 3), _enemy(2, Vector2(50, 0), 5.0, 3)]
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "lowest id wins a tie")
	# Reversed input order must not change the answer.
	enemies.reverse()
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "order independent")
	return true

func test_returns_null_when_nothing_is_eligible() -> bool:
	assert_eq(Targeting.select(_tower(&"closest"), []), null, "empty list")
	assert_eq(Targeting.select(_tower(&"closest"), [_enemy(1, Vector2(500, 0), 5.0, 0)]), null,
		"all out of range")
	return true

func test_next_priority_cycles() -> bool:
	assert_eq(Targeting.next_priority(&"first"), &"last", "first to last")
	assert_eq(Targeting.next_priority(&"closest"), &"first", "wraps around")
	return true

func test_weakest_prefers_the_lowest_health_enemy() -> bool:
	var tower := {"position": Vector2.ZERO, "range": 500.0,
		"priority": &"weakest", "detection": false}
	var candidates := [
		{"id": 1, "position": Vector2(10, 0), "health": 9, "path_index": 5,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(20, 0), "health": 2, "path_index": 3,
			"alive": true, "dying": false},
		{"id": 3, "position": Vector2(30, 0), "health": 7, "path_index": 9,
			"alive": true, "dying": false},
	]
	var picked = Targeting.select(tower, candidates)
	assert_true(picked != null, "something was picked")
	if picked == null:
		return true
	assert_eq(int(picked["id"]), 2, "the 2-health enemy is chosen over 7 and 9")
	return true

func test_weakest_is_the_exact_inverse_of_strongest() -> bool:
	# Guards a sign error: a scorer returning +health for weakest would still
	# pick "a" target and still pass a single-case test.
	var candidates := [
		{"id": 1, "position": Vector2(10, 0), "health": 4, "path_index": 1,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(10, 0), "health": 11, "path_index": 1,
			"alive": true, "dying": false},
	]
	var weak = Targeting.select({"position": Vector2.ZERO, "range": 500.0,
		"priority": &"weakest", "detection": false}, candidates)
	var strong = Targeting.select({"position": Vector2.ZERO, "range": 500.0,
		"priority": &"strongest", "detection": false}, candidates)
	assert_true(weak != null and strong != null, "both picked a target")
	if weak == null or strong == null:
		return true
	assert_eq(int(weak["id"]), 1, "weakest takes the 4-health enemy")
	assert_eq(int(strong["id"]), 2, "strongest takes the 11-health enemy")
	return true

func test_weakest_still_respects_range_and_the_phasing_gate() -> bool:
	# The new scorer must not bypass is_targetable: a low-health enemy out of
	# range, or phased against a tower without detection, is not a target.
	var tower := {"position": Vector2.ZERO, "range": 50.0,
		"priority": &"weakest", "detection": false}
	var candidates := [
		{"id": 1, "position": Vector2(500, 0), "health": 1, "path_index": 1,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(10, 0), "health": 3, "path_index": 1,
			"alive": true, "dying": false, "phased": true},
		{"id": 3, "position": Vector2(20, 0), "health": 8, "path_index": 1,
			"alive": true, "dying": false},
	]
	var picked = Targeting.select(tower, candidates)
	assert_true(picked != null, "something in range was picked")
	if picked == null:
		return true
	assert_eq(int(picked["id"]), 3, "the far 1-health and phased 3-health are both ineligible")
	return true

func test_the_priority_list_pairs_the_two_health_scorers() -> bool:
	# Ordering is load-bearing: next_priority() cycles this array, and the two
	# existing cycle tests only keep passing while `closest` stays last.
	assert_eq(Targeting.PRIORITIES.size(), 5, "five priorities")
	assert_eq(Targeting.PRIORITIES[Targeting.PRIORITIES.size() - 1], &"closest",
		"closest stays last so the wrap assertion holds")
	var strongest_at := Targeting.PRIORITIES.find(&"strongest")
	assert_eq(Targeting.PRIORITIES[strongest_at + 1], &"weakest",
		"weakest sits directly after strongest")
	return true

func test_every_priority_has_a_label() -> bool:
	for priority in Targeting.PRIORITIES:
		var label: String = Targeting.LABELS.get(priority, "")
		assert_false(label.is_empty(), "%s has a label" % priority)
	return true

# --------------------------------------------------------------------------
# Ported from targeting.test.ts beyond the brief's list. Expected values are
# taken directly from the .test.ts file, never derived by running this
# GDScript port. These use reference-shaped helpers (_ref_tower/_ref_enemy)
# that mirror the reference file's own `tower()`/`enemy()` factories and
# default values, so ported scenarios can be transcribed with the reference's
# literal overrides rather than re-derived through the brief's helpers.
# --------------------------------------------------------------------------

func _ref_tower(extra := {}) -> Dictionary:
	var t := {"position": Vector2(0, 0), "range": 500.0, "priority": &"closest"}
	t.merge(extra, true)
	return t

func _ref_enemy(id: int, extra := {}) -> Dictionary:
	var e := {"id": id, "position": Vector2(100, 0), "health": 10.0,
		"path_index": 1, "alive": true, "dying": false}
	e.merge(extra, true)
	return e

func _lineup() -> Array:
	return [
		_ref_enemy(1, {"position": Vector2(100, 0), "health": 5.0, "path_index": 1}),
		_ref_enemy(2, {"position": Vector2(200, 0), "health": 30.0, "path_index": 4}),
		_ref_enemy(3, {"position": Vector2(300, 0), "health": 12.0, "path_index": 2}),
	]

# Ported: "picks the nearest for 'closest'".
func test_lineup_closest_picks_the_nearest() -> bool:
	var result = Targeting.select(_ref_tower({"priority": &"closest"}), _lineup())
	assert_eq(result["id"], 1, "closest of the lineup is id 1")
	return true

# Ported: "picks the furthest along the route for 'first'".
func test_lineup_first_picks_the_furthest_along() -> bool:
	var result = Targeting.select(_ref_tower({"priority": &"first"}), _lineup())
	assert_eq(result["id"], 2, "highest path_index in the lineup is id 2")
	return true

# Ported: "picks the least far along for 'last'".
func test_lineup_last_picks_the_least_far_along() -> bool:
	var result = Targeting.select(_ref_tower({"priority": &"last"}), _lineup())
	assert_eq(result["id"], 1, "lowest path_index in the lineup is id 1")
	return true

# Ported: "picks the highest health for 'strongest'".
func test_lineup_strongest_picks_the_highest_health() -> bool:
	var result = Targeting.select(_ref_tower({"priority": &"strongest"}), _lineup())
	assert_eq(result["id"], 2, "most health in the lineup is id 2")
	return true

# Ported: "returns null when nothing is in range" — the whole lineup (out to
# x=300) rejected by a tight range of 10, exercised through select(), not
# just is_targetable().
func test_lineup_returns_null_when_range_too_small() -> bool:
	assert_eq(Targeting.select(_ref_tower({"range": 10.0}), _lineup()), null,
		"nothing in the lineup is within range 10")
	return true

# Ported eligibility group: "ignores the dead" / "ignores the dying" /
# "ignores anything beyond range" / "includes an enemy exactly on the range
# boundary" — through select(), at the reference's own magnitudes (10,000
# for "far", exactly 500 for the boundary), distinct from the brief's
# is_targetable()-level checks and its smaller range values.
func test_select_ignores_the_dead() -> bool:
	assert_eq(Targeting.select(_ref_tower(), [_ref_enemy(1, {"alive": false})]), null,
		"a dead enemy is never selected")
	return true

func test_select_ignores_the_dying_so_shots_are_not_wasted_on_corpses() -> bool:
	assert_eq(Targeting.select(_ref_tower(), [_ref_enemy(1, {"dying": true})]), null,
		"a dying enemy is never selected")
	return true

func test_select_ignores_anything_beyond_range() -> bool:
	var far := [_ref_enemy(1, {"position": Vector2(10000, 0)})]
	assert_eq(Targeting.select(_ref_tower(), far), null, "far beyond range 500")
	return true

func test_select_includes_an_enemy_exactly_on_the_range_boundary() -> bool:
	var edge := [_ref_enemy(1, {"position": Vector2(500, 0)})]
	assert_eq(Targeting.select(_ref_tower({"range": 500.0}), edge)["id"], 1,
		"exactly at range 500 still selects")
	return true

# Ported phasing group, through select() rather than is_targetable() alone.
func test_select_hides_phased_enemies_from_a_tower_without_detection() -> bool:
	var phased := [_ref_enemy(1, {"phased": true})]
	assert_eq(Targeting.select(_ref_tower(), phased), null, "blind tower selects nothing")
	return true

func test_select_reveals_phased_enemies_to_a_tower_with_detection() -> bool:
	var phased := [_ref_enemy(1, {"phased": true})]
	assert_eq(Targeting.select(_ref_tower({"detection": true}), phased)["id"], 1,
		"detection reveals the phased enemy")
	return true

# Ported: "still lets a blind tower shoot unphased enemies in the same
# group" — the hard-gate behaviour must exclude only the phased candidate,
# not degrade the whole selection.
func test_select_blind_tower_still_targets_unphased_enemies_in_the_same_group() -> bool:
	var mixed := [_ref_enemy(1, {"phased": true, "position": Vector2(50, 0)}), _ref_enemy(2)]
	assert_eq(Targeting.select(_ref_tower(), mixed)["id"], 2,
		"the unphased enemy is still selectable even though it is farther away")
	return true

# Ported: "breaks ties on the lowest id" with three candidates, not just two,
# so the tie-break cannot be a pairwise "compare the first two" shortcut.
func test_ties_break_on_lowest_id_three_way() -> bool:
	var identical := [_ref_enemy(7), _ref_enemy(3), _ref_enemy(5)]
	assert_eq(Targeting.select(_ref_tower(), identical)["id"], 3, "lowest of 7, 3, 5 is 3")
	return true

# Regression test (added after code review found a real bug): a genuine,
# non-tied score difference must win outright, even when the two scores are
# close enough that is_equal_approx would have called them a tie. P and Q
# are NOT at the same distance — Q is closer, if only by a hair — so Q must
# win regardless of which one the loop visits first. Before this was fixed
# to use strict `==`, is_equal_approx(scoreP, scoreQ) returned true here
# (their distances differ by ~0.0001, well inside its relative tolerance),
# so whichever candidate the loop reached FIRST kept "winning" via the
# score > best_score branch never firing for the second one, and the
# id-tie-break branch (wrongly) treating them as tied and preferring the
# lower id (2) - id 2 is P, the FARTHER enemy - regardless of order. That
# silently violated both "closest wins" and the "order never matters" claim
# in select()'s own doc comment.
func test_a_genuinely_closer_candidate_wins_even_when_scores_are_float_close() -> bool:
	var tower := _ref_tower({"range": 1000.0})
	var p := _ref_enemy(2, {"position": Vector2(500.0, 0)})       # distance 500.0
	var q := _ref_enemy(7, {"position": Vector2(499.9999, 0)})    # distance ~499.999908, genuinely closer
	assert_eq(Targeting.select(tower, [p, q])["id"], 7, "q is closer, p first in the array")
	assert_eq(Targeting.select(tower, [q, p])["id"], 7, "q is closer, q first in the array")
	return true

# Regression test pinning that "closest" scores by linear distance
# (distance_to), not squared distance. Positions found by an empirical
# search for two points whose distance_to() from the origin rounds to the
# exact same float while their distance_squared_to() does not (verified:
# 9.990004539 == 9.990004539, but 99.800193787 != 99.800186157) - i.e. a
# genuine tie under the metric the module is supposed to use, that would
# NOT be a tie if it scored by squared distance instead. Under squared
# distance, id 2 (the numerically-smaller-square candidate) would win
# outright via score > best_score, skipping the id tie-break entirely and
# silently preferring the higher id on what is actually a dead-even tie.
func test_closest_scores_by_linear_distance_not_squared_distance() -> bool:
	var tower := _ref_tower({"range": 20.0})
	var candidate_a := _ref_enemy(1, {"position": Vector2(9.99, -0.01)})
	var candidate_b := _ref_enemy(2, {"position": Vector2(9.99, -0.009661)})
	assert_eq(Targeting.select(tower, [candidate_a, candidate_b])["id"], 1,
		"exact tie under linear distance breaks on lowest id (a first)")
	assert_eq(Targeting.select(tower, [candidate_b, candidate_a])["id"], 1,
		"same exact tie, order swapped - still lowest id")
	return true

# Ported: "does not depend on iteration order" — for every declared
# priority, forward and backward orderings of a fully-tied field (three
# enemies sharing every scored attribute, differing only by id) must agree.
func test_order_independence_holds_for_every_priority() -> bool:
	var forward := [_ref_enemy(1), _ref_enemy(2), _ref_enemy(3)]
	var backward := forward.duplicate()
	backward.reverse()
	for priority in Targeting.PRIORITIES:
		var t := _ref_tower({"priority": priority})
		var forward_result = Targeting.select(t, forward)
		var backward_result = Targeting.select(t, backward)
		assert_eq(forward_result["id"], backward_result["id"],
			"forward and backward selection agree for priority %s" % priority)
	return true

# Ported: "supports every declared priority" — a smoke test that no priority
# branch is missing/broken and returns null on a normal lineup.
func test_select_supports_every_declared_priority() -> bool:
	for priority in Targeting.PRIORITIES:
		var result = Targeting.select(_ref_tower({"priority": priority}), _lineup())
		assert_true(result != null, "priority %s selects something from the lineup" % priority)
	return true

# Ported: "agrees with selectTarget on eligibility" — direct is_targetable()
# checks including a range-of-1 case not covered by the brief.
func test_is_targetable_agrees_with_select_on_eligibility() -> bool:
	assert_true(Targeting.is_targetable(_ref_tower(), _ref_enemy(1)), "baseline is targetable")
	assert_false(Targeting.is_targetable(_ref_tower(), _ref_enemy(1, {"dying": true})),
		"dying is not targetable")
	assert_false(Targeting.is_targetable(_ref_tower({"range": 1.0}), _ref_enemy(1)),
		"range of 1 cannot reach a distance-100 enemy")
	return true

# Ported: "cycles through every priority and returns to the start" — the
# generic cycle algorithm (not just the brief's two fixed steps): walking
# next_priority() PRIORITIES.size() - 1 times from the first entry visits
# every priority exactly once, and one more step returns to the start.
func test_next_priority_cycles_through_all_and_returns_to_start() -> bool:
	var current: StringName = Targeting.PRIORITIES[0]
	var seen := {current: true}
	for i in range(Targeting.PRIORITIES.size() - 1):
		current = Targeting.next_priority(current)
		seen[current] = true
	assert_eq(seen.size(), Targeting.PRIORITIES.size(), "every priority was visited exactly once")
	assert_eq(Targeting.next_priority(current), Targeting.PRIORITIES[0], "wraps back to the start")
	return true

# --------------------------------------------------------------------------
# Mutation-testing-driven addition (not from the reference — TypeScript's
# TargetCandidate.alive/.dying are required fields, so targeting.test.ts has
# no reason to test a missing key). This GDScript port instead reads them
# via candidate.get("alive", true) / candidate.get("dying", false), so the
# defaults are live code with their own failure mode. Every _enemy()/
# _ref_enemy() helper above always bakes both keys in, so no test above
# actually exercises the .get() default path — flipping either default
# survived the rest of the suite untouched during mutation testing. This
# closes that gap directly.
# --------------------------------------------------------------------------
func test_missing_alive_and_dying_keys_default_to_targetable() -> bool:
	var bare := {"id": 1, "position": Vector2(10, 0), "health": 5.0, "path_index": 0}
	assert_true(Targeting.is_targetable(_ref_tower(), bare),
		"a candidate dict omitting alive/dying keys defaults to alive and not dying")
	return true

# Not ported, and why:
#   - reference's "returns null for an empty field" (selectTarget(tower(), []))
#     is already covered verbatim by the brief's test_returns_null_when_nothing_is_eligible,
#     which asserts Targeting.select(_tower(&"closest"), []) == null.
#   - reference's "DEFAULT_TARGETING_PRIORITY ... matches the behaviour towers
#     had before priorities existed" is already covered verbatim by the
#     brief's test_default_priority_is_closest.
# Both would be byte-for-byte duplicate assertions under a new name.
