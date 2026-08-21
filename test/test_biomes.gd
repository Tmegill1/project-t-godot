extends TestCase

# The biome table is three directories with an identical file layout, so most
# of what could go wrong is a path that does not resolve. These check that.

func test_the_three_biomes_are_exactly_forest_ice_and_desert() -> bool:
	assert_eq(Biomes.KINDS.size(), 3, "three biomes")
	assert_true(Biomes.KINDS.has(&"forest"), "forest exists")
	assert_true(Biomes.KINDS.has(&"ice"), "ice exists")
	assert_true(Biomes.KINDS.has(&"desert"), "desert exists")
	assert_eq(Biomes.FIRST, &"forest", "forest is the first biome")
	return true

func test_every_biome_resolves_its_ground_and_road_pieces() -> bool:
	for biome in Biomes.KINDS:
		for i in Biomes.GROUND_VARIANTS:
			assert_true(ResourceLoader.exists(Biomes.ground_path(biome, i)),
				"%s ground %d resolves" % [biome, i])
		for mask in 16:
			assert_true(ResourceLoader.exists(Biomes.road_path(biome, mask)),
				"%s road %d resolves" % [biome, mask])
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

func test_every_biome_resolves_all_four_prop_slots() -> bool:
	for biome in Biomes.KINDS:
		for slot in Biomes.PROP_SLOTS:
			var path := Biomes.prop_path(biome, slot)
			assert_true(ResourceLoader.exists(path),
				"%s %s resolves to a real resource (%s)" % [biome, slot, path])
	return true
