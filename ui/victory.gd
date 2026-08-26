extends CanvasLayer

## Victory screen: shown by Game when the final wave is cleared. Its copy
## deliberately reads as a win, not "You held until wave %d of %d." - on this
## screen `wave_reached` is always Waves.MAX_WAVES, and that line would read
## as though the player fell short at the last wave (see
## task-20-21-amendments.md, Task 21 amendment 2).

var wave_reached := 0

## Which map was just cleared. Set by game/game.gd before this enters the
## tree, so it is in place by the time _ready reads it - the same ordering
## wave_reached already relies on. Defaults to the first map so a
## standalone instantiation still behaves.
var completed_map: StringName = Maps.FIRST

@onready var _summary: Label = $Panel/Summary
@onready var _next: Button = $Panel/NextMap
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/MainMenu

func _ready() -> void:
	_summary.text = "You cleared all %d waves." % Waves.MAX_WAVES
	_refresh_next_map()
	_next.pressed.connect(func():
		queue_next_map()
		get_tree().reload_current_scene())
	_retry.pressed.connect(func(): get_tree().reload_current_scene())
	_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/main_menu.tscn"))

func next_map_button() -> Button:
	return _next

## The map that follows the one just cleared, or empty when this was the last.
func next_map() -> StringName:
	return Maps.get_def(completed_map).get("next", &"")

## Shows the button only when there is somewhere to go, and names the
## destination - "Next map" alone tells the player nothing about what they
## just unlocked.
func _refresh_next_map() -> void:
	var following := next_map()
	_next.visible = following != &""
	if _next.visible:
		_next.text = "Next: %s" % Maps.get_def(following)["label"]

## Queues the following map for the board that comes up after the reload.
##
## Separate from the button press so a test can exercise it without a live
## tree - reload_current_scene() needs one and there is none in the harness.
func queue_next_map() -> void:
	var following := next_map()
	if following != &"":
		GameBoard.pending_map = following
