extends TestCase

# One directory of variants per enemy kind. The sheet's rows are NOT animation
# frames - measured, not assumed: a real walk cycle's frame-to-frame difference
# varies with lag and dips as the cycle closes, while these rows are flat
# across every lag. So they are used as per-spawn variety instead, and an
# enemy picks one when it spawns.

const _KINDS := ["slime", "ogre", "bee"]
const _MARGIN_ALPHA_MAX := 8

## The exact yield of each row, measured. A floor would hide the thing most
## likely to go wrong here: the bat row's sprites overlap wing-to-wing and only
## three of its thirteen bats can be cut out cleanly, so the bake drops the
## spans that hold more than one. If that filter ever stops working, slime and
## ogre gain sprites and bee gains merged ones - a floor sees neither.
const _EXPECTED_VARIANTS := {"slime": 15, "ogre": 13, "bee": 3}

## No variant may be wider than this multiple of its kind's narrowest. Two
## enemies cut into one PNG is the failure this catches, and it is invisible to
## every other assertion in this file - a merged sprite is free-standing, has a
## clean margin, and differs from its siblings.
const _MAX_WIDTH_RATIO := 1.4

func _variant(kind: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/enemies/%s/variant_%d.png" % [kind, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _count(kind: String) -> int:
	var n := 0
	while FileAccess.file_exists(
			"res://assets/art/enemies/%s/variant_%d.png" % [kind, n]):
		n += 1
	return n

func test_every_kind_ships_the_variants_its_row_yields() -> bool:
	for kind in _KINDS:
		assert_eq(_count(kind), int(_EXPECTED_VARIANTS[kind]),
			"%s ships %d variants" % [kind, int(_EXPECTED_VARIANTS[kind])])
	return true

func test_variants_are_free_standing_with_a_clear_margin() -> bool:
	for kind in _KINDS:
		for i in _count(kind):
			var img := _variant(kind, i)
			assert_true(img != null, "%s/variant_%d decodes" % [kind, i])
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
				"%s/variant_%d edge peak %d" % [kind, i, peak])
	return true

func test_no_variant_holds_more_than_one_creature() -> bool:
	# The bat row's gap segmentation returns spans holding two, three and four
	# bats. They are dropped in the bake; this is the gate that says so.
	for kind in _KINDS:
		var widths := []
		for i in _count(kind):
			var img := _variant(kind, i)
			assert_true(img != null, "%s/variant_%d decodes" % [kind, i])
			if img == null:
				continue
			widths.append(img.get_width())
		assert_true(not widths.is_empty(), "%s has variants to measure" % kind)
		if widths.is_empty():
			continue
		var narrowest: int = widths[0]
		var widest: int = widths[0]
		for w in widths:
			narrowest = mini(narrowest, int(w))
			widest = maxi(widest, int(w))
		assert_true(float(widest) <= float(narrowest) * _MAX_WIDTH_RATIO,
			"%s's widest variant is %d against a narrowest of %d" % [kind, widest, narrowest])
	return true

func test_variants_of_a_kind_are_actually_different() -> bool:
	# A bake that wrote the same crop N times would pass everything above and
	# defeat the entire point of per-spawn variety.
	for kind in _KINDS:
		var a := _variant(kind, 0)
		var b := _variant(kind, 1)
		assert_true(a != null and b != null, "%s has two variants to compare" % kind)
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
		assert_true(differs, "%s's first two variants are not identical" % kind)
	return true

func test_the_three_kinds_are_different_creatures() -> bool:
	var sizes := {}
	for kind in _KINDS:
		var img := _variant(kind, 0)
		assert_true(img != null, "%s/variant_0 decodes" % kind)
		if img == null:
			continue
		sizes[kind] = img.get_size()
	assert_true(sizes["ogre"].y > sizes["bee"].y,
		"the ogre sprite is taller than the bat sprite")
	return true
