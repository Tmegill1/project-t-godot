extends TestCase

# The biome table is three directories with an identical file layout, so most
# of what could go wrong is a path that does not resolve. These check that,
# plus the one piece of real logic: the diagonal-mask fallback.

func test_the_three_biomes_are_exactly_forest_ice_and_desert() -> bool:
	assert_eq(Biomes.KINDS.size(), 3, "three biomes")
	assert_true(Biomes.KINDS.has(&"forest"), "forest exists")
	assert_true(Biomes.KINDS.has(&"ice"), "ice exists")
	assert_true(Biomes.KINDS.has(&"desert"), "desert exists")
	assert_eq(Biomes.FIRST, &"forest", "forest is the first biome")
	return true

func test_every_biome_resolves_every_blend_mask_the_pack_supplies() -> bool:
	for biome in Biomes.KINDS:
		for mask in [0, 1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15]:
			var tex := Biomes.blend_texture(biome, mask)
			assert_true(tex != null, "%s mask %d resolves" % [biome, mask])
	return true

func test_the_diagonal_masks_fall_back_to_the_full_road_tile() -> bool:
	# The pack ships no diagonal-only tile in any pairing. 15 connects both
	# diagonals rather than neither, which is the safer resolution.
	for biome in Biomes.KINDS:
		var full := Biomes.blend_texture(biome, 15)
		for mask in Biomes.DIAGONAL_MASKS:
			assert_eq(Biomes.blend_texture(biome, mask), full,
				"%s mask %d falls back to 15" % [biome, mask])
	return true

func test_each_biome_uses_its_own_directory() -> bool:
	# Guards a copy-paste that points two biomes at one directory, which would
	# silently render ice as forest.
	var seen := {}
	for biome in Biomes.KINDS:
		var dir: String = Biomes.get_def(biome)["dir"]
		assert_false(seen.has(dir), "%s has its own directory" % biome)
		seen[dir] = true
	return true

func test_every_biome_carries_a_human_readable_label() -> bool:
	for biome in Biomes.KINDS:
		var label: String = Biomes.get_def(biome)["label"]
		assert_false(label.is_empty(), "%s has a label" % biome)
	return true
