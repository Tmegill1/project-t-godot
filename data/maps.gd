class_name Maps

const FIRST := &"demoMap"

const DEFS := {
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		# 200, raised from 100 on 2026-08-30. The tower costs that landed the
		# same day left this purse buying exactly ONE tower - a Basic at 35, or
		# a Magic at 80 - because the second Basic escalates to 135. Measured
		# against a player who merely spends, on this map:
		#
		#   start   opening   wave 1   lives lost by w3   board full   lives left
		#     100   1 tower   0 leaks                 7          w13           10
		#     170   2 towers   1 leak                 6          w12           12
		#     200   2 towers  0 leaks                 2          w13           18
		#     250   3 towers  0 leaks                 0          w13            9
		#
		# 200 buys the second tower without buying away the wave-2 sting, and
		# leaves the build-out exactly where the cost change put it: the budget
		# still fills at wave 13 and still maxes at 20. 170 is worse than either
		# neighbour - it affords the tower and nothing else, so the board is
		# thin enough to leak on wave 1.
		"tower_budget": 12, "starting_gold": 200,
		"biome": &"forest",
		"layout": "res://data/maps/the_pass.txt",
		"next": &"map2",
	},
	&"map2": {
		"label": "The Fork",
		"cols": 26, "rows": 17, "tile_size": 48,
		# Two entrances means the full wave runs down both, so this map fields
		# twice the enemies of the same wave number on The Pass. Its larger
		# opening purse pays for that difficulty; tower variety still caps at
		# three of each kind, as it does on every map.
		"tower_budget": 12, "starting_gold": 250,
		"biome": &"ice",
		"layout": "res://data/maps/the_fork.txt",
		"next": &"map3",
	},
	&"map3": {
		"label": "The Coils",
		"cols": 28, "rows": 16, "tile_size": 48,
		# Widest board, but the serpentine route folds back on itself - a
		# tower on a bend covers two passes. The shared twelve-tower cap still
		# leaves meaningful coverage choices here.
		"tower_budget": 12, "starting_gold": 200,
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
