extends TestCase

# The inspector is a view over the board: it decides nothing about legality or
# affordability, it asks UpgradesSim and the board. These tests pin that it
# asks, and that it refreshes when the answers change.
#
# @onready resolution follows the project-wide pattern - notification(
# NOTIFICATION_READY) directly, because add_child() does not deliver it in
# this harness. See test_hud.gd's header for the full finding.
#
# SCRIPT ERROR noise from the placement flow below is expected, per
# test_game_board.gd's documented pattern: a tower the board instantiates
# never resolves its own @onready fields, so Tower.setup() and
# set_range_visible() abort partway. Every field the inspector reads (kind,
# tiers, price_paid, the resolved stats) is assigned before that point.

func _ready_inspector() -> TowerInspector:
	var i: TowerInspector = load("res://ui/tower_inspector.tscn").instantiate()
	i.notification(Node.NOTIFICATION_READY)
	return i

func _ready_board() -> GameBoard:
	var b: GameBoard = load("res://game/game_board.tscn").instantiate()
	b.notification(Node.NOTIFICATION_READY)
	return b

func _first_buildable_tile(b: GameBoard) -> Vector2i:
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == Tiles.BUILDABLE:
				return Vector2i(c, r)
	return Vector2i(-1, -1)

func _ready_tower_on(b: GameBoard) -> Tower:
	b._gold = 5000
	var tile := _first_buildable_tile(b)
	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)
	return b._towers_root.get_child(0)

func _place_tower(b: GameBoard, kind: StringName) -> Tower:
	var placed := b._towers_root.get_child_count()
	b.select_tower_kind(kind)
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == Tiles.BUILDABLE and not b._occupied.has(Vector2i(c, r)):
				b._try_place(c, r)
				if b._towers_root.get_child_count() > placed:
					return b._towers_root.get_child(placed)
	return null

func test_starts_empty_with_no_tower_shown() -> bool:
	var i := _ready_inspector()
	assert_false(i.has_tower(), "nothing selected at start")
	assert_eq(i.branch_rows().size(), 0, "and no rows drawn")
	i.free()
	return true

func test_show_tower_lists_one_row_per_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	assert_true(i.has_tower(), "a tower is shown")
	assert_eq(i.branch_rows().size(), Upgrades.BRANCHES.size(), "one row per branch")
	for branch in Upgrades.BRANCHES:
		assert_true(i.branch_rows().has(branch), "a row for %s" % branch)
	i.free(); b.free()
	return true

func test_a_row_shows_the_next_tiers_label_and_cost() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	var row: Button = i.branch_rows()[&"sustained"]
	assert_true(row.text.contains("Quick Loader"), "names the tier being bought: %s" % row.text)
	assert_true(row.text.contains("30"), "and its price: %s" % row.text)
	assert_true(row.text.contains("Barrage"), "and the branch it belongs to: %s" % row.text)
	i.free(); b.free()
	return true

# The description is the tooltip rather than a third line of button text: the
# sidebar is 140px wide at the design ratio and a Button does not wrap, so a
# sentence on the face of it would simply be cut off.
func test_a_row_carries_the_tiers_description_as_its_tooltip() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	assert_eq(i.branch_rows()[&"sustained"].tooltip_text,
		String(Upgrades.DEFS[&"basic"][&"sustained"]["tiers"][0]["description"]),
		"the tier's own description, not a paraphrase")
	i.free(); b.free()
	return true

# The row must follow the tower, not restate tier 1 forever.
func test_a_row_advances_to_the_next_tier_after_a_purchase() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)

	b.upgrade_selected_tower(&"sustained")

	var row: Button = i.branch_rows()[&"sustained"]
	assert_true(row.text.contains("Drum Feed"), "now offers tier 2: %s" % row.text)
	assert_true(row.text.contains("60"), "at tier 2's price: %s" % row.text)
	i.free(); b.free()
	return true

func test_a_row_is_disabled_when_the_player_cannot_afford_it() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)
	b._gold = 0

	i.show_tower(t)

	assert_true(i.branch_rows()[&"sustained"].disabled, "cannot buy what you cannot afford")
	i.free(); b.free()
	return true

# The reference carries a comment recording this exact bug: its panel was drawn
# once on selection, so a tower selected while broke stayed greyed out after a
# wave paid out and the player had to reselect to see it.
func test_rows_re_enable_when_gold_arrives_without_reselecting() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)
	b._gold = 0
	i.show_tower(t)
	assert_true(i.branch_rows()[&"sustained"].disabled, "precondition: greyed out")

	b._gold = 500
	b.gold_changed.emit(500)

	assert_false(i.branch_rows()[&"sustained"].disabled,
		"the row re-enabled on the gold signal alone")
	i.free(); b.free()
	return true

func test_a_row_is_disabled_when_the_cross_path_rule_locks_the_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	t.tiers = {&"sustained": 2, &"burst": 3}

	i.show_tower(t)

	assert_true(i.branch_rows()[&"sustained"].disabled,
		"locked by commitment, not by price")
	assert_true(i.branch_rows()[&"sustained"].text.contains("locked"),
		"and it says so - a player who reads 'maxed' would stop trying to reach it: %s"
			% i.branch_rows()[&"sustained"].text)
	assert_false(i.branch_rows()[&"burst"].disabled,
		"while the committed branch is still open")
	i.free(); b.free()
	return true

func test_a_maxed_branch_is_disabled_too() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	t.tiers = {&"sustained": 0, &"burst": UpgradesSim.MAX_TIER}

	i.show_tower(t)

	assert_true(i.branch_rows()[&"burst"].disabled, "there is nothing left to buy")
	assert_true(i.branch_rows()[&"burst"].text.contains("maxed"),
		"a finished branch reads as maxed, not as locked by the other one: %s"
			% i.branch_rows()[&"burst"].text)
	i.free(); b.free()
	return true

func test_pressing_a_row_asks_the_board_to_buy_that_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)

	i.branch_rows()[&"burst"].pressed.emit()

	assert_eq(t.tiers[&"burst"], 1, "the board bought the tier")
	assert_eq(t.tiers[&"sustained"], 0, "the branch pressed is the branch bought, not the first one listed")
	i.free(); b.free()
	return true

# Sell lives here now, beside the tiers it refunds, and has to quote what the
# tower is actually worth - placement plus every upgrade since.
func test_the_sell_row_quotes_the_refund_including_upgrades() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)
	b.upgrade_selected_tower(&"sustained")

	var sell: Button = i.sell_row()
	assert_true(sell.text.contains(str(EconomySim.sell_refund(t.price_paid))),
		"quotes half of placement plus the tier just bought: %s" % sell.text)
	i.free(); b.free()
	return true

func test_pressing_sell_sells_the_selected_tower() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)

	i.sell_row().pressed.emit()

	assert_eq(b.get_tower_count(&"basic"), 0, "the board sold it")
	assert_false(i.has_tower(), "and the panel emptied instead of describing a tower that is gone")
	assert_false(i._rows_root.visible, "with its column hidden")
	i.free(); b.free()
	return true

func test_clear_empties_the_inspector() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	i.clear()

	assert_false(i.has_tower(), "nothing shown after deselection")
	assert_eq(i.branch_rows().size(), 0, "and no stale rows on display")
	assert_false(i._rows_root.visible, "the whole column is hidden, not left showing a dead tower's tiers")
	i.free(); b.free()
	return true

# Selecting a tower on the board has to reach the inspector without anyone
# calling show_tower by hand - that wiring is what makes the panel appear.
func test_selecting_a_tower_on_the_board_shows_it() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	b._handle_tap(Grid.tile_to_world_center(t.grid_col, t.grid_row))

	assert_true(i.has_tower(), "the tap selected it and the inspector followed")
	assert_eq(i.branch_rows().size(), Upgrades.BRANCHES.size(), "with its rows drawn")

	b._deselect_tower()

	assert_false(i.has_tower(), "and deselecting clears it again")
	i.free(); b.free()
	return true

# Showing a second tower must rewrite the rows rather than add another set.
# The nodes are built once and never freed, so the count is the guard against
# a reintroduced rebuild as much as against duplicates.
func test_showing_a_second_tower_rewrites_the_rows_in_place() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var first := _ready_tower_on(b)
	i.show_tower(first)
	var count := i._rows_root.get_child_count()
	var header := i._name

	var second := _place_tower(b, &"mortar")
	i.show_tower(second)

	assert_eq(i._rows_root.get_child_count(), count, "no second set of rows was added")
	assert_true(i._name == header, "and the header is the same node, rewritten")
	assert_true(header.text.contains(String(Towers.DEFS[&"mortar"]["label"])),
		"now describing the second tower: %s" % header.text)
	assert_true(i.branch_rows()[&"sustained"].text.contains(
		String(Upgrades.DEFS[&"mortar"][&"sustained"]["label"])),
		"and so do its rows: %s" % i.branch_rows()[&"sustained"].text)
	i.free(); b.free()
	return true

# The bug this design exists to prevent, exercised through the button itself
# rather than through the board. Godot locks an object while it is emitting
# and refuses to free it, so a rebuild triggered BY a row's own press aborted
# partway: the tier was bought and the panel went on advertising it.
func test_pressing_a_row_refreshes_the_panel_it_was_pressed_from() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)
	assert_true(i.branch_rows()[&"sustained"].text.contains("Quick Loader"),
		"precondition: the row offers tier 1")
	var gold_before := b.get_gold()

	i.branch_rows()[&"sustained"].pressed.emit()

	assert_eq(t.tiers[&"sustained"], 1, "the tier was bought")
	assert_true(i.branch_rows()[&"sustained"].text.contains("Drum Feed"),
		"and the row moved on to the next one: %s" % i.branch_rows()[&"sustained"].text)
	assert_true(i.branch_rows()[&"sustained"].text.contains("60"),
		"at its price: %s" % i.branch_rows()[&"sustained"].text)
	assert_true(i._counters[&"sustained"].text.contains("1/%d" % UpgradesSim.MAX_TIER),
		"and the header counted it: %s" % i._counters[&"sustained"].text)
	assert_true(i.sell_row().text.contains(str(EconomySim.sell_refund(t.price_paid))),
		"and the refund grew with it: %s" % i.sell_row().text)
	assert_eq(b.get_gold(), gold_before - 30, "one tier, one charge")
	i.free(); b.free()
	return true

func test_rows_meet_the_minimum_tap_target() -> bool:
	assert_true(TowerInspector.MIN_TAP_SIZE.x >= 44.0 and TowerInspector.MIN_TAP_SIZE.y >= 44.0,
		"MIN_TAP_SIZE satisfies the touch-first 44x44 floor")
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))
	for branch in i.branch_rows():
		var button: Button = i.branch_rows()[branch]
		assert_eq(button.custom_minimum_size, TowerInspector.MIN_TAP_SIZE,
			"the %s row is built at the tap-target size" % branch)
	assert_eq(i.sell_row().custom_minimum_size, TowerInspector.MIN_TAP_SIZE,
		"and so is Sell")
	i.free(); b.free()
	return true

# The header says what this panel IS, what tower it describes, and how far
# down each branch that tower has gone - on three lines that read as three
# different kinds of thing.
func test_the_header_names_the_panel_the_tower_and_its_tiers() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)
	b.upgrade_selected_tower(&"sustained")

	assert_eq(i._kicker.text, "UPGRADES:", "the panel says what it is")
	assert_eq(i._name.text, String(Towers.DEFS[&"basic"]["label"]), "and which tower")
	assert_eq(i._counters[&"sustained"].text, "Barrage 1/%d" % UpgradesSim.MAX_TIER,
		"the branch bought into counts up")
	assert_eq(i._counters[&"burst"].text, "Marksman 0/%d" % UpgradesSim.MAX_TIER,
		"and the untouched one still reads zero")
	i.free(); b.free()
	return true

# Three sizes, largest for the tower's own name: the hierarchy is what makes
# the panel legible at a glance, and it is the only thing here a test can hold
# (a screenshot judges whether it LOOKS right; this holds that it was asked
# for at all).
func test_the_header_lines_carry_three_distinct_type_treatments() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	var kicker: int = i._kicker.get_theme_font_size(&"font_size")
	var name_size: int = i._name.get_theme_font_size(&"font_size")
	var counter_label: Label = i._counters[&"sustained"]
	var counter: int = counter_label.get_theme_font_size(&"font_size")
	assert_eq(kicker, TowerInspector.KICKER_FONT_SIZE, "the kicker is set to its own size")
	assert_eq(name_size, TowerInspector.NAME_FONT_SIZE, "the tower name to its own")
	assert_eq(counter, TowerInspector.COUNTER_FONT_SIZE, "the counters to theirs")
	assert_true(name_size > counter and counter > kicker,
		"and they descend: name %d > counter %d > kicker %d" % [name_size, counter, kicker])
	assert_true(i._kicker.get_theme_color(&"font_color") != i._name.get_theme_color(&"font_color"),
		"the kicker is not the same colour as the name it introduces")
	i.free(); b.free()
	return true

# --------------------------------------------------------------------------
# the green highlight
#
# Green means "you can press this right now" - legal AND affordable. Anything
# else keeps the default look, so the colour carries one meaning only.
# --------------------------------------------------------------------------

func test_an_affordable_row_is_highlighted() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	assert_true(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"a row you can buy is picked out")
	i.free(); b.free()
	return true

func test_an_unaffordable_row_is_not_highlighted() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)
	b._gold = 0
	i.show_tower(t)

	assert_false(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"green would promise a purchase the player cannot make")
	i.free(); b.free()
	return true

func test_a_locked_row_is_not_highlighted() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	t.tiers = {&"sustained": 2, &"burst": 3}
	i.show_tower(t)

	assert_false(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"gold in the bank does not unlock a branch the cross-path rule closed")
	assert_true(i.branch_rows()[&"burst"].has_theme_stylebox_override(&"normal"),
		"while the branch that IS open stays picked out")
	i.free(); b.free()
	return true

# The highlight has to follow the gold, like the disabled state does - the same
# bug the reference recorded, one layer up.
func test_the_highlight_appears_when_gold_arrives_and_goes_when_it_is_spent() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)
	b._gold = 0
	i.show_tower(t)
	assert_false(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"precondition: broke, so not highlighted")

	b._gold = 500
	b.gold_changed.emit(500)
	assert_true(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"the row lit up on the gold signal alone")

	b._gold = 0
	b.gold_changed.emit(0)
	assert_false(i.branch_rows()[&"sustained"].has_theme_stylebox_override(&"normal"),
		"and went out again when it was spent")
	i.free(); b.free()
	return true

func test_the_highlight_is_the_documented_green() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	var box: StyleBoxFlat = i.branch_rows()[&"sustained"].get_theme_stylebox(&"normal")
	assert_eq(box.bg_color, TowerInspector.BUYABLE_COLOR, "the green is the one constant, not a literal")
	assert_true(box.bg_color.g > box.bg_color.r and box.bg_color.g > box.bg_color.b,
		"and it is actually green")
	i.free(); b.free()
	return true

# --------------------------------------------------------------------------
# staying inside a 140px sidebar
#
# The harness never puts nodes in a live tree, so containers never lay out and
# no test here can measure a rect - CONTINUE.md §5 says so, and Task 11 found
# this defect by screenshotting rather than by running the suite: the Rows
# container reported the header Label's 214px minimum width and grew 37px out
# over the map. What IS pinnable is the set of properties that keep a row's
# minimum width off its text, so the regression cannot come back silently.
# --------------------------------------------------------------------------

func test_the_header_wraps_rather_than_demanding_its_own_width() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	for label in [i._kicker, i._name, i._counters[&"sustained"], i._counters[&"burst"]]:
		assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART,
			"a Label without autowrap reports its longest line as a minimum width")
		assert_eq(label.text.count("\n"), 0, "each header line is its own Label now")
	i.free(); b.free()
	return true

func test_every_row_clips_its_text_instead_of_widening() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	for branch in i.branch_rows():
		var button: Button = i.branch_rows()[branch]
		assert_true(button.clip_text, "the %s row clips rather than pushing the column wider" % branch)
		assert_eq(button.text.count("\n"), 2, "branch, tier and price on three short lines")
	assert_true(i.sell_row().clip_text, "and so does Sell")
	i.free(); b.free()
	return true

# If a row ever does exceed the column, it must spill toward the screen edge
# rather than back over the play field, where it is both visible and wrong.
func test_the_rows_container_grows_away_from_the_map() -> bool:
	var i := _ready_inspector()
	assert_eq(i._rows_root.grow_horizontal, Control.GROW_DIRECTION_END,
		"overflow goes right, off the edge, not left over the map")
	i.free()
	return true

# The header text is left-aligned and would otherwise sit flush against the
# sidebar's edge, with the map showing through right beside it. Same 8px
# breather the build buttons above get from the panel's own layout.
func test_the_rows_are_inset_from_the_sidebar_edges() -> bool:
	var i := _ready_inspector()
	assert_eq(i._rows_root.offset_left, 8.0, "inset from the left edge")
	assert_eq(i._rows_root.offset_right, -8.0, "and the right")
	assert_true(140.0 - 16.0 >= TowerInspector.MIN_TAP_SIZE.x,
		"the inset column is still wide enough for a row at its minimum size")
	i.free()
	return true
