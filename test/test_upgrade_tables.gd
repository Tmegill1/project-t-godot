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
		&"sustained": ["Quick Loader", "Drum Feed", "Open Bolt", "Sustained Fire"],
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
		&"sustained": ["Long Barrel", "Rapid Loader", "Autoloader", "Overwatch"],
		&"burst": ["Dense Slug", "Shaped Charge", "Tungsten Core", "Siege Cannon"],
	},
}


const EXPECTED_EFFECTS := {
	&"basic": {
		&"sustained": [
			{&"fire_rate_bonus_ms": 200.0},
			{&"fire_rate_bonus_ms": 160.0},
			{&"fire_rate_bonus_ms": 140.0, &"range_multiplier": 1.15},
			{&"fire_rate_bonus_ms": 150.0, &"damage_bonus": 2.0},
		],
		&"burst": [
			{&"damage_bonus": 2.0},
			{&"damage_bonus": 2.0},
			{&"detection": true, &"damage_bonus": 4.0},
			{&"damage_bonus": 12.0, &"range_multiplier": 1.25},
		],
	},
	&"fast": {
		&"sustained": [
			{&"fire_rate_bonus_ms": 125.0},
			{&"fire_rate_bonus_ms": 94.0},
			{&"slow_duration_ms": 1500, &"slow_factor": 0.7},
			{&"slow_duration_ms": 2500, &"slow_factor": 0.45, &"fire_rate_bonus_ms": 56.0},
		],
		&"burst": [
			{&"damage_bonus": 1.0},
			{&"bonus_gold_per_kill": 1},
			{&"gold_multiplier": 1.6, &"damage_bonus": 1.0},
			{&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2},
		],
	},
	&"mortar": {
		&"sustained": [
			{&"splash_radius": 70.0},
			{&"fire_rate_bonus_ms": 500.0},
			{&"splash_radius": 95.0, &"fire_rate_bonus_ms": 225.0},
			{&"splash_radius": 130.0, &"damage_bonus": 3.0},
		],
		&"burst": [
			{&"damage_bonus": 3.0},
			{&"damage_bonus": 5.0},
			{&"damage_bonus": 13.0, &"range_multiplier": 1.2},
			{&"damage_bonus": 25.0},
		],
	},
	&"long": {
		&"sustained": [
			{&"range_multiplier": 1.2},
			{&"fire_rate_bonus_ms": 450.0},
			{&"fire_rate_bonus_ms": 250.0},
			{&"range_multiplier": 1.33, &"fire_rate_bonus_ms": 200.0},
		],
		&"burst": [
			{&"damage_bonus": 6.0},
			{&"damage_bonus": 8.0},
			{&"pierce_bonus": 5, &"damage_bonus": 9.0},
			{&"pierce_bonus": 10, &"damage_bonus": 38.0},
		],
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
		&"damage_bonus", &"fire_rate_bonus_ms", &"range_multiplier",
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
	assert_almost_eq(float(tier["effects"][&"damage_bonus"]), 9.0, 0.0001,
		"carries interim damage so the purchase is not inert while pierce is dormant")
	return true

func test_get_branch_returns_the_branch_definition() -> bool:
	var branch := Upgrades.get_branch(&"basic", &"sustained")
	assert_eq(branch["label"], "Barrage", "basic's sustained branch is Barrage")
	return true

# Pins every effect VALUE, not just the key vocabulary
# test_every_effect_key_is_recognised already covers. The keys catch a
# misspelling; they do not catch a magnitude. The whole-branch review changed
# six values by mutation - Cryo Rounds' 1500ms slow to 15ms, and five of six
# splash radii to a tenth of themselves - and all six passed the entire suite,
# because tests resolve towers almost only at tier 0 and tier 4 of one branch,
# and because strongest-wins hides any value a higher tier overrides.
#
# These numbers are a snapshot of data/upgrades.gd taken after Task 1's review
# had checked all thirty-two tiers against upstream by hand. Their job is the
# same as EXPECTED_COSTS': to be a second, independent statement of the table,
# so that changing it takes two deliberate edits rather than one slip.
#
# The type caveat at the top of this file applies here too: 1500 and 1500.0
# compare equal, so a value that became a float would pass.
func test_tier_effects_match_the_reference_table() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			var expected: Array = EXPECTED_EFFECTS[kind][branch]
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			assert_eq(tiers.size(), expected.size(), "%s/%s tier count" % [kind, branch])
			for i in tiers.size():
				var actual: Dictionary = tiers[i]["effects"]
				var want: Dictionary = expected[i]
				# Size as well as contents, so an effect ADDED to a tier fails
				# here rather than passing every key the table happens to name.
				assert_eq(actual.size(), want.size(),
					"%s/%s tier %d carries exactly %d effect(s)" % [kind, branch, i + 1, want.size()])
				for key in want:
					assert_true(actual.has(key),
						"%s/%s tier %d carries %s" % [kind, branch, i + 1, key])
					assert_eq(actual.get(key), want[key],
						"%s/%s tier %d %s" % [kind, branch, i + 1, key])
	return true

# Damage and fire rate are flat now, and the multiplier keys are gone from the
# resolver. A tier carrying one would be silently ignored, which is worse than
# a crash - so the table is checked rather than trusted.
func test_no_tier_carries_a_dead_multiplier_key() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				var effects: Dictionary = tier["effects"]
				assert_false(effects.has(&"damage_multiplier"),
					"%s/%s %s has no damage_multiplier" % [kind, branch, tier["label"]])
				assert_false(effects.has(&"fire_rate_multiplier"),
					"%s/%s %s has no fire_rate_multiplier" % [kind, branch, tier["label"]])
	return true

# --------------------------------------------------------------------------
# effect_summary
# --------------------------------------------------------------------------

func test_effect_summary_renders_flat_damage_and_fire_rate() -> bool:
	assert_eq(Upgrades.effect_summary({&"damage_bonus": 12.0}), "+12 damage",
		"flat damage reads as a plain addition")
	assert_eq(Upgrades.effect_summary({&"fire_rate_bonus_ms": 400.0}),
		"fires 0.4s faster", "a fire-rate bonus reads in seconds")
	return true

func test_effect_summary_joins_several_effects() -> bool:
	assert_eq(
		Upgrades.effect_summary({&"damage_bonus": 2.0, &"fire_rate_bonus_ms": 150.0}),
		"+2 damage · fires 0.15s faster",
		"effects join in a fixed order regardless of dictionary order")
	return true

func test_effect_summary_is_empty_for_no_effects() -> bool:
	assert_eq(Upgrades.effect_summary({}), "", "nothing to say about nothing")
	return true

# THE anti-drift test. A hand-written description drifts the first time a value
# is tuned, and this slice tuned all thirty-two of them. Generating the line
# means the number on screen is the number the tier applies - but only while
# every key the table uses is one the renderer knows.
func test_every_tier_renders_a_summary() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				var summary := Upgrades.effect_summary(tier["effects"])
				assert_true(summary.length() > 0,
					"%s/%s %s renders" % [kind, branch, tier["label"]])
				assert_false(summary.contains("?"),
					"%s/%s %s has no unrendered key" % [kind, branch, tier["label"]])
	return true
