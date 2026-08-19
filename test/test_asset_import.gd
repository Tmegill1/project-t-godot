extends TestCase

# Mipmap generation and mipmap sampling are two halves of one fix, and this
# gate holds the half that has no visible trace anywhere else.
#
# Every ground, prop and endpoint texture under assets/kenney/, plus the
# shared tower atlas, is baked from 128px+ Kenney source art drawn into 48px
# tiles - a hard minification (the same class of ratio the ~37% forest ground
# reduction is: see test_enemy.gd) that aliases and shimmers unless the
# sampler has a pre-averaged mipmap chain to read instead of the base level.
# map_renderer.gd sets TEXTURE_FILTER_LINEAR_WITH_MIPMAPS so its sprites
# sample that chain (pinned by test_map_renderer.gd) - but a filter that
# samples a chain nobody generated just falls back to the base level anyway.
# Generation is the other half, and it lives entirely in the .import
# sidecar's mipmaps/generate setting, an import-time flag with zero
# representation in the committed PNG bytes.
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
# If this goes red: set mipmaps/generate=true in the named .import file and
# re-run `godot --headless --import`. Do not delete this gate.

func _import_files() -> Array[String]:
	var found: Array[String] = ["res://assets/towers.png.import"]
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

func test_every_kenney_and_tower_import_generates_a_mipmap_chain() -> bool:
	var files := _import_files()
	assert_true(files.size() > 0, "precondition: found .import files under assets/kenney/ and assets/towers.png.import")
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
