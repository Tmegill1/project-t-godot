extends Node

## Sounds the core slice can fire. Others exist in assets/audio and are wired
## by the phases that introduce their events.
##
## Two names below have no call site, both deliberate:
## - "ui-click": skipped on purpose. The HUD's only two buttons already
##   trigger "wave-start" and "sell" through the board; a separate click
##   sound here would double-fire on every press.
## - "explosion": unwired, and honestly so - neither the brief nor its
##   amendments ever assigned it a call site. Left present rather than
##   inventing a use for it; a later phase that needs it can wire it
##   deliberately.
const SOUNDS := [
	&"place", &"sell", &"denied", &"ui-click", &"wave-start", &"wave-clear",
	&"leak", &"victory", &"defeat", &"fire-basic", &"fire-fast",
	&"fire-mortar", &"fire-long", &"death-goblin", &"death-ogre",
	&"death-bat", &"death-shaman", &"death-troll",
	# boss.ogg has been in assets/audio since the core slice and was never in
	# this list, so the manager never loaded it and play(&"boss") was a silent
	# no-op. Registered now that something fires it.
	&"boss", &"explosion",
]

const POOL_SIZE := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _muted := false

## Volume as a linear 0..1, applied to the master bus.
##
## Stored linear rather than read back from the bus because linear_to_db(0.0)
## is -inf: silence is a level the bus can hold but not report in a form that
## converts back.
##
## The bus, not the players: the pool rotates through POOL_SIZE
## AudioStreamPlayers, so setting this per player would leave anything already
## playing at the old level and would need re-applying inside play(). The bus
## moves every voice at once, mid-playback included.
var _volume := 1.0

func _ready() -> void:
	for sound_name in SOUNDS:
		for ext in [".ogg", ".wav"]:
			var path := "res://assets/audio/%s%s" % [sound_name, ext]
			if ResourceLoader.exists(path):
				_streams[sound_name] = load(path)
				break
		if not _streams.has(sound_name):
			push_warning("missing sound: %s" % sound_name)

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

func play(sound: StringName) -> void:
	if _muted or not _streams.has(sound):
		return
	var player := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _streams[sound]
	player.play()

func set_muted(muted: bool) -> void:
	_muted = muted

func set_volume(linear: float) -> void:
	_volume = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_volume))

func get_volume() -> float:
	return _volume

## Whether play() is currently short-circuited. Independent of the volume:
## muting does not zero the level and unmuting does not restore a remembered
## one, so a player who adjusts the slider while muted gets what they chose.
func is_muted() -> bool:
	return _muted
