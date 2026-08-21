extends TestCase

# assets/towers.png is consumed through Tower.frame_region on a 5-column grid
# of 96px frames, by both the placed tower and the build panel's icons. The
# illustrated swap changes the art inside those frames and nothing else, which
# is why no tower code changed with it.
#
# Frames 3, 4, 14 and 15 are unreferenced by any tower kind and stay blank.

const _ATLAS := "res://assets/towers.png"
const _COLUMNS := 5
const _FRAME := 96
const _UNUSED_FRAMES := [3, 4, 14, 15]

func _atlas() -> Image:
	var bytes := FileAccess.get_file_as_bytes(_ATLAS)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _opaque_pixels(img: Image, frame: int) -> int:
	var ox := (frame % _COLUMNS) * _FRAME
	var oy := (frame / _COLUMNS) * _FRAME
	var count := 0
	for y in range(0, _FRAME, 2):
		for x in range(0, _FRAME, 2):
			if img.get_pixel(ox + x, oy + y).a > 8.0 / 255.0:
				count += 1
	return count

func test_the_atlas_keeps_the_geometry_tower_gd_assumes() -> bool:
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	assert_eq(img.get_width(), _COLUMNS * _FRAME, "atlas width is 5 frames")
	assert_eq(img.get_height(), 4 * _FRAME, "atlas height is 4 frames")
	assert_eq(Tower.SHEET_COLUMNS, _COLUMNS, "Tower.SHEET_COLUMNS still 5")
	assert_eq(Tower.FRAME_SIZE, _FRAME, "Tower.FRAME_SIZE still 96")
	return true

func test_every_frame_a_tower_kind_names_carries_art() -> bool:
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.get_def(kind)
		for frame in def["upgrade_frames"]:
			assert_true(_opaque_pixels(img, int(frame)) > 0,
				"%s frame %d carries art" % [kind, int(frame)])
	return true

func test_the_unreferenced_frames_are_blank() -> bool:
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for frame in _UNUSED_FRAMES:
		assert_eq(_opaque_pixels(img, int(frame)), 0, "unused frame %d is blank" % int(frame))
	return true

func test_a_kind_s_levels_grow_across_its_upgrade_frames() -> bool:
	# The upgrade read this swap buys: four hand-drawn states per tower, each
	# more substantial than the last. A bake that wrote the same level into
	# every frame would pass every other assertion here.
	#
	# First against last, not each against the one before it: a level's
	# silhouette can widen and shorten between two steps (the Mage's crystals
	# spread further at L3 than they do at L4) without the level being any
	# less of an upgrade.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var frames: Array = Towers.get_def(kind)["upgrade_frames"]
		var first := _opaque_pixels(img, int(frames[0]))
		var last := _opaque_pixels(img, int(frames[frames.size() - 1]))
		assert_true(last > first,
			"%s's top level covers more than its first (%d vs %d)" % [kind, last, first])
	return true

func test_every_referenced_frame_keeps_a_transparent_margin() -> bool:
	# Art running to a frame edge bleeds into the neighbouring frame when the
	# AtlasTexture samples it.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n := int(frame)
			var ox := (n % _COLUMNS) * _FRAME
			var oy := (n / _COLUMNS) * _FRAME
			var peak := 0.0
			for i in _FRAME:
				peak = maxf(peak, img.get_pixel(ox + i, oy).a)
				peak = maxf(peak, img.get_pixel(ox + i, oy + _FRAME - 1).a)
				peak = maxf(peak, img.get_pixel(ox, oy + i).a)
				peak = maxf(peak, img.get_pixel(ox + _FRAME - 1, oy + i).a)
			assert_true(peak <= 8.0 / 255.0,
				"%s frame %d keeps a transparent margin" % [kind, n])
	return true

func test_no_referenced_frame_carries_a_detached_fragment() -> bool:
	# The gate for everything the cut can drag in with the tower: the "LVL 4"
	# caption printed above it, or a sliver of the neighbouring level. Both
	# arrive separated from the tower by a band of transparency, so a frame
	# whose content spans an empty row or column has caught something.
	#
	# Every tower on the sheet is solid between its extremes - measured, not
	# assumed: all sixteen come out with zero interior empty rows and zero
	# interior empty columns. The flags and floating crystals stay attached to
	# their poles and rings.
	#
	# Full stride, not every other pixel: a one-row gap is exactly what a
	# caption leaves behind, and a stride of two can step over it.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n := int(frame)
			var ox := (n % _COLUMNS) * _FRAME
			var oy := (n / _COLUMNS) * _FRAME
			var rows := []
			var cols := []
			rows.resize(_FRAME)
			cols.resize(_FRAME)
			rows.fill(false)
			cols.fill(false)
			for y in _FRAME:
				for x in _FRAME:
					if img.get_pixel(ox + x, oy + y).a > 8.0 / 255.0:
						rows[y] = true
						cols[x] = true
			assert_eq(_interior_gaps(rows), 0,
				"%s frame %d spans no empty row" % [kind, n])
			assert_eq(_interior_gaps(cols), 0,
				"%s frame %d spans no empty column" % [kind, n])
	return true

## Empty entries lying between the first and last true entry.
func _interior_gaps(occupied: Array) -> int:
	var first := -1
	var last := -1
	for i in occupied.size():
		if bool(occupied[i]):
			if first < 0:
				first = i
			last = i
	if first < 0:
		return 0
	var gaps := 0
	for i in range(first, last + 1):
		if not bool(occupied[i]):
			gaps += 1
	return gaps
