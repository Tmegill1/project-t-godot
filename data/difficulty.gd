class_name Difficulty

## Difficulty tiers. Pure data, like the rest of data/.
##
## Difficulty is a PARAMETER in this project, never a global. Waves and the
## harness take a tier argument; nothing reads a mutable singleton. That is
## what keeps sim/ pure and keeps Harness.run_wave's guarantee - same input,
## same result - which is the property every balance claim here rests on.
##
## Normal is the exact identity transform. Every measured number in this
## project describes Normal, so the existing suite doubles as the regression
## net for this file: if a Normal multiplier drifts, something else fails.

const NORMAL := &"normal"
const HARD := &"hard"
const NIGHTMARE := &"nightmare"

## Easiest first. Task 2's monotonicity test walks this in order.
const ORDER: Array[StringName] = [NORMAL, HARD, NIGHTMARE]

## The multiplier keys, as distinct from starting_lives (an int) and label
## (a string). Tests iterate this rather than restating the list.
const KEYS: Array[StringName] = [
	&"count_multiplier",
	&"interval_multiplier",
	&"health_multiplier",
	&"speed_multiplier",
	&"gold_multiplier",
]

## Which lever attacks what. RE-MEASURED 2026-08-30, and the first reading was
## wrong in a way worth recording rather than quietly overwriting.
##
## The original table called interval_multiplier "the sharpest lever available"
## and health "proven weak alone", reasoning from an earlier finding that board
## COVERAGE binds rather than hit points. Against a full twelve-tower board that
## is backwards. Count and interval both raise enemy DENSITY, and the sustained
## upgrade branch grants splash - 45px, then 75px - whose value scales with
## density. So the two levers picked to attack coverage are exactly the ones a
## splash build answers best, and eleven of the sixteen legal maxed boards shut
## the old Nightmare row out completely.
##
##   health_multiplier    hit points, and the lever that actually bites. Splash
##                        kills a cluster in one hit however many are in it;
##                        what it cannot do is kill something twice.
##   speed_multiplier     time under fire, and a THRESHOLD rather than a dial.
##                        Below 1.40 the strongest legal board leaks nothing at
##                        all, at any health up to 4.0. At 1.40 it starts to
##                        bleed. Less time in range is the same as less range,
##                        and no upgrade branch answers it.
##   count_multiplier     enemies per wave. Held at 1.0 deliberately: raising it
##                        WIDENS the gap between a splash build and one without,
##                        punishing the weaker build and feeding the stronger.
##   interval_multiplier  spawn spacing, so concurrency. Held at 1.0 for the
##                        same reason. Both are left in the table because they
##                        are the right levers for a mid-run board and the wrong
##                        ones for a completed board, and a later tier may want
##                        them back.
##   gold_multiplier      the board a player can afford. Indirect, strong.
##   starting_lives       forgiveness. The only lever a player feels at once.
##
## SMALLER is harsher for interval_multiplier and gold_multiplier. Larger is
## harsher for the other three. The monotonicity test encodes both directions.
const DEFS := {
	&"normal": {
		"label": "Normal",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"starting_lives": Economy.STARTING_LIVES,
	},
	## Measured 2026-08-30 against the STRONGEST legal fully-upgraded board, not
	## against one arbitrary build. The cross-path rule allows exactly two maxed
	## splits per tower, a board picks one per kind, so there are sixteen legal
	## maxed boards; test_balance_tuning.gd now walks all of them.
	##
	## Lives lost across a whole run, strongest board against weakest:
	##
	##   count/interval/health/speed   strongest        weakest
	##   1.40 0.60 1.40 1.15           0 - SHUT OUT          46
	##   1.00 1.00 3.50 1.30           0 - SHUT OUT         146
	##   1.00 1.00 4.00 1.35           0 - SHUT OUT         246
	##   1.00 1.00 4.00 1.40 (Hard)             3           258
	##   1.00 1.00 4.50 1.40 (Nightmare)        9           336
	##   1.00 1.00 5.00 1.40                   27           441
	##
	## The spread between best and worst build is two orders of magnitude at
	## every row, and no tier value closes it. That is a TOWER balance problem -
	## the sustained branch dominates the burst branch against late waves - which
	## the selector revealed rather than caused. It is invisible on Normal
	## because every build shuts Normal out.
	&"hard": {
		## The full board loses 3 of its 15 lives, on wave 20, and finishes with
		## 12: real lives late without ending the run.
		"label": "Hard",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 4.0,
		"speed_multiplier": 1.40,
		"gold_multiplier": 0.90,
		"starting_lives": 15,
	},
	&"nightmare": {
		## The strongest legal board loses 9 of its 12 lives and survives with 3.
		## Beatable, but only by the best build there is - and every board that
		## leaves a tower on the burst branch loses badly.
		"label": "Nightmare",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 4.5,
		"speed_multiplier": 1.40,
		"gold_multiplier": 0.85,
		"starting_lives": 12,
	},
}

static func get_def(tier: StringName) -> Dictionary:
	return DEFS[tier]

static func multiplier(tier: StringName, key: StringName) -> float:
	return float(DEFS[tier][key])

static func starting_lives(tier: StringName) -> int:
	return int(DEFS[tier]["starting_lives"])

static func label(tier: StringName) -> String:
	return String(DEFS[tier]["label"])

## Whether a tier name is one this table knows. Callers that read a tier from
## outside the table - a saved run, a menu, a harness config - use this rather
## than indexing DEFS and crashing on a typo.
static func is_valid(tier: StringName) -> bool:
	return DEFS.has(tier)
