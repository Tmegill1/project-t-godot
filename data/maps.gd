class_name Maps

const FIRST := &"demoMap"

const DEFS := {
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		"tower_budget": 16, "starting_gold": 100,
		"biome": &"forest",
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
		# The last map. An empty StringName rather than null so every reader
		# gets the same type back.
		"next": &"",
	},
}

static func get_def(name: StringName) -> Dictionary:
	return DEFS[name]

## Tiles for a map, generated with its default seed.
static func build_tiles(name: StringName) -> Array:
	match name:
		&"demoMap":
			return DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
		&"map2":
			return Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
		&"map3":
			return Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
		_:
			push_error("Maps.build_tiles: unknown map %s" % name)
			return []

## Canvas size a map needs, in pixels.
static func pixel_size(name: StringName) -> Vector2i:
	var d: Dictionary = DEFS[name]
	return Vector2i(d["cols"] * d["tile_size"], d["rows"] * d["tile_size"])
