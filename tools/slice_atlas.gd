extends SceneTree

# Slices the eight map tiles out of the reference sprite sheet.
#
#   godot --headless --script tools/slice_atlas.gd
#   godot --headless --import        # regenerate the .import sidecars afterwards
#
# Reads the sheet straight out of the gitignored reference clone. The 3.9 MB
# sheet is deliberately never copied into assets/ or committed - see
# .superpowers/sdd/2026-08-09-godot-core-slice/task-15-findings.md.
#
# ============================================================================
# WHAT IS TRUE OF THESE RECTS - READ THIS BEFORE CHANGING THEM
# ============================================================================
# An earlier version of this header claimed several tiles had been "measured,
# not eyeballed" and "confirmed clean". That was false: six of the eight tiles
# shipped with artwork running straight off an edge or a neighbouring prop
# bleeding in. Do not trust a claim in this file that no longer has a test
# behind it. The claims below are backed by test/test_map_assets.gd, which
# re-derives them from the committed PNGs on every suite run.
#
# There are two different kinds of tile here and they want opposite things:
#
#   PROPS (tree, stone, castle, cave, spike, fire) are drawn as free-standing
#   sprites, so each wants the whole subject inside the rect with a fully
#   transparent margin all round and no neighbouring prop intruding.
#
#   GROUND (grass, path) are seamless textures drawn edge-to-edge across every
#   tile of the board, so each wants to be opaque with NO transparent border
#   at all. A 1px transparent strip on one side draws a visible dark seam at
#   every single tile boundary across the whole map (verified by tiling the
#   old and new textures 4x4 over a dark background and comparing).
#
# The sheet's alpha channel is real (48.6% of its pixels are alpha 0), so the
# rects below were derived from it: a seeded 4-connected flood fill over
# alpha > 8 gives each prop's connected component, and the rect is that
# component's bounding box plus a margin landing in measured-transparent
# gutters. Every rect was then rendered over a magenta background and looked
# at, because a bounding box cannot tell you the crop is around the right
# subject.
#
#   name   | reference (BootScene.ts) | used here           | edge max alpha L,R,T,B
#   -------|--------------------------|---------------------|-----------------------
#   grass  | (60,150,64,64)           | (56,152,64,64)      | opaque; min alpha 249
#   path   | (60,64,64,64)            | (53,56,64,64)       | opaque; min alpha 249
#   tree   | (40,250,100,150)         | (15,248,150,165)    | 2, 0, 2, 0
#   stone  | (670,230,128,128)        | (661,239,216,97)    | 0, 0, 0, 0
#   castle | (750,600,256,350)        | (737,620,287,305)   | 255, 255, 1, 0   (*)
#   cave   | (700,880,300,300)        | (716,924,300,216)   | 0, 17, 0, 0      (*)
#   spike  | (760,530,100,100)        | (770,523,100,100)   | 0, 0, 0, 0
#   fire   | (650,500,100,100)        | (624,512,141,92)    | 5, 58, 230, 0    (*)
#
# (*) Three tiles CANNOT be cut with a clean margin on every edge, because of
# how the source sheet is packed. Those edges are not defects introduced here;
# they are the best available crop, and test_map_assets.gd holds each one to a
# measured pixel budget so it can never quietly get worse. Details are in the
# per-rect comments below.
#
# Every rect here deviates from BootScene.ts, which is a real, visible
# divergence from the Phaser original and was signed off by the owner ("keep
# the corrected art"). Each is one edit from exact parity: paste the reference
# value from the table above back into FRAMES, re-run this script, re-run
# godot --headless --import, and update test_map_assets.gd's expectations.
# ============================================================================

const SOURCE := "res://reference/project-t/td-browser/public/map-sprites.png"

const FRAMES := [
	# GROUND. The grass swatch on the sheet spans x=[22,122] y=[143,225]; the
	# reference rect's right column (x=123) lies outside it, so the shipped
	# tile carried a transparent strip down its right edge. No 64x64 window
	# anywhere on this sheet is fully opaque - the largest alpha==255 square in
	# the whole 1024x1536 image is 6x6 px - so "min alpha 255" is unreachable.
	# The best achievable minimum over a 64x64 window is 249, and this rect
	# (the one closest to the reference that reaches it) hits exactly that.
	{"name": "grass",  "rect": Rect2i(56, 152, 64, 64)},
	# Same story for the path swatch, x=[22,122] y=[40,122]: the reference rect
	# ran off both the right (x=123) and the bottom (y=127) of the swatch,
	# which is why the shipped tile seamed on two sides instead of one.
	{"name": "path",   "rect": Rect2i(53, 56, 64, 64)},
	# Widened from the reference's (40,250,100,150) during the original task:
	# the canopy is a single connected blob spanning x=[20,159] y=[253,407], so
	# the reference clipped ~20px of leaf off each side. Left unchanged here;
	# re-measured edge maxima are 2/0/2/0, i.e. already clean.
	{"name": "tree",   "rect": Rect2i(15, 248, 150, 165)},
	# The reference's (670,230,128,128) framed only the left half of the prop.
	# The flood-filled component is x=[667,870] y=[245,327]: one rock outcrop
	# with two humps sharing a continuous grass base. A 9x zoom of the join at
	# x=752..807 shows no seam and no gutter - the humps are bridged by
	# boulders and grass that belong to both, so this is one prop, not two
	# merged ones, and there is no column between them with max alpha < 255.
	# The reference rect therefore cut through solid rock (right edge 255) and
	# also swallowed the top of a separate bush below it (bottom edge 255).
	# Taking the whole outcrop is the only cut that is clean on all four edges.
	# CONSEQUENCE: 216x97 is a 2.2:1 rect and map_renderer scales x and y
	# independently to a square tile, so the rocks now render ~2.2x taller
	# relative to their width than the reference did. That is a visible change.
	{"name": "stone",  "rect": Rect2i(661, 239, 216, 97)},
	# The castle's own component is x=[726,1023] y=[624,918], and it cannot be
	# given a transparent margin on either side:
	#   RIGHT - the artwork runs into the sheet's last column. x=1023 carries
	#   34 rows of hard opaque castle (alpha 205-255 at y=853..886), so the
	#   sheet itself clips the castle. No rect can add margin that isn't there.
	#   LEFT - two neighbouring rock props overlap the castle's own rows and
	#   reach x=736, while the castle's leftmost pixel is at x=726. Every
	#   column in x=[700,1023] contains either castle or neighbour within the
	#   castle's y range, so no clean left column exists either. Left=737 is
	#   the leftmost column with zero neighbour pixels; it costs 233 px of the
	#   castle's own base bush (x=726..736, y=843..891), which is invisible in
	#   the rendered tile, and it keeps all ~190 px of neighbouring rock out.
	# Top and bottom ARE clean: y=620 (max alpha 1) sits in the gutter above
	# the flag tips, y=924 in the 8-row gutter (y=920..927) below the castle's
	# ground and above the boulder that the reference rect used to swallow.
	{"name": "castle", "rect": Rect2i(737, 620, 287, 305)},
	# Left as the original task cut it - the controller re-measured this one
	# and ruled it correct, and the subject is complete with clean gutters on
	# three sides. Its right column carries exactly one pixel at alpha 17: the
	# last antialiased step of the cave's own rock wall (the wall tapers
	# 230 -> 41 -> 24 -> 17 -> 1 -> 0 across x=1012..1017). Widening the rect
	# by two fully transparent columns to 302 would clear it, at the cost of
	# touching a tile that was signed off as correct; the 1px budget in
	# test_map_assets.gd records the state instead.
	{"name": "cave",   "rect": Rect2i(716, 924, 300, 216)},
	# Same 100x100 size as the reference's (760,530,100,100), shifted 10px left
	# and 7px up. The bush is x=[775,866] y=[532,595] and is well isolated; the
	# reference rect simply sat wrong on it, clipping the bush's right side
	# (edge 255) while its left edge cut a neighbouring bush (246) and its
	# bottom edge cut one of the castle's red flags (250). Shifting rather than
	# resizing keeps the decoration rendering at exactly the reference's scale.
	{"name": "spike",  "rect": Rect2i(770, 523, 100, 100)},
	# The reference's (650,500,100,100) was far too small: the campfire's stone
	# ring spans x=[629,764] y=[512,599], so the reference clipped the stones
	# off both sides (edges 255/255) and the grass off the bottom (250).
	# This rect holds 100% of the prop - flame, both floating embers, the full
	# stone ring and its grass. The TOP edge cannot be made clean: the prop
	# directly above-right dips to y=512 at x>=756, while the campfire's own
	# flame tip rises to y=512 at x=692, so any row that clears the flame also
	# crosses the neighbour. Result: an ~9x2 px tan sliver of that neighbour
	# sits in the tile's top-right corner (tile-local x=132..140). The two
	# alternatives were measured and are worse - cutting at x=755 to clear the
	# sliver amputates 9 columns of the campfire's own grass and stone with a
	# hard vertical edge (verified by rendering both), and every top row that
	# clears the neighbour also cuts through the flame.
	{"name": "fire",   "rect": Rect2i(624, 512, 141, 92)},
]

func _initialize() -> void:
	var source := Image.load_from_file(SOURCE)
	if source == null:
		printerr("could not load %s - is the reference clone present?" % SOURCE)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute("res://assets/map")
	for frame in FRAMES:
		var rect: Rect2i = frame["rect"]
		var out := Image.create(rect.size.x, rect.size.y, false, source.get_format())
		out.blit_rect(source, rect, Vector2i.ZERO)
		var path := "res://assets/map/%s.png" % frame["name"]
		var err := out.save_png(path)
		if err != OK:
			printerr("failed writing %s: %d" % [path, err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [path, rect.size.x, rect.size.y])

	quit(0)
