class_name Aura

## The goblin shaman's shield aura: it grants shield charges to the enemies
## around it, which makes it a priority target. Kill the escort and the wave
## dies normally; ignore it and everything takes an extra hit.
##
## Pure, like sim/slow.gd beside it. It REPORTS which enemies should gain a
## charge and never applies anything - the caller owns its own enemy state,
## and a rule that mutated the live board's nodes could not also be run by the
## harness against its plain dictionaries. Both callers run this, per the
## standing rule that one question gets one answer in sim/.

## How far the aura reaches.
##
## Comfortably wider than a creature but far short of a tower's range (the
## shortest is Magic's 80), so a shaman shields the column it walks in rather
## than the whole board, and killing it is a positional decision.
const RADIUS := 90.0

## How often it fires. Not every tick: an aura that refilled a charge the
## instant a tower stripped it would not be a buff, it would be
## invulnerability.
const COOLDOWN_MS := 2500.0

## The most charges the aura will stack on one enemy. Without a cap, a slow
## wave walking beside a shaman arrives at the towers unkillable.
const MAX_GRANTED_CHARGES := 2

## Ids of the enemies that should gain a shield charge this tick.
##
## `elapsed_ms` is the caller's own wave clock, so every shaman on the board
## shares one beat rather than each tracking its own. That is what keeps this
## function stateless, and therefore reproducible: the same clock always gives
## the same answer, which is what the harness's determinism rests on.
static func grant(shamans: Array, enemies: Array, elapsed_ms: float) -> Array:
	var out: Array = []
	if shamans.is_empty():
		return out
	if not _on_the_beat(elapsed_ms):
		return out

	for enemy in enemies:
		if not enemy.get("alive", true) or enemy.get("dying", false):
			continue
		# A shaman carries its own shield from the table. Topping one up here -
		# its own or another's - would make a shaman pair unkillable by the
		# rapid-fire build that is supposed to answer them.
		if enemy.get("kind", &"") == &"shaman":
			continue
		if int(enemy.get("shield", 0)) >= MAX_GRANTED_CHARGES:
			continue
		for shaman in shamans:
			if shaman.get("id") == enemy.get("id"):
				continue
			# Inclusive at the boundary, matching Damage.in_splash: something
			# exactly at the radius IS covered.
			if Vector2(shaman["position"]).distance_to(enemy["position"]) <= RADIUS:
				out.append(enemy["id"])
				# One grant per enemy per beat, however many shamans cover it.
				break
	return out

## Whether this tick lands on the aura's beat.
##
## Derived from the caller's clock rather than a stored timer, so `grant` stays
## stateless. The window is one tick wide rather than an exact equality: the
## board's clock advances in ~16.67ms steps that never land on a round number,
## so testing `fposmod(...) == 0` would miss the beat forever.
static func _on_the_beat(elapsed_ms: float) -> bool:
	if elapsed_ms < 0.0:
		return false
	if elapsed_ms == 0.0:
		return true
	return fposmod(elapsed_ms, COOLDOWN_MS) < _BEAT_WINDOW_MS

## How wide the beat window is. Slightly over one 60Hz tick, so a clock
## stepping by 16.67ms cannot step over the beat without landing in it.
const _BEAT_WINDOW_MS := 17.0
