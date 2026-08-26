class_name BuildStamp

## Which build this is. Shown in the corner of the main menu.
##
## This file is a TEMPLATE and is committed with placeholder values. The
## deploy workflow overwrites it with the real commit SHA immediately before
## exporting, so a shipped build identifies itself and a local run says "dev".
## Nothing regenerates it for a local `godot --path .` run, which is exactly
## what makes "dev" meaningful.
##
## It exists because we could not tell which build a browser was actually
## running. A cached index.pck looks identical to a fresh one from the
## outside, and answering "which version am I looking at?" took downloading
## the pack and parsing it in a headless engine. One label in the corner
## replaces all of that.
##
## Keep the constant names and types stable: .github/workflows/deploy-pages.yml
## rewrites this file by generating it wholesale, so a rename here needs the
## same rename there.

## Short commit SHA the build came from, or "dev" for an unstamped local run.
const SHA := "dev"

## When the build was exported, ISO-8601 UTC, or "" locally.
const BUILT_AT := ""

## What to show the player. Deliberately terse - this is a diagnostic, not a
## feature, and it should not compete with the title for attention.
static func label() -> String:
	if SHA == "dev":
		return "dev build"
	if BUILT_AT == "":
		return "build %s" % SHA
	return "build %s · %s" % [SHA, BUILT_AT]
