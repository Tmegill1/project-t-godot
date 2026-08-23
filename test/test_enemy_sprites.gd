extends TestCase

# One walk cycle and one death sequence per enemy kind, cut from
# reference/illustrated-sheet/walk-and-death.png.
#
# This replaced a per-spawn variant system. The first sheet's enemy rows were
# fifteen different goblins rather than one goblin walking - measured twice,
# once by frame-lag autocorrelation and once by registering consecutive
# sprites on the head and finding the head moved MORE than the legs - so
# variety was all that art could offer. This sheet is the other way round.
#
# The bat's walk cycle is SEVEN frames where every other kind has eight. Its
# eighth frame is an orphaned wing with no body, which the bake drops on area
# rather than on index: hard-coding "skip frame 7" would silently discard a
# good frame if the sheet were regenerated.

const _KINDS := ["slime", "ogre", "bee"]
const _EXPECTED_WALK := {"slime": 8, "ogre": 8, "bee": 7}
const _EXPECTED_DEATH := {"slime": 4, "ogre": 4, "bee": 4}
const _MARGIN_ALPHA_MAX := 8

func _frame(kind: String, action: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/enemies/%s/%s_%d.png" % [kind, action, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _count(kind: String, action: String) -> int:
	var n := 0
	while FileAccess.file_exists(
			"res://assets/art/enemies/%s/%s_%d.png" % [kind, action, n]):
		n += 1
	return n

# This is also the gate on the bake's walk/death boundary. The bake splits a
# row on each frame's ORIGINAL index, so a dropped frame shortens whichever
# half it came out of - which means a row that loses a death frame reports
# 8 walk / 3 death and fails here. An earlier rule assumed any drop came from
# the walk half; under it that same row would have reported 7 / 4, stayed
# self-consistent, and silently shipped a walking pose as death_0.
func test_every_kind_ships_the_frames_its_row_yields() -> bool:
	for kind in _KINDS:
		assert_eq(_count(kind, "walk"), int(_EXPECTED_WALK[kind]),
			"%s ships %d walk frames" % [kind, int(_EXPECTED_WALK[kind])])
		assert_eq(_count(kind, "death"), int(_EXPECTED_DEATH[kind]),
			"%s ships %d death frames" % [kind, int(_EXPECTED_DEATH[kind])])
	return true

func test_the_variant_files_are_gone() -> bool:
	# Not merely unused - removed. A variant left on disk beside a walk cycle
	# is the next reader's wrong turn.
	for kind in _KINDS:
		assert_false(FileAccess.file_exists(
			"res://assets/art/enemies/%s/variant_0.png" % kind),
			"%s ships no variants any more" % kind)
	return true

func test_every_frame_is_free_standing_with_a_clear_margin() -> bool:
	for kind in _KINDS:
		for action in ["walk", "death"]:
			for i in _count(kind, action):
				var img := _frame(kind, action, i)
				assert_true(img != null, "%s/%s_%d decodes" % [kind, action, i])
				if img == null:
					continue
				var w := img.get_width()
				var h := img.get_height()
				var peak := 0
				for y in h:
					peak = maxi(peak, maxi(
						int(round(img.get_pixel(0, y).a * 255.0)),
						int(round(img.get_pixel(w - 1, y).a * 255.0))))
				for x in w:
					peak = maxi(peak, maxi(
						int(round(img.get_pixel(x, 0).a * 255.0)),
						int(round(img.get_pixel(x, h - 1).a * 255.0))))
				assert_true(peak <= _MARGIN_ALPHA_MAX,
					"%s/%s_%d edge peak %d" % [kind, action, i, peak])
	return true

func test_no_frame_is_a_fragment_of_another() -> bool:
	# The gate for the bat's orphaned wing, and for any future frame the
	# generator drops a body out of. A fragment is free-standing and cleanly
	# trimmed, so nothing else here can see it - only its area gives it away.
	for kind in _KINDS:
		for action in ["walk", "death"]:
			var areas := []
			for i in _count(kind, action):
				var img := _frame(kind, action, i)
				assert_true(img != null, "%s/%s_%d decodes" % [kind, action, i])
				if img == null:
					continue
				var opaque := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 8.0 / 255.0:
							opaque += 1
				areas.append(opaque)
			assert_true(not areas.is_empty(), "%s has %s frames" % [kind, action])
			if areas.is_empty():
				continue
			var largest := 0
			for a in areas:
				largest = maxi(largest, int(a))
			for i in areas.size():
				assert_true(float(areas[i]) >= float(largest) * 0.45,
					"%s/%s_%d covers %d against the sequence's %d - a fragment would not"
						% [kind, action, i, int(areas[i]), largest])
	return true

func test_consecutive_walk_frames_differ() -> bool:
	# A cycle that wrote the same crop N times would pass everything above.
	for kind in _KINDS:
		for i in _count(kind, "walk") - 1:
			var a := _frame(kind, "walk", i)
			var b := _frame(kind, "walk", i + 1)
			assert_true(a != null and b != null,
				"%s walk %d and %d decode" % [kind, i, i + 1])
			if a == null or b == null:
				continue
			var differs := a.get_size() != b.get_size()
			if not differs:
				for y in range(0, a.get_height(), 3):
					for x in range(0, a.get_width(), 3):
						if a.get_pixel(x, y) != b.get_pixel(x, y):
							differs = true
							break
					if differs:
						break
			assert_true(differs, "%s walk frames %d and %d differ" % [kind, i, i + 1])
	return true

func test_the_death_sequence_ends_lower_than_it_starts() -> bool:
	# Every one of these creatures falls over. The last death frame is drawn
	# flat, so it is markedly wider than tall relative to the first - which is
	# the cheapest true statement about a death animation, and enough to catch
	# a sequence baked in reverse or one that never left its feet.
	for kind in _KINDS:
		var n := _count(kind, "death")
		assert_true(n >= 2, "%s has a death sequence to compare" % kind)
		if n < 2:
			continue
		var first := _frame(kind, "death", 0)
		var last := _frame(kind, "death", n - 1)
		assert_true(first != null and last != null, "%s death frames decode" % kind)
		if first == null or last == null:
			continue
		var first_ratio := float(first.get_width()) / float(first.get_height())
		var last_ratio := float(last.get_width()) / float(last.get_height())
		assert_true(last_ratio > first_ratio,
			"%s ends its death flatter than it started (%.2f against %.2f)"
				% [kind, last_ratio, first_ratio])
	return true
