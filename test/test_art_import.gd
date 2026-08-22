extends TestCase

# Mipmap generation and mipmap sampling are two halves of one fix, and this
# gate holds the half that has no visible trace anywhere else.
#
# game/map_renderer.gd's _place (props, endpoints) and game/enemy.tscn's
# sprite both sample TEXTURE_FILTER_LINEAR_WITH_MIPMAPS (pinned by
# test_map_renderer.gd and test_enemy.gd respectively) - but a filter that
# samples a chain nobody generated just falls back to the base level anyway.
# Generation is the other half, and it lives entirely in the .import
# sidecar's mipmaps/generate setting, an import-time flag with zero
# representation in the committed PNG bytes. A missing chain fails no test
# anywhere else in this suite, throws no error, and changes no pixel count -
# it only makes the rendered board look worse, on every frame, in a way
# nothing but this file can see.
#
# This replaces test/test_asset_import.gd, deleted in this task (Task 10 of
# the illustrated art swap), which itself replaced a gate lost when
# test_map_assets.gd was deleted (Task 10 of the earlier Kenney art swap).
# That version walked assets/kenney/ and asserted mipmaps/generate=true over
# every file it found, because every Kenney tile, prop and endpoint wanted a
# chain uniformly. The illustrated sheet does not: some of the assets it
# produced are region-sampled, and a mip level on a region-sampled texture
# averages across the region's boundary rather than the whole source, which
# reintroduces exactly the seam or bleed the region crop exists to remove.
# So this version pins a SPLIT rather than a sweep, on both sides: every
# included file must read mipmaps/generate=true, every excluded one must
# read mipmaps/generate=false. A gate that only asserted the true side would
# let a later sweep turn the excluded assets on and nothing would catch it.
#
# Included - painted art past a hard minification, sampled whole (no
# region_enabled): props (up to 96x61 into a 48px box, 1.83x), the two
# composed endpoints (~220px into a 144px box, 1.49x), and the enemy variants
# (up to 105x47 into 28-58px tall, 1.3-1.6x). All three go through a filter
# that samples a mip chain - see the sprite tests named above - so a missing
# chain would alias on every one of them.
#
# Excluded - ground and road tiles. Two independent reasons, either alone
# enough. First, they are barely minified: 66 source px into a 48px cell,
# 1.125x, next to the props' up to 1.83x. Second, and load-bearing on its
# own: map_renderer.gd's _place_tile sets region_enabled and crops the card's
# painted border (TILE_BLEED) before drawing, so a mip level would average
# the cropped border back into the terrain, reintroducing by hand the seam
# TILE_BLEED exists to remove. _place_tile filters plain LINEAR for exactly
# this reason - see its doc comment in game/map_renderer.gd.
#
# assets/towers.png.import is EXCLUDED ON PURPOSE, and this exclusion is
# load-bearing, not an oversight to "complete" by folding it back in.
# Nothing samples a mip chain on it: game/tower.gd region-samples the sheet
# through an AtlasTexture, and both game/tower.tscn's Sprite and
# ui/tower_panel.gd's Button.icon inherit the project's default LINEAR
# filter (no mipmaps), never LINEAR_WITH_MIPMAPS. Turning
# mipmaps/generate=true on for this file would be actively wrong even if a
# future change did wire a mipmap filter to it: towers.png is one 480x384
# sheet, region-sampled per frame, and mip levels average across frame
# boundaries - the frame margin is 6px, so one level down it is down to 3px
# and degrades further from there, bleeding adjacent tower frames into each
# other. If you are tempted to add this file back to the walk below, add a
# mipmap texture_filter to the tower sprite first and convince yourself the
# frame-bleed above does not apply - it does.
#
# Deliberately out of scope: assets/art/enemies/_unused/{shaman,troll}/. Both
# are extracted but unreferenced by any code (Enemies.KINDS does not name
# either), waiting on the enemy-variety feature - see the plan's notes for
# the executor. Nothing samples them, so their mipmap setting cannot be
# wrong yet; this gate follows the same measured split as everything else
# and does not reach into assets no code loads.
#
# If this goes red: a file moved from one side of the split to the other
# without its .import changing to match, or Biomes/Enemies grew or shrank
# without the .import sidecars following. Set mipmaps/generate to the value
# this file says the path should have and re-run `godot --headless --import`.
# Do not delete this gate.

## Props: every biome's tree/stone/spike/fire. Path helper from data/biomes.gd
## rather than a literal string, so a prop slot rename here fails loudly
## instead of silently checking a path nothing loads.
func _prop_import_paths() -> Array[String]:
	var out: Array[String] = []
	for biome in Biomes.KINDS:
		for slot in Biomes.PROP_SLOTS:
			out.append(Biomes.prop_path(biome, slot) + ".import")
	return out

## The two composed endpoints, shared across every biome.
func _endpoint_import_paths() -> Array[String]:
	return [
		"res://assets/art/castle.png.import",
		"res://assets/art/cave.png.import",
	]

## Every referenced enemy variant - the three kinds Enemies.KINDS names, not
## the unreferenced assets/art/enemies/_unused/ rows (see the docstring above).
func _enemy_variant_import_paths() -> Array[String]:
	var out: Array[String] = []
	for kind in Enemies.KINDS:
		for i in Enemies.variant_count(kind):
			out.append("res://assets/art/enemies/%s/variant_%d.png.import" % [kind, i])
	return out

## Every biome's ground variants and road edge-mask pieces.
func _tile_import_paths() -> Array[String]:
	var out: Array[String] = []
	for biome in Biomes.KINDS:
		for i in Biomes.GROUND_VARIANTS:
			out.append(Biomes.ground_path(biome, i) + ".import")
		# The road is an edge mask over four orthogonal neighbours (see
		# game/map_renderer.gd's edge_mask), so every one of the 16
		# combinations is a real file - unlike the corner-mask pack this art
		# replaced, which had no diagonal-only pieces to leave out.
		for mask in range(16):
			out.append(Biomes.road_path(biome, mask) + ".import")
	return out

## Reads mipmaps/generate out of a committed .import file's text, not a
## Texture2D's has_mipmaps(): this checks the configuration actually in
## source control rather than whatever .godot/imported happens to hold from a
## stale or partial cache. Returns "true", "false", or "" if the file could
## not be read or the line is not there to read.
func _mipmap_setting(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	if text.contains("mipmaps/generate=true"):
		return "true"
	if text.contains("mipmaps/generate=false"):
		return "false"
	return ""

func test_props_endpoints_and_enemy_variants_generate_a_mipmap_chain() -> bool:
	var paths := _prop_import_paths() + _endpoint_import_paths() + _enemy_variant_import_paths()
	# Pinned, not just "> 0": 45 is 12 props (4 slots x 3 biomes) + 2
	# endpoints + 31 enemy variants (15 slime + 13 ogre + 3 bee) as of this
	# fix. If this drops, a biome, prop slot or enemy kind went missing from
	# the data tables, not "the assets are fine, just fewer of them".
	assert_true(paths.size() == 45,
		("expected 45 mipmap-chain imports (12 props + 2 endpoints + 31 " +
		"enemy variants), got %d - a biome, prop slot or enemy kind is " +
		"likely missing from Biomes or Enemies") % paths.size())
	for path in paths:
		var setting := _mipmap_setting(path)
		assert_true(setting != "", "%s reads as text and sets mipmaps/generate" % path)
		if setting == "":
			continue
		assert_eq(setting, "true",
			("%s does not set mipmaps/generate=true - its sprite filters " +
			"LINEAR_WITH_MIPMAPS with no chain to sample, so it will alias " +
			"when minified") % path)
	return true

func test_ground_and_road_tiles_and_the_tower_sheet_stay_mipmap_free() -> bool:
	var paths := _tile_import_paths()
	paths.append("res://assets/towers.png.import")
	# Pinned for the same reason as the true-side count: 67 is 18 ground (6
	# variants x 3 biomes) + 48 road (16 masks x 3 biomes) + towers.png. A
	# gate that only asserted the true side above would let a later sweep
	# turn mipmaps on for these region-sampled assets and nothing would catch
	# it - this is the other half of that pin.
	assert_true(paths.size() == 67,
		("expected 67 mipmap-free imports (18 ground + 48 road + towers.png), " +
		"got %d - a biome or the tower sheet entry is likely missing") % paths.size())
	for path in paths:
		var setting := _mipmap_setting(path)
		assert_true(setting != "", "%s reads as text and sets mipmaps/generate" % path)
		if setting == "":
			continue
		assert_eq(setting, "false",
			("%s sets mipmaps/generate=true, but it is region-sampled and a " +
			"mip level would average the region's cropped or framed edge " +
			"back into its neighbour - see this file's docstring") % path)
	return true
