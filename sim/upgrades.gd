class_name UpgradesSim

## Upgrade rules: what may be bought, what it costs, what a tower becomes.
##
## The cross-path rule is the whole point. A tower may take one branch deep
## only while the other stays shallow, so every tower is a commitment rather
## than a checklist. Without it, gold is the only constraint and every tower
## converges on the same fully-upgraded shape.
##
## Pure: no engine references, no mutation of arguments.

const MAX_TIER := 4

## Highest tier the *other* branch may sit at while one branch goes deep.
const CROSS_PATH_CAP := 2

## Penetration every tower gains per tier bought, in either branch.
##
## Owner's rule: levelling a tower should make it better at getting THROUGH,
## not only at hitting harder. With the damage floor in sim/damage.gd it is
## the second guarantee that no tower is ever walled by late-game armour - the
## Magic tower is the case it exists for, since neither of its branches
## mentions pierce and it would otherwise rely on the floor alone.
##
## The explicit pierce_bonus tiers stack ON TOP of this, so Long Range stays
## the pierce specialist rather than being levelled down to everyone else.
## 2, not 1. Measured: at 1, a fully-committed Magic tower reaches 6 pierce
## against a wave-20 ogre's effective 14.4 (9 armour x ARMOR_VS_MAGIC), so the
## damage floor was doing all the work and the penetration was decorative -
## the "not walled, but not a choice either" outcome the spec warns about. At
## 2 it reaches 12, which clears the floor and makes levelling genuinely buy
## its way through. Long Range still ends far ahead, because its explicit
## pierce tiers add 15 on top.
const PIERCE_PER_TIER := 2

static func empty_tiers() -> Dictionary:
	return {&"sustained": 0, &"burst": 0}

static func _other_branch(branch: StringName) -> StringName:
	return &"burst" if branch == &"sustained" else &"sustained"

## Whether the next tier on a branch may be bought. Ignores affordability.
static func can_upgrade(tiers: Dictionary, branch: StringName) -> bool:
	if not tiers.has(branch):
		return false
	var next: int = int(tiers[branch]) + 1
	if next > MAX_TIER:
		return false
	# Going past the cap commits this tower; the other branch must already be
	# shallow, and stays locked there afterwards.
	if next > CROSS_PATH_CAP and int(tiers[_other_branch(branch)]) > CROSS_PATH_CAP:
		return false
	return true

## Buys the next tier. Returns a new dictionary; never mutates the argument.
##
## The reference throws on an illegal buy, on the reasoning that a call which
## should have been gated is a bug rather than a no-op. GDScript has no
## exceptions and assert() compiles out of release builds, so this pushes an
## error and returns the tiers unchanged: loud where it matters, inert in a
## shipped build. Callers gate on can_upgrade first.
static func with_upgrade(tiers: Dictionary, branch: StringName) -> Dictionary:
	if not can_upgrade(tiers, branch):
		push_error("Illegal upgrade: %s from tier %s" % [branch, tiers.get(branch, "?")])
		return tiers.duplicate()
	var next := tiers.duplicate()
	next[branch] = int(tiers[branch]) + 1
	return next

## Price of moving a branch from `current_tier` to the next. Zero when maxed.
static func upgrade_cost(kind: StringName, branch: StringName, current_tier: int) -> int:
	if current_tier >= MAX_TIER or current_tier < 0:
		return 0
	return int(Upgrades.DEFS[kind][branch]["tiers"][current_tier]["cost"])

## Total gold sunk into a tower's upgrades, for sell-value calculations.
## Tiers bought across BOTH branches. Distinct from total_invested, which
## sums their gold cost - this counts the steps, because penetration is a
## reward for commitment rather than for spending.
static func total_tiers(tiers: Dictionary) -> int:
	var total := 0
	for branch in Upgrades.BRANCHES:
		total += int(tiers.get(branch, 0))
	return total

static func total_invested(kind: StringName, tiers: Dictionary) -> int:
	var total := 0
	for branch in Upgrades.BRANCHES:
		for tier in range(int(tiers.get(branch, 0))):
			total += upgrade_cost(kind, branch, tier)
	return total

## How many distinct looks a tower has, from unupgraded to fully committed.
##
## Four, not seven. A tower can hold six tiers in total, but six silhouettes
## are not readable at tile size - and the useful signal is "how much is
## invested here", not the exact tier.
const VISUAL_TIERS := 4

## Which look a tower should be wearing, from its purchased tiers. Driven by
## total investment across both branches, so a tower taken deep down one path
## and one taken evenly both look like what they are: expensive.
static func visual_tier(tiers: Dictionary) -> int:
	var total := maxi(0, int(tiers.get(&"sustained", 0))) + maxi(0, int(tiers.get(&"burst", 0)))
	# 0 -> 0, 1-2 -> 1, 3-4 -> 2, 5-6 -> 3.
	return mini(VISUAL_TIERS - 1, int(ceil(float(total) / 2.0)))

## The sprite frame a tower should be showing.
static func sprite_frame_for(kind: StringName, tiers: Dictionary) -> int:
	var frames: Array = Towers.DEFS[kind]["upgrade_frames"]
	var tier := mini(visual_tier(tiers), frames.size() - 1)
	return int(frames[tier])

## A tower's live combat stats after upgrades.
##
## Multipliers compose, flat bonuses add, and radii, slows and gold take the
## strongest value rather than stacking - otherwise tier 4's big splash would
## be added to tier 2's small one and the numbers would drift from what the
## tier text says.
static func resolve_tower_stats(kind: StringName, tiers: Dictionary) -> Dictionary:
	var base: Dictionary = Towers.DEFS[kind]
	var stats := {
		"damage": float(base["damage"]),
		"fire_rate": float(base["fire_rate"]),
		"range": float(base["range"]),
		# Every tier bought grants penetration, in either branch. The explicit
		# pierce_bonus tiers below add to this rather than replacing it.
		"pierce": int(base["pierce"]) + total_tiers(tiers) * PIERCE_PER_TIER,
		"splash_radius": float(base["base_splash_radius"]),
		"detection": bool(base["detection"]),
		"slow_factor": 1.0,
		"slow_duration_ms": 0.0,
		"gold_multiplier": 1.0,
		"bonus_gold_per_kill": 0,
	}

	for branch in Upgrades.BRANCHES:
		var definition: Dictionary = Upgrades.DEFS[kind][branch]
		for tier in range(int(tiers.get(branch, 0))):
			var effects: Dictionary = definition["tiers"][tier]["effects"]

			if effects.has(&"damage_multiplier"):
				stats["damage"] *= float(effects[&"damage_multiplier"])
			if effects.has(&"fire_rate_multiplier"):
				stats["fire_rate"] *= float(effects[&"fire_rate_multiplier"])
			if effects.has(&"range_multiplier"):
				stats["range"] *= float(effects[&"range_multiplier"])
			if effects.has(&"pierce_bonus"):
				stats["pierce"] += int(effects[&"pierce_bonus"])
			if effects.has(&"splash_radius"):
				stats["splash_radius"] = maxf(stats["splash_radius"], float(effects[&"splash_radius"]))
			if effects.has(&"detection") and bool(effects[&"detection"]):
				stats["detection"] = true
			if effects.has(&"gold_multiplier"):
				stats["gold_multiplier"] = maxf(stats["gold_multiplier"], float(effects[&"gold_multiplier"]))
			if effects.has(&"bonus_gold_per_kill"):
				stats["bonus_gold_per_kill"] = maxi(
					int(stats["bonus_gold_per_kill"]), int(effects[&"bonus_gold_per_kill"]))
			# Lower is stronger, and the duration travels with the factor that won.
			if effects.has(&"slow_factor") and float(effects[&"slow_factor"]) < stats["slow_factor"]:
				stats["slow_factor"] = float(effects[&"slow_factor"])
				stats["slow_duration_ms"] = float(effects.get(&"slow_duration_ms", stats["slow_duration_ms"]))

	stats["damage"] = round(stats["damage"])
	stats["fire_rate"] = round(stats["fire_rate"])
	stats["range"] = round(stats["range"])
	return stats
