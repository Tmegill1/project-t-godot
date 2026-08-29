class_name MapRenderer
extends Node2D

## Draws a tile grid. Decoration scatter is seeded so a map renders
## identically every run.

## Shared across every biome: the goal and spawn markers are player landmarks,
## not scenery, and are the same object whatever the map is made of.
const _CASTLE := preload("res://assets/art/castle.png")
const _CAVE := preload("res://assets/art/cave.png")

const _MAX_FIRE_TILES := 7

## z-index ordering. Ground draws below decoration, endpoints and blocked-tile
## overlays. Ground sits at -1 rather than 0 for no reason beyond history: a
## grid overlay used to occupy 0 between them, and the values were left alone
## when it was removed rather than renumbering every layer.
## Four terrain layers, bottom to top. The ordering is load-bearing: the blend
## pass is offset half a tile, so tiles from cells NEXT to a road spill 24px
## onto it - and at 50% alpha that washed the road out and made it read
## thinner than it is. The road therefore draws ABOVE the blend, not with the
## ground it is chosen alongside.
const _Z_GROUND := -3
const _Z_GROUND_BLEND := -2
const _Z_ROAD := -1
## Between ground and props: detail scatters over the terrain but under
## anything the player is meant to read as an object.
const _Z_DETAIL := 0
const _Z_OVERLAY := 1

var _tiles: Array = []
var _rows := 0
var _cols := 0
var _decorations := {}  # Vector2i -> Sprite2D
var _decoration_slots := {}  # Vector2i -> StringName
var _biome: StringName = Biomes.FIRST

## Sprites that count as solid props, recorded as they are created.
##
## This replaces the old _PROP_TEXTURES const array of preloads, which could
## not express a per-biome prop set. Recording at creation is also strictly
## more robust than comparing textures after the fact - two biomes could
## legitimately share a texture without both being props.
var _prop_sprites := {}

func render(tiles: Array, rng: Rng = null, biome: StringName = Biomes.FIRST) -> void:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DECORATION_SEED)
	_biome = biome
	_tiles = tiles
	_rows = tiles.size()
	_cols = tiles[0].size() if _rows > 0 else 0

	# Freed synchronously, not queue_free()'d: queue_free() only unparents a
	# node once a frame actually processes, which never happens within a
	# single headless test method (no await allowed) - a queue_free() here
	# would leave the previous render's sprites in get_children() alongside
	# the new ones, doubling counts on every re-render observed synchronously.
	# The sprites being cleared are owned exclusively by this node (nothing
	# else holds a reference once _decorations.clear() runs), so an immediate
	# free() is safe.
	for child in get_children():
		child.free()
	_decorations.clear()
	_decoration_slots.clear()
	_prop_sprites.clear()

	_draw_ground()
	_scatter_detail(rng)
	_draw_endpoints()
	_scatter_decoration(rng)
	_draw_blocked(rng)

## Every prop as a world-space blocking circle, for sim/placement.gd.
##
## Endpoints are excluded on purpose: they are drawn 3 tiles wide, so a
## footprint from one would carry a ~72px radius and sterilise the ground
## around the spawn and goal - where a player most wants a last line of
## defence. The path corridor already keeps towers off the endpoints.
##
## Radius is half the sprite's LONGEST displayed axis, so it over-covers
## rather than under-covers: blocking slightly too much reads as level design,
## while a tower clipping into a rock reads as a bug. This only measures
## correctly because _place scales uniformly (see its doc comment); under the
## stretch-to-square behaviour it replaced, displayed size was a distortion.
## Which cell each scattered decoration was assigned to, and what it is.
##
## Exposed because the SCATTER RULE (which cells get a spike, which get a fire)
## and the RENDER (where in that cell the sprite actually lands) are different
## questions, and jitter made the second a bad proxy for the first. Tests used
## to recover the cell by comparing a sprite's position against tile origins,
## which stopped working the moment a prop was allowed to overhang - and would
## have gone on "working" by silently testing nothing.
func decoration_cells() -> Dictionary:
	var out := {}
	for cell in _decorations:
		out[cell] = _decoration_slots.get(cell, &"")
	return out

func prop_footprints() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Sprite2D):
			continue
		var sprite: Sprite2D = child
		if not _prop_sprites.has(sprite):
			continue
		var tex: Texture2D = sprite.texture
		var display := Vector2(tex.get_width(), tex.get_height()) * sprite.scale
		out.append({
			"pos": sprite.position + display / 2.0,
			"radius": maxf(display.x, display.y) / 2.0,
		})
	return out

## Fits a texture inside a size_px square box preserving the source aspect
## ratio, then centres it in that box.
##
## DELIBERATE DIVERGENCE FROM THE REFERENCE. Phaser's MapRenderer.ts uses
## setDisplaySize(size, size), which stretches each source to a square
## whatever its true proportions are; most of this art is not square, so the
## reference visibly distorts it (stone.png is 216x97 - squashed over 2:1 -
## and cave.png 300x216). Matching that stretch was faithful but wrong-looking,
## so the port scales uniformly instead. Anything comparing rendered geometry
## against the Phaser build will differ here, by design.
##
## Centring has to be applied to the position because these sprites are
## top-left anchored (centered = false, matching Phaser's setOrigin(0, 0)):
## once a sprite no longer fills its box, the leftover slack is split evenly
## rather than all landing on the right/bottom edge.
func _place(texture: Texture2D, col: int, row: int, size_px: float,
		z: int, offset := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	var src := Vector2(texture.get_width(), texture.get_height())
	var factor := size_px / maxf(src.x, src.y)
	var slack := (Vector2(size_px, size_px) - src * factor) / 2.0
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE) + offset + slack
	s.scale = Vector2.ONE * factor
	# _place draws props (up to 96x61 into a 48px box, 1.83x) and endpoints
	# (~220px into a 144px box, 1.49x) - hard enough minification that the
	# project-wide default filter, plain LINEAR, would sample the base level
	# only and alias badly; this reads the mipmap chain the .import files
	# generate instead (test_art_import.gd). LINEAR rather than NEAREST
	# because this art is painted, not pixel art - and the enemy sprites
	# (game/enemy.tscn) are the same case, not the opposite: they are also
	# painted art past a hard minification, so they also take
	# LINEAR_WITH_MIPMAPS rather than NEAREST.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = z
	add_child(s)
	return s

## How much of a tile each prop slot fills. 1.0 unless a slot's art carries
## more visual weight than its role deserves.
##
## Only fire is under 1.0. The decor column's campfire is its loudest object -
## bright orange against every one of the three biomes' grounds - and up to
## seven of them land on a map, so at full tile size they competed with the
## player's own towers for attention. Shrinking the art shrinks the footprint
## with it, which is intended rather than tolerated: prop_footprints derives a
## blocking radius from displayed size precisely so that what blocks you is
## what you can see, and holding the footprint while shrinking the art would
## manufacture the invisible wall that rule exists to prevent.
const PROP_SCALE := {
	&"tree": 1.0, &"stone": 1.0, &"spike": 1.0, &"fire": 0.8,
}

## How far a prop may wander from its cell's centre, as a fraction of a tile.
##
## THE single largest contributor to the board reading as a grid. Every sprite
## used to be positioned at col * TILE_SIZE, so trees, stones, spikes and fires
## all drew a 48px lattice however varied the ground beneath them was - and
## nothing in the scene ever crossed a cell boundary. Props may now overhang
## their cell, which is the point.
##
## 0.28 rather than more: past about a third the prop visibly belongs to the
## wrong tile, and props from adjacent cells start colliding.
const PROP_JITTER := 0.28

## How much a prop's size may vary from its slot's nominal scale.
##
## Repetition of an identical sprite reads as tiling even when the positions
## are broken up. Kept modest because prop_footprints derives a blocking radius
## from displayed size, so this is not purely cosmetic - a bigger tree really
## does block more.
const PROP_SCALE_JITTER := 0.18

## The most a prop may be rotated, in degrees.
##
## Deliberately small. These are painted, top-down props with a clear up
## direction; past a few degrees they read as knocked over rather than as
## naturally placed.
const PROP_ROTATION_DEGREES := 7.0

## Slots that must not rotate at all. Flame art has an unambiguous up.
const _NO_ROTATE: Array[StringName] = [&"fire"]

## Places a prop and records it as one, so prop_footprints can find it.
## Places a prop and records it as one, so prop_footprints can find it.
##
## `rng` is required rather than optional: a prop placed without one would sit
## dead centre on the lattice, which is the thing this whole layer exists to
## avoid, and an optional argument makes forgetting it silent.
func _place_prop(slot: StringName, col: int, row: int, rng: Rng) -> Sprite2D:
	# load() here, not in Biomes: data/ stays engine-free (test_sim_purity.gd).
	var texture: Texture2D = load(Biomes.prop_path(_biome, slot))
	var jitter_scale := 1.0 + rng.float_range(-PROP_SCALE_JITTER, PROP_SCALE_JITTER)
	var box := Tiles.TILE_SIZE * float(PROP_SCALE.get(slot, 1.0)) * jitter_scale
	# _place centres a sprite inside the box it is given, and the box is
	# anchored at the tile's origin - so a box smaller than a tile has to be
	# offset by the difference or the prop sits in the tile's top-left corner
	# instead of the middle of it.
	var inset := Vector2.ONE * (Tiles.TILE_SIZE - box) / 2.0
	var wander := Vector2(
		rng.float_range(-PROP_JITTER, PROP_JITTER),
		rng.float_range(-PROP_JITTER, PROP_JITTER)) * Tiles.TILE_SIZE
	var sprite := _place(texture, col, row, box, _Z_OVERLAY, inset + wander)
	# Mirroring doubles the apparent variety for nothing. Unlike a road piece,
	# a prop carries no directional meaning, so there is no mask to contradict.
	sprite.flip_h = rng.int_range(0, 1) == 1
	if not _NO_ROTATE.has(slot):
		# Rotated about the sprite's own middle rather than its top-left, or a
		# rotation would also translate it.
		sprite.offset = sprite.texture.get_size() / 2.0
		sprite.position += sprite.texture.get_size() / 2.0 * sprite.scale
		sprite.rotation_degrees = rng.float_range(
			-PROP_ROTATION_DEGREES, PROP_ROTATION_DEGREES)
	_prop_sprites[sprite] = true
	return sprite

## Ground is one sprite per tile, on the tile grid.
##
## This replaces a corner-mask lattice that sampled terrain at tile centres
## over a (cols+1) x (rows+1) grid offset half a tile. That existed because the
## previous art blended between terrains; this art does not - its cells are
## discrete cards and its road pieces are shapes. An edge mask over orthogonal
## neighbours is the simpler thing that this art actually wants.
##
## Each ground tile is also drawn at one of four orientations, chosen from the
## same Rng. Six cards over 322 cells put the same picture down about 54 times,
## and the eye reads that repetition as a grid rather than as a field.
## MEASURED on the composed board: the ground's self-similarity at a lag of
## exactly one tile sat +55.8 above its neighbouring lags - that periodic
## signal IS the grid - and mirroring cuts it to +22.0, a 61% reduction, for
## nothing. Road pieces are excluded because their art is chosen by an edge
## mask and mirroring one contradicts its own mask.
##
## Two alternatives were measured and rejected. Normalising each card's mean
## colour toward the biome's moved the periodicity by nothing (+22.0 to +22.6)
## and would have flattened the deliberate dirt patches. Cross-fading tile
## edges cut the variation INSIDE a tile by 42%, which is softening the grass
## rather than fixing the grid - and the seams were never the problem: the
## luminance step across a tile boundary measured no larger than the step
## inside one, so there was no edge discontinuity to remove.
##
## Ground variety is drawn from its own Rng rather than the decoration one.
## Which of the six ground cards a tile gets is cosmetic and should not move
## when the decoration seed changes; drawing from the passed rng here would
## also shift the whole decoration stream, since _draw_ground runs first.
func _draw_ground() -> void:
	_draw_ground_layer(Rng.new(Seeds.DEFAULT_GROUND_SEED), Vector2.ZERO, 1.0)
	# The offset pass. Its own Rng, so it picks different cards from the first
	# layer rather than laying the identical board on top of itself at 50%,
	# which would cancel nothing.
	_draw_ground_blend(Rng.new(Seeds.DEFAULT_GROUND_SEED + 1))

## The second ground pass: same cards, offset half a tile, half transparent.
##
## Ground only, and it deliberately covers ROAD cells too - a road tile is
## drawn after at full opacity and its own z, so the blend never shows through
## one. Skipping road cells would leave a hard rectangle of un-blended ground
## around every road, which is a worse grid than the one being removed.
func _draw_ground_blend(rng: Rng) -> void:
	var shift := Vector2.ONE * (Tiles.TILE_SIZE * GROUND_BLEND_OFFSET)
	for r in _rows:
		for c in _cols:
			if _is_road(c, r):
				continue
			var tile := _place_tile(load(Biomes.ground_path(
				_biome, rng.int_range(0, Biomes.GROUND_VARIANTS - 1))),
				c, r, GROUND_OVERFILL)
			tile.position += shift
			tile.flip_h = rng.int_range(0, 1) == 1
			tile.flip_v = rng.int_range(0, 1) == 1
			tile.modulate = Color(1.0, 1.0, 1.0, GROUND_BLEND_ALPHA)
			tile.z_index = _Z_GROUND_BLEND

func _draw_ground_layer(variants: Rng, _shift: Vector2, _alpha: float) -> void:
	for r in _rows:
		for c in _cols:
			# load() rather than a texture from Biomes: data/ is held
			# engine-free by test_sim_purity.gd, so the render layer is where
			# a path becomes a resource. Godot's ResourceLoader caches by
			# path, so the repeated calls are dictionary hits.
			if _is_road(c, r):
				# Drawn at _Z_ROAD so the offset blend pass cannot spill over
				# it - see the z-order note above.
				var mask := edge_mask(c, r)
				var road := _place_tile(
					load(Biomes.road_path(_biome, mask)), c, r)
				road.z_index = _Z_ROAD
				# Flipped only along axes its own mask is SYMMETRIC about.
				# The old rule was never flip at all, on the grounds that
				# mirroring a piece draws a north-east corner where the mask
				# says north-west - true of a corner, and false of a straight.
				# A long run of straights is where the road's periodicity
				# actually lives (measured at +33 excess against the grass's
				# +7), and every one of them is symmetric.
				if mask_allows_flip_h(mask):
					road.flip_h = variants.int_range(0, 1) == 1
				if mask_allows_flip_v(mask):
					road.flip_v = variants.int_range(0, 1) == 1
			else:
				var tile := _place_tile(load(Biomes.ground_path(
					_biome, variants.int_range(0, Biomes.GROUND_VARIANTS - 1))),
					c, r, GROUND_OVERFILL)
				# One of four orientations, which is what turns six ground
				# cards into twenty-four. See the note above _draw_ground.
				tile.flip_h = variants.int_range(0, 1) == 1
				tile.flip_v = variants.int_range(0, 1) == 1

## Whether mirroring a piece horizontally still satisfies its own mask.
##
## flip_h swaps EAST (2) and WEST (8), so the mask survives only when it holds
## both or neither. A straight E-W run and a N-S run both qualify; an
## north-east corner does not, and flipping one would draw a north-WEST corner
## where the mask says north-east.
static func mask_allows_flip_h(mask: int) -> bool:
	return (mask & 2 != 0) == (mask & 8 != 0)

## Whether mirroring vertically still satisfies the mask. flip_v swaps NORTH
## (1) and SOUTH (4), on the same reasoning as mask_allows_flip_h.
static func mask_allows_flip_v(mask: int) -> bool:
	return (mask & 1 != 0) == (mask & 4 != 0)

## The four orthogonal neighbours of a cell that are road, as a bitmask.
## Bit order is fixed: N=1, E=2, S=4, W=8. Out of bounds is not road.
## Public so tests can assert the mask without inspecting sprites.
func edge_mask(c: int, r: int) -> int:
	var mask := 0
	if _is_road(c, r - 1):
		mask |= 1
	if _is_road(c + 1, r):
		mask |= 2
	if _is_road(c, r + 1):
		mask |= 4
	if _is_road(c - 1, r):
		mask |= 8
	return mask

## How much of each tile's edge is the card's painted border rather than
## terrain, and is therefore not drawn.
##
## The sheet's terrain tiles are cards with a dark scalloped edge and a drop
## shadow. Drawn whole, every cell boundary carries two of those edges back to
## back and the board reads as a grid of cards in black gutters - the single
## most visible thing about the first map rendered from this art. The spec
## called for tiles "scaled to slightly overfill each cell" to close them,
## which works for the ground and cannot work for the road: a road tile's
## leading border is then drawn over its neighbour's road instead of over its
## grass. Cropping removes it in both cases.
##
## MEASURED at 5 - the widest near-black run reaching in from any edge across
## all 66 ground and road PNGs in all three biomes - plus one.
const TILE_BLEED := 6

## How much larger than its cell a GROUND tile draws.
##
## Cropping the card border (TILE_BLEED) removed the black gutters, but left a
## hard edge at every cell boundary where two independently-chosen cards meet -
## visible as a faint darker seam, and the reason each dirt patch reads as
## exactly one square. Overfilling by a few percent makes neighbours overlap so
## there is no boundary to see.
##
## GROUND ONLY. A road tile is chosen by its edge mask, so overfilling one
## draws its leading border over its neighbour's ROAD instead of over grass -
## the same reason road tiles are never flipped. _place_tile takes the overfill
## as an argument for exactly that reason.
const GROUND_OVERFILL := 1.08

## Opacity of the second, half-tile-offset ground layer.
##
## MEASURED. Prop jitter and the detail layer both improved how the board
## READS, but neither touched the thing that makes it a grid: excess
## autocorrelation at a lag of exactly one tile sat at +7.7 before any of this
## work and +6.5 after both, because every cell still carried one discrete card
## and nothing changed that.
##
## This does. A second full ground pass is drawn offset by half a tile, so its
## card boundaries land on the FIRST layer's centres. The composite has no
## single 48px boundary line anywhere, because wherever one layer has an edge
## the other has a middle.
##
## Half-transparent rather than opaque: at 1.0 the offset layer simply becomes
## the grid, shifted 24px. The two have to be visible through each other for
## their boundaries to cancel rather than replace.
const GROUND_BLEND_ALPHA := 0.5

## Where the second ground layer sits relative to the first, in tiles.
const GROUND_BLEND_OFFSET := 0.5

## Draws a ground or road tile STRETCHED to fill its cell exactly.
##
## Deliberately not _place. A tile is a cell of a grid and has to cover its
## cell; _place fits a source inside the box preserving aspect and centres it
## in the slack, which is right for a prop and opens seams here - the road
## pieces are 66x63, so aspect-fitting leaves 2.2px of transparency under
## every one of them. The distortion this trades for is 4.7% on the roads and
## under 2% on the ground.
##
## prop_footprints reads displayed size to derive a blocking radius and its
## doc comment says that only measures correctly because _place scales
## uniformly. That stays true: props still go through _place, and nothing
## drawn here is ever recorded as a prop.
func _place_tile(texture: Texture2D, col: int, row: int,
		overfill := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	# The card's border is cropped rather than drawn - see TILE_BLEED.
	s.region_enabled = true
	s.region_rect = Rect2(TILE_BLEED, TILE_BLEED,
		texture.get_width() - TILE_BLEED * 2.0,
		texture.get_height() - TILE_BLEED * 2.0)
	# Overfill grows the tile about its own centre, so the surplus spills
	# evenly onto all four neighbours rather than pushing the grid off-origin.
	var spill := Tiles.TILE_SIZE * (overfill - 1.0) / 2.0
	s.position = Vector2(col * Tiles.TILE_SIZE - spill, row * Tiles.TILE_SIZE - spill)
	s.scale = Vector2(
		float(Tiles.TILE_SIZE) * overfill / s.region_rect.size.x,
		float(Tiles.TILE_SIZE) * overfill / s.region_rect.size.y)
	# Unlike _place, plain LINEAR here - no mipmap chain. Either of two
	# reasons would be enough on its own. First, region_enabled is set two
	# lines up: a mip level averages across the region's boundary, and for
	# these tiles that means averaging the cropped card border (TILE_BLEED)
	# back into the terrain, reintroducing by hand the seam the crop exists
	# to remove. Second, the minification here is mild - 66 source px into a
	# 48 cell, 1.125x - next to the props' up to 1.83x, so the aliasing plain
	# LINEAR leaves behind is negligible by comparison. See test_art_import.gd,
	# which pins both this exclusion and the props/endpoints/enemy inclusion.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.z_index = _Z_GROUND
	add_child(s)
	return s

## Out of bounds reads as ground, which is what the edge mask needs at the
## map's border without a special case.
func _is_road(c: int, r: int) -> bool:
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return false
	return _tiles[r][c] in Tiles.WALKABLE

func _draw_endpoints() -> void:
	# Drawn 3 tiles wide, offset up and left, matching the Phaser build.
	var offset := Vector2(-Tiles.TILE_SIZE, -Tiles.TILE_SIZE - 20)
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.SPAWN:
				_place(_CAVE, c, r, Tiles.TILE_SIZE * 3, _Z_OVERLAY, offset)
			elif _tiles[r][c] == Tiles.GOAL:
				_place(_CASTLE, c, r, Tiles.TILE_SIZE * 3, _Z_OVERLAY, offset)

func _scatter_decoration(rng: Rng) -> void:
	var buildable: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BUILDABLE:
				buildable.append(Vector2i(c, r))

	var spike_count: int = mini(buildable.size(), maxi(5, int(floor(buildable.size() * 0.1))))
	var shuffled := rng.shuffle(buildable)
	for i in spike_count:
		var t: Vector2i = shuffled[i]
		_decorations[t] = _place_prop(&"spike", t.x, t.y, rng)
		_decoration_slots[t] = &"spike"

	var path_adjacent: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.BUILDABLE:
				continue
			if _decorations.has(Vector2i(c, r)):
				continue
			if _is_adjacent_to_walkable(r, c):
				path_adjacent.append(Vector2i(c, r))

	var fire_count: int = mini(path_adjacent.size(), _MAX_FIRE_TILES)
	var shuffled_adjacent := rng.shuffle(path_adjacent)
	for i in fire_count:
		var t: Vector2i = shuffled_adjacent[i]
		_decorations[t] = _place_prop(&"fire", t.x, t.y, rng)
		_decoration_slots[t] = &"fire"

## How many detail sprites to scatter per tile of map.
##
## This is the layer that answers "the ground reads as squares". The ground
## itself was already fixed as far as it can be - four orientations over six
## cards, and a measured 61% cut in periodicity - and it still reads as a grid
## because every card is a discrete square of content with its own colour cast.
## Nothing else in the scene crosses a cell boundary, so the eye has nothing to
## read across the seam.
##
## Detail is scattered in CONTINUOUS world space rather than per cell, so it
## lands wherever it lands and routinely straddles boundaries. That is the
## entire point: it is the only thing in the scene that spans a seam.
const DETAIL_PER_TILE := 1.6

## Which prop art the detail layer borrows, and at what fraction of a tile.
##
## PLACEHOLDER. The illustrated sheet ships no small detail pieces, so this
## reuses the props at a size where they read as ground texture - a stone at a
## quarter scale is a pebble, a tree at a third is a shrub. Replace with real
## detail art when there is any; the layer's shape does not change.
const DETAIL_SOURCES := {
	&"stone": 0.26,
	&"tree": 0.30,
}

## Scatters non-blocking ground detail across the whole map.
##
## NEVER recorded in _prop_sprites, so prop_footprints never sees it and no
## placement rule moves. Decoration only - it may sit under a tower, over a
## road edge, anywhere. That freedom is what lets it ignore the grid.
func _scatter_detail(rng: Rng) -> void:
	var slots := DETAIL_SOURCES.keys()
	var count := int(float(_cols * _rows) * DETAIL_PER_TILE)
	var width := float(_cols * Tiles.TILE_SIZE)
	var height := float(_rows * Tiles.TILE_SIZE)
	for i in count:
		var slot: StringName = slots[rng.int_range(0, slots.size() - 1)]
		var texture: Texture2D = load(Biomes.prop_path(_biome, slot))
		var box := Tiles.TILE_SIZE * float(DETAIL_SOURCES[slot]) \
			* rng.float_range(0.75, 1.25)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.scale = Vector2.ONE * (box / maxf(
			float(texture.get_width()), float(texture.get_height())))
		# Continuous, not per cell. A detail sprite has no tile.
		sprite.position = Vector2(rng.float_range(0.0, width), rng.float_range(0.0, height))
		sprite.rotation_degrees = rng.float_range(0.0, 360.0)
		sprite.flip_h = rng.int_range(0, 1) == 1
		# Slightly translucent and slightly darkened, so it reads as part of
		# the ground rather than as a small object sitting on it.
		sprite.modulate = Color(0.92, 0.92, 0.92, rng.float_range(0.55, 0.85))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.z_index = _Z_DETAIL
		add_child(sprite)

func _draw_blocked(rng: Rng) -> void:
	var excluded := {}
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.SPAWN and _tiles[r][c] != Tiles.GOAL:
				continue
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					excluded[Vector2i(c + dc, r + dr)] = true

	var blocked: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BLOCKED and not excluded.has(Vector2i(c, r)):
				blocked.append(Vector2i(c, r))

	var stone_count: int = mini(blocked.size(), rng.int_range(3, 5))
	var shuffled := rng.shuffle(blocked)
	var stones := {}
	for i in stone_count:
		stones[shuffled[i]] = true

	for t in blocked:
		_place_prop(&"stone" if stones.has(t) else &"tree", t.x, t.y, rng)

func _is_adjacent_to_walkable(row: int, col: int) -> bool:
	# The loop variable below is untyped Variant (an array literal's element
	# type is not inferred), so `:=` cannot infer a type for nr/nc from a
	# Variant-typed member access and hard-fails to parse ("Cannot infer the
	# type of ... variable") on Godot 4.7.1. Explicit `int` typing sidesteps
	# the broken inference; this is not a behavioural change from the brief.
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nr: int = row + d.y
		var nc: int = col + d.x
		if nr < 0 or nr >= _rows or nc < 0 or nc >= _cols:
			continue
		if _tiles[nr][nc] in Tiles.WALKABLE:
			return true
	return false
