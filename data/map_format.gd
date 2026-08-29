class_name MapFormat

## The text map format: one character per tile, one line per row.
##
## This is the CONTRACT between the game and whatever authors a map. The game
## reads it; a text editor writes it today, and a TileMap-painting scene could
## export to it later. Neither side depends on the other existing, which is
## why the format came before any editor.
##
## Why text rather than code: a map used to be an algorithmic builder, so
## reading one meant mentally executing seven run_row/run_col calls to work out
## its shape. Now the shape IS the file. It is also diffable, so a map change
## reviews as the map changing rather than as coordinate arithmetic, and it is
## editable by anything - including an assistant, which cannot meaningfully
## paint a TileMap inside a scene file.
##
## Pure, like the rest of data/. It converts between text and tile arrays and
## touches no files - reading them belongs to whoever has a path.

## Character to tile kind. The alphabet is deliberately small and mnemonic:
## S and G are the endpoints, = is a road you can see running across the line,
## # is solid, and . is open ground.
const CHARS := {
	"S": Tiles.SPAWN,
	"G": Tiles.GOAL,
	"=": Tiles.PATH,
	"#": Tiles.BLOCKED,
	".": Tiles.BUILDABLE,
}

## Tile kind back to character. Derived from CHARS rather than written twice,
## so the two can never disagree.
static func char_for(kind: StringName) -> String:
	for c in CHARS:
		if CHARS[c] == kind:
			return c
	return "?"

## Reads a layout into the tile array the rest of the game already speaks.
##
## Tolerant of what a text editor does without being asked: blank lines are
## skipped, trailing whitespace is stripped, and CRLF is handled. An unknown
## character becomes a distinct UNKNOWN marker rather than silently becoming
## buildable - validate() is what turns that into a reported problem, so a typo
## surfaces as an error instead of as a hole in the map.
static func parse(text: String) -> Array:
	var tiles: Array = []
	for raw_line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var line: String = (raw_line as String).strip_edges(false, true)
		if line.is_empty():
			continue
		var row: Array = []
		for i in line.length():
			var ch := line[i]
			row.append(CHARS.get(ch, UNKNOWN))
		tiles.append(row)
	return tiles

## What an unrecognised character parses to. Not a tile kind the game knows, so
## anything that reaches the renderer or the pathfinder with one of these is a
## map that should have failed validation.
const UNKNOWN := &"unknown"

## Writes a tile array back out as text. The inverse of parse for any array
## parse could have produced.
static func format(tiles: Array) -> String:
	var lines: PackedStringArray = []
	for row in tiles:
		var line := ""
		for cell in row:
			line += char_for(cell)
		lines.append(line)
	return "\n".join(lines)

## Everything wrong with a map, as human-readable strings. Empty means valid.
##
## Structural checks only - it does not ask whether the goal is REACHABLE,
## because that needs the pathfinder and pathfinding is not this module's job.
## An authoring tool should run both.
static func validate(tiles: Array) -> Array:
	var problems: Array = []
	if tiles.is_empty():
		problems.append("the map is empty")
		return problems

	var width: int = (tiles[0] as Array).size()
	var spawns := 0
	var goals := 0
	for r in tiles.size():
		var row: Array = tiles[r]
		if row.size() != width:
			problems.append("row %d is %d wide, but row 0 is %d - the grid is ragged"
				% [r, row.size(), width])
		for c in row.size():
			match row[c]:
				Tiles.SPAWN:
					spawns += 1
				Tiles.GOAL:
					goals += 1
				UNKNOWN:
					problems.append("unknown character at column %d, row %d" % [c, r])

	if spawns < 1:
		problems.append("no spawn - a map needs at least one S")
	if goals != 1:
		problems.append("expected exactly one goal (G), found %d" % goals)
	return problems
