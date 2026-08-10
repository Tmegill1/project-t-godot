class_name Rng
extends RefCounted

## Seeded mulberry32, bit-exact with the JavaScript original.
##
## GDScript ints are 64-bit signed and JS bitwise operators are 32-bit, so
## every arithmetic step is masked back to 32 bits. The multiplications
## overflow int64 and wrap; that is fine and intended, because two's-complement
## wrapping preserves the low 32 bits, which is all the algorithm reads.
## Verified against the JS reference for seed 12345 to 17 decimal places.

const MASK := 0xFFFFFFFF

var _state: int

func _init(seed_value: int) -> void:
	_state = seed_value & MASK

## Next value in [0, 1).
func next() -> float:
	_state = (_state + 0x6d2b79f5) & MASK
	var t := _state
	t = ((t ^ (t >> 15)) * (t | 1)) & MASK
	t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & MASK))) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

## Integer in [lo, hi], both inclusive.
func int_range(lo: int, hi: int) -> int:
	if hi < lo:
		var swap := lo
		lo = hi
		hi = swap
	return lo + int(next() * float(hi - lo + 1))

## A uniformly chosen element. Returns null on an empty array.
func pick(items: Array):
	if items.is_empty():
		push_error("Rng.pick: cannot choose from an empty array")
		return null
	return items[int(next() * float(items.size()))]

## A shuffled copy. Fisher-Yates; does not mutate the input.
func shuffle(items: Array) -> Array:
	var out := items.duplicate()
	var i := out.size() - 1
	while i > 0:
		var j := int(next() * float(i + 1))
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
		i -= 1
	return out

## An independent generator seeded from this one's stream. Forking lets a
## subsystem draw freely without shifting anyone else's sequence.
func fork() -> Rng:
	return Rng.new(int(next() * 4294967296.0))
