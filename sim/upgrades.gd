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
static func total_invested(kind: StringName, tiers: Dictionary) -> int:
	var total := 0
	for branch in Upgrades.BRANCHES:
		for tier in range(int(tiers.get(branch, 0))):
			total += upgrade_cost(kind, branch, tier)
	return total
