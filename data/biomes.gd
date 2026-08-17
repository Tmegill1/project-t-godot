class_name Biomes

## Which art a map is drawn with. Three entries, each one directory that the
## bake tool (tools/bake_kenney.gd) guarantees holds an identical file layout:
## blend_NN.png per corner mask, plus tree/stone/spike/fire.
##
## The prop slot names are the ones MapRenderer's scatter rules already use.
## Only the texture behind each name is per-biome; none of the placement rules
## are.

const FIRST := &"forest"

const DEFS := {
	&"forest": {"label": "Forest", "dir": "res://assets/kenney/forest"},
	&"ice": {"label": "Ice", "dir": "res://assets/kenney/ice"},
	&"desert": {"label": "Desert", "dir": "res://assets/kenney/desert"},
}

const KINDS: Array[StringName] = [&"forest", &"ice", &"desert"]

const PROP_SLOTS: Array[StringName] = [&"tree", &"stone", &"spike", &"fire"]

## The pack ships no diagonal-only blend tile in any pairing - the connection
## is genuinely ambiguous, so blob tilesets omit it. 15 (full road) is the
## substitution: it connects both diagonals rather than neither. The demo map
## produces neither mask, and test_map_renderer.gd asserts that stays true, so
## this is a safety net rather than a live path.
const DIAGONAL_MASKS: Array[int] = [6, 9]
const DIAGONAL_FALLBACK := 15

static func get_def(biome: StringName) -> Dictionary:
	return DEFS[biome]

## Returns a path, never a loaded resource. data/ is held engine-free by
## test/test_sim_purity.gd, whose docstring explains that resource loading
## breaks the headless claim the whole harness rests on. The render layer
## loads; this module only names. Same division as data/enemies.gd's
## texture_key and data/towers.gd's sprite_frame.
static func blend_path(biome: StringName, mask: int) -> String:
	var resolved := DIAGONAL_FALLBACK if mask in DIAGONAL_MASKS else mask
	return "%s/blend_%02d.png" % [DEFS[biome]["dir"], resolved]

static func prop_path(biome: StringName, slot: StringName) -> String:
	return "%s/%s.png" % [DEFS[biome]["dir"], slot]
