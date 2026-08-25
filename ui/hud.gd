class_name Hud
extends CanvasLayer

## HUD strip: gold, lives, wave, the Start button and a transient message
## line. Purely a view over GameBoard's signals and accessors - it decides
## nothing about gold, lives, wave progression or placement rules; that is
## the board's job. StartButton carries a custom_minimum_size of at least
## 44x44 (touch-first requirement; see task-20-21-amendments.md amendment 3).
##
## Sell used to live here too. It moved to ui/tower_inspector.gd, beside the
## upgrade tiers whose cost its refund is half of - a sell price that counts
## upgrades means nothing next to the wave counter.
##
## The speed toggle lives here rather than on the board because it is an engine
## setting, not a game rule: nothing in sim/ may reference Engine at all, and
## the harness has its own tick size. What the board owns is the simulation;
## what this owns is how fast the player watches it.

const MESSAGE_SECONDS := 2.0

## What the fast-play button multiplies time by. 1.5x rather than 2x, which
## played too fast.
##
## Engine.time_scale scales the delta passed to _physics_process on 4.7.1 - it
## does not raise the tick rate - so at 1.5x every enemy takes steps half again
## as long. Bigger steps are the shape that soft-locked waves 19 and 20 before
## the waypoint clamp landed, so test_harness.gd sweeps all twenty waves at
## DOUBLE the tick size: a bound above what this button applies, deliberately,
## so the setting has headroom instead of sitting on the tested edge.
const FAST_TIME_SCALE := 1.5

## Horizontal inset of the Top bar from the viewport edges. The bar anchors
## edge to edge, so without this its first and last children sit flush on the
## screen border with the tilemap showing through behind them. Mirrors the
## 12px separation the bar already puts between its own items. The scene file
## carries the literal (offset_left/offset_right on Top); this names it and
## test_hud.gd pins both against each other.
const EDGE_INSET := 12.0

# The scene also carries a `Plate` ColorRect behind `Top`. It has no field
# here on purpose - it is pure decoration the script never touches, and a dead
# @onready earns a "declared but never used" warning. test_hud.gd reaches it
# with get_node("Plate").
#
# It exists because the white Gold/Lives/Wave text is illegible on the ice and
# desert biomes - confirmed live on both, screenshots at
# docs/screenshots/board-map{2,3}.png. A plate rather than a per-biome text
# tint or a shadow: it is the only one of the three that is biome-independent,
# so a fourth biome cannot arrive and break it. Its mouse_filter is IGNORE, so
# it never eats a click meant for the board underneath.
@onready var _gold: Label = $Top/GoldLabel
@onready var _lives: Label = $Top/LivesLabel
@onready var _wave: Label = $Top/WaveLabel
@onready var _budget: Label = $Top/BudgetLabel
@onready var _prep: Label = $Top/PrepLabel
@onready var _start: Button = $Top/StartButton
@onready var _speed: Button = $Top/SpeedButton
@onready var _mute: Button = $Top/MuteButton
@onready var _volume_slider: HSlider = $Top/VolumeSlider
@onready var _message: Label = $Top/Message

var _board: GameBoard
var _message_timer := 0.0
var _fast := false

func _ready() -> void:
	_mute.pressed.connect(_toggle_mute)
	_volume_slider.value_changed.connect(_on_volume_changed)

func mute_button() -> Button:
	return _mute

func volume_slider() -> HSlider:
	return _volume_slider

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.lives_changed.connect(_on_lives_changed)
	board.wave_changed.connect(_on_wave_changed)
	board.wave_state_changed.connect(_on_wave_state_changed)
	board.placement_rejected.connect(_show_message)
	board.prep_changed.connect(_on_prep_changed)
	board.wave_reward.connect(_on_wave_reward)
	board.tower_placed.connect(func(_kind): _refresh_budget())
	board.tower_sold.connect(func(_kind): _refresh_budget())
	_start.pressed.connect(board.start_next_wave)
	_speed.pressed.connect(_toggle_speed)

	# Engine.time_scale is global and outlives reload_current_scene(), so a run
	# that ended at 2x would hand the next one double speed behind a button
	# reading 1x. Binding a HUD is the start of a run; reset it here.
	_fast = false
	_apply_speed()

	_on_gold_changed(board.get_gold())
	_on_lives_changed(board.get_lives())
	_on_wave_changed(board.get_wave(), Waves.MAX_WAVES)
	_message.text = ""
	_refresh_budget()
	_on_prep_changed(board.get_prep_remaining_ms(),
		EconomySim.call_early_bonus(board.get_prep_remaining_ms()))
	refresh_audio_controls()

func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message.text = ""

func _on_gold_changed(gold: int) -> void:
	_gold.text = "Gold %d" % gold

func _on_lives_changed(lives: int) -> void:
	_lives.text = "Lives %d" % lives

func _on_wave_changed(wave: int, max_waves: int) -> void:
	_wave.text = "Wave %d / %d" % [wave, max_waves]

func _on_wave_state_changed(active: bool) -> void:
	_start.disabled = active
	_start.text = "In progress" if active else "Start wave"

## The Start button doubles as the call-early button. One control, because
## they are one action: starting the next wave. The payout is on the label so
## the player can see what the decision is worth without a hover - this game
## is touch-first and hover does not exist on a phone.
func _on_prep_changed(remaining_ms: float, bonus: int) -> void:
	if remaining_ms <= 0.0:
		_prep.visible = false
		_prep.text = ""
		if _board != null and not _board.is_wave_active():
			_start.text = "Start wave"
		return
	_prep.visible = true
	_prep.text = "Next in %ds" % int(floor(remaining_ms / 1000.0))
	_start.text = "Call wave (+%d)" % bonus if bonus > 0 else "Call wave"

## Itemised, so the player can see WHY they were paid. A single total hides
## the fact that clearing fast and banking gold are two separate incentives.
func _on_wave_reward(base: int, speed: int, earned_interest: int) -> void:
	var parts := ["Wave cleared: +%d" % base]
	if speed > 0:
		parts.append("+%d fast" % speed)
	if earned_interest > 0:
		parts.append("+%d interest" % earned_interest)
	_show_message(" ".join(parts))

## The map budget is a cap across every kind, where the build panel shows the
## per-kind ones. Both are already enforced in GameBoard._try_place; this is
## the half the player could not see.
func _refresh_budget() -> void:
	if _board == null:
		return
	var total := int(Maps.get_def(_board.get_map_name())["tower_budget"])
	var used := 0
	for kind in Towers.KINDS:
		used += _board.get_tower_count(kind)
	_on_budget_changed(used, total)

func _on_budget_changed(used: int, total: int) -> void:
	_budget.text = "Towers %d/%d" % [used, total]

func _toggle_speed() -> void:
	_fast = not _fast
	_apply_speed()

func _apply_speed() -> void:
	var factor := FAST_TIME_SCALE if _fast else 1.0
	Engine.time_scale = factor
	_speed.text = _speed_label(factor)

## "Speed 1x", "Speed 1.5x". Derived from the multiplier rather than written
## beside it, so a change to FAST_TIME_SCALE cannot leave the button
## advertising the old number.
func _speed_label(factor: float) -> String:
	return "Speed %sx" % ("%.1f" % factor).trim_suffix(".0")

func _show_message(text: String) -> void:
	_message.text = text
	_message_timer = MESSAGE_SECONDS

func _toggle_mute() -> void:
	var mgr := _audio()
	if mgr == null:
		return
	mgr.set_muted(not mgr.is_muted())
	refresh_audio_controls()

func _on_volume_changed(value: float) -> void:
	var mgr := _audio()
	if mgr != null:
		mgr.set_volume(value)

## Pulls both controls back into line with the AudioManager's actual state.
##
## Called on bind rather than assumed at build time: the HUD scene ships with
## a full slider and an unmuted label, and the manager may already be at some
## other setting by the time the HUD exists.
func refresh_audio_controls() -> void:
	var mgr := _audio()
	if mgr == null:
		return
	_mute.text = "Sound off" if mgr.is_muted() else "Sound on"
	_volume_slider.set_value_no_signal(mgr.get_volume())

## Looks up the AudioManager autoload the same way GameBoard._play_sound
## does, and for the same reasons (see game/game_board.gd:414-441): by
## absolute path off the tree's own root rather than the bare global name,
## so this also resolves from a Hud that was never added to a live tree -
## every Hud the test harness builds, and calling get_node() directly on
## self in that state throws rather than returning null.
func _audio() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return loop.root.get_node_or_null("AudioManager")
