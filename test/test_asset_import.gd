extends TestCase

# Mipmap generation and mipmap sampling are two halves of one fix, and this
# gate holds the half that has no visible trace anywhere else.
#
# Every ground, prop and endpoint texture under assets/kenney/ is baked from
# 128px+ Kenney source art drawn into 48px tiles - a hard minification (the
# same class of ratio the ~37% forest ground reduction is: see
# test_enemy.gd) that aliases and shimmers unless the sampler has a
# pre-averaged mipmap chain to read instead of the base level. map_renderer.gd
# sets TEXTURE_FILTER_LINEAR_WITH_MIPMAPS so its sprites sample that chain
# (pinned by test_map_renderer.gd) - but a filter that samples a chain nobody
# generated just falls back to the base level anyway. Generation is the
# other half, and it lives entirely in the .import sidecar's
# mipmaps/generate setting, an import-time flag with zero representation in
# the committed PNG bytes.
#
# That is exactly why this gate is worth having: a missing mipmap chain
# fails no test anywhere else in this suite, throws no error, and changes no
# pixel count - it only makes the rendered board look worse, on every frame,
# in a way nothing here can see except this file.
#
# This replaces a gate lost when test_map_assets.gd was deleted (Task 10 of
# the Kenney art swap): that file's GATE 5 asserted the same property by
# loading each PNG as an imported Texture2D and calling has_mipmaps(). This
# version reads the committed .import file as plain text instead, so it
# checks the configuration actually in source control rather than whatever
# .godot/imported happens to hold from a stale or partial cache.
#
# Deliberately excludes assets/enemies/**: those are 48px hand-placed pixel
# art filtered NEAREST, not LINEAR_WITH_MIPMAPS (see test_enemy.gd), and a
# mipmap chain on pixel art is the wrong call, not a missing one. Asserting
# mipmaps/generate=true over them would be pinning a bug, not a fix.
#
# assets/towers.png.import is EXCLUDED ON PURPOSE, and this exclusion is load-
# bearing, not an oversight to "complete" by folding it back in. Nothing
# samples a mip chain on it: game/tower.gd region-samples the sheet through
# an AtlasTexture, and both game/tower.tscn's Sprite and ui/tower_panel.gd's
# Button.icon inherit the project's default LINEAR filter (no mipmaps), never
# LINEAR_WITH_MIPMAPS. Turning mipmaps/generate=true on for this file would
# be actively wrong even if a future change did wire a mipmap filter to it:
# towers.png is one 480x384 sheet, region-sampled per frame, and mip levels
# average across frame boundaries - the frame margin is 6px, so one level
# down it is down to 3px and degrades further from there, bleeding adjacent
# tower frames into each other. If you are tempted to add this file back to
# the walk below, add a mipmap texture_filter to the tower sprite first and
# convince yourself the frame-bleed above does not apply - it does.
#
# If this goes red: set mipmaps/generate=true in the named .import file and
# re-run `godot --headless --import`. Do not delete this gate.

func _import_files() -> Array[String]:
	var found: Array[String] = []
	_walk("res://assets/kenney/", found)
	found.sort()
	return found

func _walk(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full + "/", found)
		elif entry.ends_with(".import"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

func test_every_kenney_import_generates_a_mipmap_chain() -> bool:
	var files := _import_files()
	# Pinned, not just "> 0": a bare non-empty check is satisfied by a single
	# stray .import file, so a renamed or partially-missing assets/kenney/
	# would shrink this gate silently instead of failing it - the same shape
	# of blind spot this file exists to close. 56 is the walk's true count as
	# of this fix (every ground/road blend and prop texture across
	# forest/ice/desert, plus the two composed endpoints); if this drops, a
	# biome directory or its ground/prop set went missing, not "the assets
	# are fine, just fewer of them".
	assert_true(files.size() >= 56,
		("only found %d .import files under assets/kenney/ (expected at " +
		"least 56) - a biome directory or its ground/prop set is likely " +
		"missing, not merely smaller") % files.size())
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_true(not text.is_empty(), "%s reads as text" % path)
		if text.is_empty():
			continue
		assert_true(text.contains("mipmaps/generate=true"),
			("%s does not set mipmaps/generate=true - map_renderer.gd's " +
			"LINEAR_WITH_MIPMAPS filter has no chain to sample, so this " +
			"texture will alias when minified") % path)
	return true
