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

## How many of a kind this map allows.
static func tower_limit(kind: StringName, map_name: StringName) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	var limit := int(def["base_limit"])
	if map_name != Maps.FIRST:
		limit += int(def["limit_bonus_map2"])
	return limit
