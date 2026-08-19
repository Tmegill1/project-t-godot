extends TestCase

# assets/towers.png is consumed through Tower.frame_region on a 5-column grid
# of 96px frames, by both the placed tower and the build panel's button icons.
# This file pins the geometry that arithmetic assumes, and checks that every
# frame data/towers.gd actually names carries art.
#
# Frames 3, 4, 14 and 15 are unreferenced by any tower kind and are
# deliberately blank - asserting they are empty is what keeps a future re-bake
# from quietly relying on them without adding them to a tower's upgrade path.

const _ATLAS := "res://assets/towers.png"
const _COLUMNS := 5
const _FRAME := 96
const _UNUSED_FRAMES := [3, 4, 14, 15]

func _atlas_image() -> Image:
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
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	assert_eq(img.get_width(), _COLUMNS * _FRAME, "atlas width is 5 frames")
	assert_eq(img.get_height(), 4 * _FRAME, "atlas height is 4 frames")
	assert_eq(Tower.SHEET_COLUMNS, _COLUMNS, "Tower.SHEET_COLUMNS still 5")
	assert_eq(Tower.FRAME_SIZE, _FRAME, "Tower.FRAME_SIZE still 96")
	return true

func test_every_frame_a_tower_kind_names_carries_art() -> bool:
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.get_def(kind)
		for frame in def["upgrade_frames"]:
			var n: int = frame
			assert_true(_opaque_pixels(img, n) > 0,
				"%s frame %d carries art" % [kind, n])
		var base: int = def["sprite_frame"]
		assert_true(_opaque_pixels(img, base) > 0,
			"%s base frame %d carries art" % [kind, base])
	return true

func test_the_unreferenced_frames_are_blank() -> bool:
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for frame in _UNUSED_FRAMES:
		var n: int = frame
		assert_eq(_opaque_pixels(img, n), 0, "unused frame %d is blank" % n)
	return true

func test_every_referenced_frame_keeps_a_transparent_margin() -> bool:
	# Art running to a frame edge bleeds into the neighbouring frame when the
	# AtlasTexture samples it.
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n: int = frame
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
