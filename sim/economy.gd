class_name EconomySim

## Currency and pricing arithmetic. Named EconomySim because Economy is the
## data table of constants.

## Price of the next tower of a kind. Escalation is per kind, and exists to
## stop the board becoming twenty copies of one tower. Matches escalatedCost's
## `Math.max(0, owned)` clamp in economy.ts — a negative count (not producible
## by anything in this slice today, but not this function's job to rule out)
## must never push the price below base.
static func tower_price(kind: StringName, owned_of_kind: int) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	return int(def["cost"]) + maxi(0, owned_of_kind) * int(def["cost_escalation"])

## Half of everything sunk into a tower comes back on sale, rounded down.
static func sell_refund(paid: int) -> int:
	return int(floor(float(paid) * Economy.SELL_REFUND_FRACTION))

static func can_afford(gold: int, price: int) -> bool:
	return gold >= price

## Gold paid for a kill, after the killing tower's gold effects.
##
## The multiplier applies first and the flat bonus is added after, so a flat
## bonus is never itself multiplied - which is what the tier descriptions say.
## Rounds to nearest rather than flooring, matching the reference's kill payout
## (`Math.round(reward * goldMultiplier) + bonusGold`); gold is an integer, and
## a half-gold difference the HUD cannot show would drift from the banked
## total. `source` is the dictionary a tower emits with its shot, so a kill is
## credited to the tower that fired - including a splash kill, which reuses it.
## Reading with defaults keeps this correct for a source carrying no gold keys
## at all.
static func kill_reward(base_reward: int, source: Dictionary) -> int:
	var multiplier := float(source.get(&"gold_multiplier", 1.0))
	var flat := int(source.get(&"bonus_gold_per_kill", 0))
	return maxi(0, roundi(float(maxi(0, base_reward)) * multiplier) + flat)

## How many of a kind this map allows.
static func tower_limit(kind: StringName, map_name: StringName) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	var limit := int(def["base_limit"])
	if map_name != Maps.FIRST:
		limit += int(def["limit_bonus_map2"])
	return limit
