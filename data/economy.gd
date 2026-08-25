class_name Economy

## Every tunable economy number, in one place. Nothing here contains rules -
## the arithmetic lives in sim/economy.gd.
##
## Tower budgets and starting gold live per map, in data/maps.gd, so a new map
## brings its own rather than needing an entry here as well. They remain the
## strongest difficulty lever in the game: a tighter board demands choices,
## where harder monsters only demand more damage.
##
## Every number here is ported from the reference and is an unplaytested
## placeholder. The one measured number in the economy is the gold decay in
## data/waves.gd - see the spec's section 4.6.

const STARTING_LIVES := 20
const SELL_REFUND_FRACTION := 0.5

## Paid for clearing a wave. Two parts, deliberately: a flat amount so
## clearing always pays, and a speed component so a defence that KILLS beats
## one that merely survives.
const WAVE_CLEAR := {
	"base_bonus": 20,
	"bonus_per_wave": 5,
	## A wave cleared at or under this pays the full speed bonus.
	"fast_clear_ms": 20000.0,
	## One taking this long or longer pays none.
	"slow_clear_ms": 60000.0,
	"max_speed_bonus": 40,
}

## How long the player gets between waves before the next starts on its own,
## and what giving that time up is worth.
const CALL_EARLY := {
	"prep_duration_ms": 20000.0,
	"gold_per_second": 3,
	## Ceiling on a single payout, so the reward cannot dwarf the wave-clear
	## bonus and turn the game into a rush simulator.
	"max_bonus": 45,
}

## Interest on banked gold, paid at each wave clear.
const INTEREST := {
	"rate_per_wave": 0.05,
	## The cap is load-bearing. Uncapped compounding makes hoarding strictly
	## better than building, which is the opposite of a tower defence.
	"max_per_wave": 30,
	## Balance below which no interest is paid, so it never trickles.
	"minimum_balance": 50,
}
