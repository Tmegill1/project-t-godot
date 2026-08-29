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
	_place_camps(rng)
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
		# Props are centred (see _place_prop); endpoints and tiles are not.
		# Reading the flag rather than assuming keeps the blocking circle on
		# the visible art - the invisible wall this whole footprint model
		# exists to prevent is exactly what a wrong anchor would manufacture.
		var centre: Vector2 = sprite.position if sprite.centered \
			else sprite.position + display / 2.0
		out.append({
			"pos": centre,
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
	# Jitter is bounded so the drawn sprite cannot reach a ROAD neighbour. A
	# fence or a rock overhanging the lane enemies walk down reads as an
	# obstacle in it - the player's eye does not know the footprint stops at
	# the grass. Wandering is still free in every direction that is not road,
	# which is where the lattice-breaking actually comes from.
	var half_over := maxf(0.0, (box - Tiles.TILE_SIZE) / 2.0)
	var limit := PROP_JITTER * Tiles.TILE_SIZE
	var wander := Vector2(
		rng.float_range(
			-_room_towards(col, row, -1, 0, half_over, limit),
			_room_towards(col, row, 1, 0, half_over, limit)),
		rng.float_range(
			-_room_towards(col, row, 0, -1, half_over, limit),
			_room_towards(col, row, 0, 1, half_over, limit)))
	var sprite := _place(texture, col, row, box, _Z_OVERLAY, inset + wander)
	# Re-anchored to CENTRED. _place leaves a sprite top-left anchored, which
	# is right for a tile but wrong for anything that rotates: a rotation about
	# a top-left origin swings the sprite instead of turning it in place.
	#
	# An earlier version set both `offset` and `position` by half the sprite,
	# which pushes BOTH the same way rather than cancelling - so every rotated
	# prop was displaced by half its own size, and that is what put a fence and
	# a rock on the road. Converting the anchor once, here, keeps the geometry
	# uniform: a prop's position IS its centre.
	var drawn := sprite.texture.get_size() * sprite.scale
	sprite.centered = true
	sprite.position += drawn / 2.0
	# Mirroring doubles the apparent variety for nothing. Unlike a road piece,
	# a prop carries no directional meaning, so there is no mask to contradict.
	sprite.flip_h = rng.int_range(0, 1) == 1
	if not _NO_ROTATE.has(slot):
		sprite.rotation_degrees = rng.float_range(
			-PROP_ROTATION_DEGREES, PROP_ROTATION_DEGREES)
	_prop_sprites[sprite] = true
	return sprite

## How far a prop in this cell may move towards one neighbour.
##
## Zero towards a road, minus whatever the sprite already overhangs by being
## larger than its cell - so a prop beside the road is pulled AWAY from it
## rather than merely stopped at the edge. Full jitter in every other
## direction, which is what keeps the lattice broken.
func _room_towards(col: int, row: int, dc: int, dr: int,
		half_over: float, limit: float) -> float:
	if _is_road(col + dc, row + dr):
		return -half_over
	return limit

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

## Whether mirroring a piece horizontally leaves the road looking the same.
##
## Requires the road to RUN horizontally - east AND west - so the mirror is
## along its length. A first version asked only whether the mask was symmetric
## about the axis, which also allows the flip when the piece has NEITHER east
## nor west. That is the case that broke it: a horizontal straight has no north
## or south, so it was allowed to flip VERTICALLY, and that mirrors the road's
## cross-section. The verges are not painted the same top and bottom, so the
## road visibly stepped up and down between segments.
##
## Connectivity was never the whole question. A flip has to preserve the ART,
## and mirroring across a road's width does not.
static func mask_allows_flip_h(mask: int) -> bool:
	return (mask & 2 != 0) and (mask & 8 != 0)

## Whether mirroring vertically leaves the road looking the same. Requires
## north AND south, on the same reasoning as mask_allows_flip_h.
static func mask_allows_flip_v(mask: int) -> bool:
	return (mask & 1 != 0) and (mask & 4 != 0)

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

## Fences and fires appear ONLY as part of a camp - never scattered alone.
##
## They used to be strewn uniformly: a palisade section on 10% of buildable
## tiles, plus up to seven lone campfires on tiles beside the lane. Both read
## as litter rather than as terrain, and the reason is that a palisade and a
## fire pit are MANUFACTURED things. A boulder alone in a field is a boulder;
## a five-stake fence alone in a field, with nothing on either side of it and
## nothing behind it, is a question the map cannot answer.
##
## What the art can actually do sets the shape. The palisade is a horizontal
## section with flat ends and continuous rails, so segments at tile pitch abut
## into a wall - verified by compositing before this was built. It has no
## corner piece and no side-on piece, so a camp is A WALL WITH FIRES BEHIND IT
## rather than a four-sided enclosure. Building the enclosure the idea wants
## would need two more sprites that do not exist; building it out of the
## horizontal piece alone would put a fence lying on its side at each end.
const CAMP_COUNT := 3
const CAMP_MIN_WIDTH := 3
const CAMP_MAX_WIDTH := 5

## How far a camp sits from the road it watches, in tiles.
##
## Never adjacent. The ring of cells touching the lane is the most valuable
## ground on the map, and a camp there would deny the player exactly the spots
## a tower wants - the palisade blocks placement like any other prop, and
## unlike scattered props it blocks a CONTIGUOUS run. Two to three tiles back
## still reads as "stationed beside the road" without competing for the cells
## the player is going to want.
const CAMP_MIN_ROAD_DISTANCE := 2
const CAMP_MAX_ROAD_DISTANCE := 3

## How far a camp stays clear of the map border, in tiles.
##
## Every camp on the first attempt landed against an edge - the top two rows
## and column zero - because on a map whose road runs through the middle those
## are the only places with two clear rows at the right distance from it. It
## looked wrong for a reason worth keeping: against the border the fires BEHIND
## the wall are the part that falls off-screen, and the top row sits under the
## HUD strip, so what gets clipped is exactly the depth that makes a camp read
## as a camp rather than as a fence with nothing behind it.
const CAMP_BORDER_INSET := 1

## How far a camp's fire is pulled down towards the wall in front of it, and
## how much horizontal play it keeps, in pixels.
##
## Measured rather than guessed. With both centred on their own cells the
## fire's sprite bottom sits 14px clear of the wall sprite's top, and that band
## of bare grass is what made the first build read as "a fire, and separately a
## fence" rather than as one camp. 12px closes it while leaving the wall's
## stake tips unobscured.
const CAMP_FIRE_SETBACK := 12.0
const CAMP_FIRE_WANDER := 6.0

## Chebyshev distance from a cell to the nearest road, searched outwards and
## capped - the answer is only ever compared against CAMP_MAX_ROAD_DISTANCE,
## so a full distance field would be work thrown away.
func _distance_to_road(col: int, row: int, cap: int) -> int:
	for d in range(1, cap + 1):
		for dr in range(-d, d + 1):
			for dc in range(-d, d + 1):
				if maxi(absi(dr), absi(dc)) != d:
					continue
				if _is_road(col + dc, row + dr):
					return d
	return cap + 1

## Whether a camp of `width` fits with its wall on `row` starting at `col`.
##
## Needs the wall's row AND the row behind it: the fires stand behind the
## wall, both so the camp has depth and so the wall occludes their bases.
func _camp_fits(col: int, row: int, width: int, used: Dictionary) -> bool:
	# row is the WALL's row; row - 1 holds the fires, so the inset applies to
	# row - 1 at the top and to row at the bottom.
	if row - 1 < CAMP_BORDER_INSET or row > _rows - 1 - CAMP_BORDER_INSET:
		return false
	if col < CAMP_BORDER_INSET or col + width > _cols - CAMP_BORDER_INSET:
		return false
	var near := false
	for i in width:
		for r in [row, row - 1]:
			var cell := Vector2i(col + i, r)
			if _tiles[r][cell.x] != Tiles.BUILDABLE:
				return false
			if _decorations.has(cell) or used.has(cell):
				return false
		var d := _distance_to_road(col + i, row, CAMP_MAX_ROAD_DISTANCE)
		if d < CAMP_MIN_ROAD_DISTANCE:
			return false  # too close: this is ground the player wants
		if d <= CAMP_MAX_ROAD_DISTANCE:
			near = true
	return near

## Places up to CAMP_COUNT camps. Runs BEFORE _scatter_decoration so the
## scatter sees the camp cells as taken and fills around them.
func _place_camps(rng: Rng) -> void:
	# Only where the biome's art is actually a wall. See Biomes.has_wall_art:
	# the ice and desert "spike" is a totem and a skull pile, and lining five
	# of either up in a row would be a worse version of the problem camps were
	# built to fix.
	if not Biomes.has_wall_art(_biome):
		return
	var sites: Array = []
	for r in range(1, _rows):
		for c in range(0, _cols):
			# Widest first, so a camp claims as much of a run as it can rather
			# than leaving a two-tile orphan beside it.
			for w in range(CAMP_MAX_WIDTH, CAMP_MIN_WIDTH - 1, -1):
				if _camp_fits(c, r, w, {}):
					sites.append({"col": c, "row": r, "width": w})
					break
	if sites.is_empty():
		return

	var used := {}
	var placed := 0
	for site in rng.shuffle(sites):
		if placed >= CAMP_COUNT:
			break
		if not _camp_fits(site["col"], site["row"], site["width"], used):
			continue  # an earlier camp took part of this run
		_build_camp(site, rng, used)
		placed += 1

func _build_camp(site: Dictionary, rng: Rng, used: Dictionary) -> void:
	var col: int = site["col"]
	var row: int = site["row"]
	var width: int = site["width"]

	# Fires FIRST. At equal z_index Godot draws in child order, so placing the
	# wall afterwards lets it occlude the fire bases behind it. Built the other
	# way round the fire floats in front of its own fence and the camp reads as
	# two unrelated props sharing a patch of grass.
	var fire_count: int = 1 if width < 4 else 2
	for i in fire_count:
		var fc: int = col + 1 + i * (width - 2)
		var cell := Vector2i(clampi(fc, col, col + width - 1), row - 1)
		if _decorations.has(cell):
			continue
		# Aligned and then pulled down against the wall, rather than given the
		# ordinary jitter. Left to wander a third of a tile on its own a fire
		# either opens the gap below back up or climbs in front of its own
		# palisade; inside a built structure it is the relationship to the wall
		# that has to hold, not the freedom from the lattice. A few pixels of
		# horizontal play keep two fires in one camp from looking stamped.
		var sprite := _place_aligned_prop(&"fire", cell.x, cell.y)
		sprite.position.x += rng.float_range(-CAMP_FIRE_WANDER, CAMP_FIRE_WANDER)
		sprite.position.y += CAMP_FIRE_SETBACK
		_decorations[cell] = sprite
		_decoration_slots[cell] = &"fire"

	for i in width:
		var cell := Vector2i(col + i, row)
		_decorations[cell] = _place_aligned_prop(&"spike", cell.x, cell.y)
		_decoration_slots[cell] = &"spike"

	# Claim the camp and a one-tile margin, so two camps cannot grow together
	# into one long unreadable fence.
	for r in range(row - 2, row + 2):
		for c in range(col - 1, col + width + 1):
			used[Vector2i(c, r)] = true

## A prop placed exactly on its cell centre: no jitter, rotation, flip or
## scale variance.
##
## The deliberate exception to _place_prop's rule that every prop wanders. A
## palisade is a BUILT thing - its segments have to line up, or the run stops
## reading as a wall and goes straight back to the scattered junk this
## replaced. Here alignment IS the effect, so the jitter that breaks the
## lattice everywhere else is precisely wrong. It costs the grid nothing:
## a handful of camp tiles against a whole map of jittered props and a
## half-tile-offset ground blend.
##
## No flip either, unlike _place_prop: mirroring a fence section moves where
## its rails meet the neighbouring one, which is the join that makes a run
## read as continuous.
##
## CAUTION for any future caller: this skips _room_towards, so unlike
## _place_prop it does NOTHING to keep its sprite off the road. Camp props are
## safe only because _camp_fits already holds them CAMP_MIN_ROAD_DISTANCE
## clear of the lane - relaxing any of the camp siting rules makes
## test_no_prop_overhangs_the_road fail, which is how that dependency was
## found. Placing an aligned prop anywhere near a road needs its own clamp.
func _place_aligned_prop(slot: StringName, col: int, row: int) -> Sprite2D:
	var texture: Texture2D = load(Biomes.prop_path(_biome, slot))
	var box := Tiles.TILE_SIZE * float(PROP_SCALE.get(slot, 1.0))
	var inset := Vector2.ONE * (Tiles.TILE_SIZE - box) / 2.0
	var sprite := _place(texture, col, row, box, _Z_OVERLAY, inset)
	# Same centre re-anchoring as _place_prop, for the same reason: a prop's
	# position is its centre, and prop_footprints reads sprite.centered to find
	# the blocking circle.
	var drawn := sprite.texture.get_size() * sprite.scale
	sprite.centered = true
	sprite.position += drawn / 2.0
	_prop_sprites[sprite] = true
	return sprite

## One scattered prop slot. Weighted so trees stay the common case and the
## biome's landmark, where it has one, stays occasional.
func _scatter_slot(rng: Rng) -> StringName:
	if Biomes.has_wall_art(_biome):
		return &"stone" if rng.int_range(0, 2) == 0 else &"tree"
	var roll := rng.int_range(0, 4)
	if roll == 0:
		return &"stone"
	if roll == 1:
		return &"spike"
	return &"tree"

## Trees and rocks on open ground. Fences and fires are NOT scattered here -
## see _place_camps for why.
func _scatter_decoration(rng: Rng) -> void:
	var buildable: Array = []
	var buildable_total := 0
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.BUILDABLE:
				continue
			buildable_total += 1
			if not _decorations.has(Vector2i(c, r)):
				buildable.append(Vector2i(c, r))

	# The same 10% the palisade sections used to take, and camps are placed ON
	# TOP of it rather than counted against it.
	#
	# The alternative - camps drawing from this budget so the total number of
	# blocking props held steady - was built and measured, and it stripped the
	# map bare: on the demo map the camps ate most of the allowance and left
	# six scattered props for the whole field, which is the opposite of what
	# the decoration is for.
	#
	# What it costs is build space, and that was measured too rather than
	# assumed. Legal tower positions on a half-tile lattice, using the real
	# placement rule: demo map 46.3% before, 42.1% after; map2 54.7% to 51.7%;
	# map3 50.1% to 45.5%. Roughly four points, against a 16-tower limit and
	# 542 legal spots on the tightest map - nowhere near binding.
	#
	# Computed from the whole buildable pool rather than the pool left after
	# camps, so the target does not drift with how much ground camps took.
	var target: int = mini(buildable_total, maxi(5, int(floor(buildable_total * 0.1))))
	var count: int = mini(buildable.size(), target)
	var shuffled := rng.shuffle(buildable)
	for i in count:
		var t: Vector2i = shuffled[i]
		# A biome with no wall art keeps its spike in the scatter, because
		# there it was never the problem: a skull pile alone in the desert is
		# a landmark, while a fence alone in a field is a fence around nothing.
		var slot: StringName = _scatter_slot(rng)
		_decorations[t] = _place_prop(slot, t.x, t.y, rng)
		_decoration_slots[t] = slot

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
		# Continuous, not per cell - a detail sprite has no tile, which is how
		# it crosses boundaries. But it must not land ON the road: the road is
		# where the player reads threat, and a pebble or shrub drawn there
		# looks like something in the lane. Resampled rather than nudged, so
		# the distribution over the ground stays uniform.
		# Named `spot`, not `position`: a local called position shadows
		# Node2D.position and the engine warns about it.
		var spot := Vector2(rng.float_range(0.0, width), rng.float_range(0.0, height))
		var attempts := 0
		while _is_road(int(spot.x / Tiles.TILE_SIZE),
				int(spot.y / Tiles.TILE_SIZE)) and attempts < 8:
			spot = Vector2(rng.float_range(0.0, width), rng.float_range(0.0, height))
			attempts += 1
		if attempts >= 8:
			# A map that is nearly all road would spin here. Drop the sprite
			# rather than place it badly or loop.
			sprite.free()
			continue
		sprite.position = spot
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
