extends TestCase

## Normal is the IDENTITY row. Every balance number this project has measured
## describes Normal, so if any multiplier here drifts off 1.0 the whole
## existing suite becomes a description of something nobody tuned.
func test_normal_is_the_identity_transform() -> bool:
	for key in Difficulty.KEYS:
		assert_almost_eq(Difficulty.multiplier(Difficulty.NORMAL, key), 1.0, 0.0001,
			"normal's %s is exactly 1.0" % key)
	assert_eq(Difficulty.starting_lives(Difficulty.NORMAL), Economy.STARTING_LIVES,
		"normal keeps the shipped life budget")
	return true

## Every tier carries every key. A tier missing one would push the default
## onto the lookup site, which puts a balance number in code instead of data.
func test_every_tier_carries_every_key() -> bool:
	for tier in Difficulty.ORDER:
		assert_true(Difficulty.DEFS.has(tier), "%s is in DEFS" % tier)
		var def: Dictionary = Difficulty.DEFS[tier]
		for key in Difficulty.KEYS:
			assert_true(def.has(key), "%s carries %s" % [tier, key])
		assert_true(def.has("starting_lives"), "%s carries starting_lives" % tier)
		assert_true(def.has("label"), "%s carries label" % tier)
	return true

func test_order_and_defs_agree() -> bool:
	assert_eq(Difficulty.ORDER.size(), Difficulty.DEFS.size(),
		"ORDER covers DEFS exactly")
	return true

## Catches a transposed table row, which no single-tier test can see: each
## lever must move the same direction across the whole ladder.
func test_tiers_never_get_easier_as_they_go_up() -> bool:
	for i in range(1, Difficulty.ORDER.size()):
		var lower: StringName = Difficulty.ORDER[i - 1]
		var higher: StringName = Difficulty.ORDER[i]
		for key in [&"count_multiplier", &"health_multiplier", &"speed_multiplier"]:
			assert_true(Difficulty.multiplier(higher, key) >= Difficulty.multiplier(lower, key),
				"%s's %s is at least %s's" % [higher, key, lower])
		# These two run the other way: SMALLER is harsher.
		for key in [&"interval_multiplier", &"gold_multiplier"]:
			assert_true(Difficulty.multiplier(higher, key) <= Difficulty.multiplier(lower, key),
				"%s's %s is at most %s's" % [higher, key, lower])
		assert_true(Difficulty.starting_lives(higher) <= Difficulty.starting_lives(lower),
			"%s grants no more lives than %s" % [higher, lower])
	return true
