class_name Biomes

## Which art a map is drawn with. Three entries, each one directory that the
## bake tool (tools/bake_sheet.gd) guarantees holds an identical file layout:
## ground_N.png per ground variant, road_NN.png per edge mask, plus
## tree/stone/spike/fire.
##
## The prop slot names are the ones MapRenderer's scatter rules already use.
## Only the texture behind each name is per-biome; none of the placement rules
## are.

const FIRST := &"forest"

const DEFS := {
	&"forest": {"label": "Forest", "dir": "res://assets/art/forest"},
	&"ice": {"label": "Ice", "dir": "res://assets/art/ice"},
	&"desert": {"label": "Desert", "dir": "res://assets/art/desert"},
}

const KINDS: Array[StringName] = [&"forest", &"ice", &"desert"]

const PROP_SLOTS: Array[StringName] = [&"tree", &"stone", &"spike", &"fire"]

static func get_def(biome: StringName) -> Dictionary:
	return DEFS[biome]

static func prop_path(biome: StringName, slot: StringName) -> String:
	return "%s/%s.png" % [DEFS[biome]["dir"], slot]

## Returns a path, never a loaded resource. data/ is held engine-free by
## test/test_sim_purity.gd, whose docstring explains that resource loading
## breaks the headless claim the whole harness rests on. The render layer
## loads; this module only names.
static func ground_path(biome: StringName, index: int) -> String:
	return "%s/ground_%d.png" % [DEFS[biome]["dir"], index]

## Every one of the sixteen edge masks as a road piece. There is no fallback
## and no rotation: the bake composes all sixteen from the sheet's cross, so
## every mask a map can produce has a file - including the four dead ends,
## which no rotation of the pieces the sheet itself draws can reach.
static func road_path(biome: StringName, mask: int) -> String:
	return "%s/road_%02d.png" % [DEFS[biome]["dir"], mask]

## Ground variants per biome.
const GROUND_VARIANTS := 6
