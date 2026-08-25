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

## Gold paid for a kill, after the wave's gold modifier and the killing
## tower's gold effects.
##
## Order is load-bearing and tested. The WAVE modifier scales the base reward
## first, then the tower's multiplier applies to that scaled figure, then the
## flat bonus is added last and is never itself multiplied - which is what the
## tier descriptions say. So the Bounty Hunter branch multiplies what the wave
## actually pays rather than an unscaled number, and a flat bonus keeps its
## full value however deep the wave is.
##
## Rounds to nearest rather than flooring, matching the reference's kill payout
## (`Math.round(reward * goldMultiplier) + bonusGold`); gold is an integer, and
## a half-gold difference the HUD cannot show would drift from the banked
## total. `source` is the dictionary a tower emits with its shot, so a kill is
## credited to the tower that fired - including a splash kill, which reuses it.
## Reading with defaults keeps this correct for a source carrying no gold keys
## at all.
##
## `gold_modifier` defaults to 1.0 so a caller with no wave in hand reads the
## unscaled reward, which is what keeps every pre-existing two-argument call
## site correct.
static func kill_reward(base_reward: int, source: Dictionary,
		gold_modifier: float = 1.0) -> int:
	var scaled := float(maxi(0, base_reward)) * gold_modifier
	var multiplier := float(source.get(&"gold_multiplier", 1.0))
	var flat := int(source.get(&"bonus_gold_per_kill", 0))
	return maxi(0, roundi(scaled * multiplier) + flat)

## How many of a kind this map allows.
static func tower_limit(kind: StringName, map_name: StringName) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	var limit := int(def["base_limit"])
	if map_name != Maps.FIRST:
		limit += int(def["limit_bonus_map2"])
	return limit

# --- Wave economy ---------------------------------------------------------

## Gold paid for clearing a wave, itemised.
##
## Itemised rather than totalled because the UI must be able to tell the
## player WHY they were paid, or the incentives stay invisible.
##
## DIVERGENCE from the reference, deliberate: upstream's waveClearReward also
## folds interest into this call, and computes interestOn twice in one
## function body. Interest is its own function here, called once by the board -
## which is where the banked balance already lives. Same result, one
## responsibility each.
static func wave_clear_bonus(wave: int, clear_ms: float) -> Dictionary:
	var base := int(Economy.WAVE_CLEAR["base_bonus"]) \
		+ maxi(0, wave) * int(Economy.WAVE_CLEAR["bonus_per_wave"])

	var fast := float(Economy.WAVE_CLEAR["fast_clear_ms"])
	var slow := float(Economy.WAVE_CLEAR["slow_clear_ms"])
	# maxf(1.0, ...) so a table where the two thresholds are equal divides by
	# one rather than by zero.
	var span := maxf(1.0, slow - fast)
	var slowness := (maxf(0.0, clear_ms) - fast) / span
	var speed := roundi(float(Economy.WAVE_CLEAR["max_speed_bonus"])
		* clampf(1.0 - slowness, 0.0, 1.0))

	return {"base": base, "speed": speed}

## Interest on banked gold, capped, floored, and only above a minimum.
static func interest_on(banked: int) -> int:
	if banked < int(Economy.INTEREST["minimum_balance"]):
		return 0
	return mini(int(Economy.INTEREST["max_per_wave"]),
		int(floor(float(banked) * float(Economy.INTEREST["rate_per_wave"]))))

## Gold for starting a wave early, proportional to the prep time given up.
##
## Whole seconds only, and capped, so rushing cannot dominate the wave-clear
## bonus and reduce the game to a race.
static func call_early_bonus(remaining_ms: float) -> int:
	var window := float(Economy.CALL_EARLY["prep_duration_ms"])
	var seconds := int(floor(clampf(remaining_ms, 0.0, window) / 1000.0))
	return mini(int(Economy.CALL_EARLY["max_bonus"]),
		seconds * int(Economy.CALL_EARLY["gold_per_second"]))
