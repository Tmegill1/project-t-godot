extends TestCase

# Pins the shape and every cost in the upgrade table. The costs are the
# balance surface: they are what a player feels, and a transcription slip in
# one of thirty-two numbers is invisible without this.
#
# test/case.gd's _values_equal cannot distinguish 20 from 20.0, so no test
# here detects a *type* change - a cost that became a float would pass. The
# shape assertions below at least catch a missing or extra tier.

const EXPECTED_COSTS := {
	&"basic": {&"sustained": [30, 60, 130, 260], &"burst": [30, 65, 145, 290]},
	&"fast": {&"sustained": [40, 80, 165, 330], &"burst": [40, 85, 175, 350]},
	&"mortar": {&"sustained": [50, 100, 200, 400], &"burst": [50, 105, 210, 420]},
	&"long": {&"sustained": [60, 120, 240, 450], &"burst": [60, 130, 260, 500]},
}

const EXPECTED_TIER_LABELS := {
	&"basic": {
		&"sustained": ["Quick Loader", "Drum Feed", "Fragmentation", "Saturation"],
		&"burst": ["Heavy Rounds", "Rifled Barrel", "Spotter", "Executioner"],
	},
	&"fast": {
		&"sustained": ["Hair Trigger", "Overclocked", "Cryo Rounds", "Deep Freeze"],
		&"burst": ["Machined Rounds", "Scavenger", "Bounty Board", "War Profiteer"],
	},
	&"mortar": {
		&"sustained": ["Wide Bore", "Quick Crew", "Cluster Shell", "Firestorm"],
		&"burst": ["Packed Charge", "Heavy Shell", "Siege Charge", "Bunker Buster"],
	},
	&"long": {
		&"sustained": ["Long Barrel", "Rapid Loader", "Shellburst", "Carpet Fire"],
		&"burst": ["Dense Slug", "Shaped Charge", "Tungsten Core", "Siege Cannon"],
	},
}

func test_branches_are_sustained_and_burst() -> bool:
	assert_eq(Upgrades.BRANCHES.size(), 2, "exactly two branches")
	assert_true(Upgrades.BRANCHES.has(&"sustained"), "sustained branch exists")
	assert_true(Upgrades.BRANCHES.has(&"burst"), "burst branch exists")
	return true

func test_every_tower_kind_has_both_branches() -> bool:
	for kind in Towers.KINDS:
		assert_true(Upgrades.DEFS.has(kind), "%s has upgrade defs" % kind)
		for branch in Upgrades.BRANCHES:
			assert_true(Upgrades.DEFS[kind].has(branch), "%s has a %s branch" % [kind, branch])
	return true

func test_every_branch_has_exactly_four_tiers() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			assert_eq(tiers.size(), 4, "%s/%s has four tiers" % [kind, branch])
	return true

func test_tier_costs_match_the_reference_table() -> bool:
	for kind in EXPECTED_COSTS:
		for branch in EXPECTED_COSTS[kind]:
			var expected: Array = EXPECTED_COSTS[kind][branch]
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			for i in expected.size():
				assert_eq(int(tiers[i]["cost"]), int(expected[i]),
					"%s/%s tier %d costs %d" % [kind, branch, i + 1, expected[i]])
	return true

func test_tier_labels_match_the_reference_table() -> bool:
	for kind in EXPECTED_TIER_LABELS:
		for branch in EXPECTED_TIER_LABELS[kind]:
			var expected: Array = EXPECTED_TIER_LABELS[kind][branch]
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			for i in expected.size():
				assert_eq(tiers[i]["label"], expected[i],
					"%s/%s tier %d is '%s'" % [kind, branch, i + 1, expected[i]])
	return true

func test_every_tier_has_a_nonempty_description() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				assert_true(String(tier["description"]).length() > 0,
					"%s/%s '%s' has description text for the UI" % [kind, branch, tier["label"]])
	return true

# Guards the transcription against invented effect keys: a typo like
# "damage_multipler" would otherwise sit in the table doing nothing, and
# resolve_tower_stats would silently ignore it.
func test_every_effect_key_is_recognised() -> bool:
	var known := [
		&"damage_multiplier", &"fire_rate_multiplier", &"range_multiplier",
		&"pierce_bonus", &"splash_radius", &"detection",
		&"slow_factor", &"slow_duration_ms",
		&"gold_multiplier", &"bonus_gold_per_kill",
	]
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				for key in tier["effects"]:
					assert_true(known.has(key),
						"%s/%s '%s' effect key %s is recognised" % [kind, branch, tier["label"], key])
	return true

# The one divergence from the reference table, pinned so it is deliberate
# rather than drift. Delete this test together with the effect when armoured
# enemies land and pierce starts biting.
func test_tungsten_core_carries_an_interim_live_effect() -> bool:
	var tier: Dictionary = Upgrades.DEFS[&"long"][&"burst"]["tiers"][2]
	assert_eq(tier["label"], "Tungsten Core", "tier 3 of long/burst")
	assert_eq(int(tier["effects"][&"pierce_bonus"]), 5, "keeps the reference's pierce")
	assert_almost_eq(float(tier["effects"][&"damage_multiplier"]), 1.3, 0.0001,
		"carries interim damage so the purchase is not inert while pierce is dormant")
	return true

func test_get_branch_returns_the_branch_definition() -> bool:
	var branch := Upgrades.get_branch(&"basic", &"sustained")
	assert_eq(branch["label"], "Barrage", "basic's sustained branch is Barrage")
	return true
