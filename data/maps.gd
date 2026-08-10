class_name Maps

const FIRST := &"demoMap"

const DEFS := {
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		"tower_budget": 16, "starting_gold": 100,
		"next": &"map2",
	},
}

static func get_def(name: StringName) -> Dictionary:
	return DEFS[name]

## Tiles for a map, generated with its default seed.
static func build_tiles(name: StringName) -> Array:
	match name:
		&"demoMap":
			return DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
		_:
			push_error("Maps.build_tiles: unknown map %s" % name)
			return []

## Canvas size a map needs, in pixels.
static func pixel_size(name: StringName) -> Vector2i:
	var d: Dictionary = DEFS[name]
	return Vector2i(d["cols"] * d["tile_size"], d["rows"] * d["tile_size"])
