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
	&"fire-mortar", &"fire-long", &"death-slime", &"death-ogre",
	&"death-bee", &"explosion",
]

const POOL_SIZE := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _muted := false

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
