class_name Maps

const FIRST := &"demoMap"

const DEFS := {
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		"tower_budget": 16, "starting_gold": 100,
		"biome": &"forest",
		"layout": "res://data/maps/the_pass.txt",
		"next": &"map2",
	},
	&"map2": {
		"label": "The Fork",
		"cols": 26, "rows": 17, "tile_size": 48,
		# Two entrances means the full wave runs down both, so this map fields
		# twice the enemies of the same wave number on The Pass. The opening
		# gold and the budget are where that difficulty is paid for.
		"tower_budget": 20, "starting_gold": 250,
		"biome": &"ice",
		"layout": "res://data/maps/the_fork.txt",
		"next": &"map3",
	},
	&"map3": {
		"label": "The Coils",
		"cols": 28, "rows": 16, "tile_size": 48,
		# Widest board, but the serpentine route folds back on itself - a
		# tower on a bend covers two passes, so it needs fewer of them than
		# its size suggests.
		"tower_budget": 18, "starting_gold": 200,
		"biome": &"desert",
		"layout": "res://data/maps/the_coils.txt",
		# The last map. An empty StringName rather than null so every reader
		# gets the same type back.
		"next": &"",
	},
}

static func get_def(name: StringName) -> Dictionary:
	return DEFS[name]

## Tiles for a map, read from its layout file.
##
## These used to be algorithmic builders - three GDScript files that pushed
## path coordinates and scattered blocked tiles from a seed. Reading one meant
## mentally executing seven run_row/run_col calls to work out the map's shape.
## The shape is now the file, so a map is data rather than code, a map change
## reviews as the map changing, and adding one stops being programming.
##
## The seeded scatter those builders produced was BAKED IN when they were
## retired, so every map is exactly the board it was before - the golden tests
## did not move.
##
## FileAccess is the first file I/O in data/, and it is compatible with what
## test_sim_purity.gd exists to protect: the ban is on scene types (which would
## break the headless claim) and on clocks, RNG and platform state (which would
## break the reproducible one). Reading a packed file is neither - it works
## headlessly and returns the same bytes every time.
##
## Deliberately not cached: a map edited on disk is picked up on the next
## reload, which is the whole point of the format.
static func build_tiles(name: StringName) -> Array:
	if not DEFS.has(name):
		push_error("Maps.build_tiles: unknown map %s" % name)
		return []
	var path: String = DEFS[name]["layout"]
	if not FileAccess.file_exists(path):
		push_error("Maps.build_tiles: no layout file at %s" % path)
		return []
	return MapFormat.parse(FileAccess.get_file_as_string(path))

## A map's dimensions in tiles. Named accessors because callers asked
## DemoMap.GRID_COLS before the builders were retired, and
## DEFS[name]["cols"] reads worse at every one of those call sites.
static func cols(name: StringName) -> int:
	return int(DEFS[name]["cols"])

static func rows(name: StringName) -> int:
	return int(DEFS[name]["rows"])

## Canvas size a map needs, in pixels.
static func pixel_size(name: StringName) -> Vector2i:
	var d: Dictionary = DEFS[name]
	return Vector2i(d["cols"] * d["tile_size"], d["rows"] * d["tile_size"])
