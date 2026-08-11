class_name Tiles

## The tile vocabulary, in one place. Every map shares TILE_SIZE.

const TILE_SIZE := 48

const BUILDABLE := &"buildable"
const PATH := &"path"
const BLOCKED := &"blocked"
const SPAWN := &"spawn"
const GOAL := &"goal"

## Tiles an enemy may walk over.
const WALKABLE: Array[StringName] = [PATH, SPAWN, GOAL]
