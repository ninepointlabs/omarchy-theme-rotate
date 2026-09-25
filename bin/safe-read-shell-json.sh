#!/bin/bash
# Prints ~/.config/omarchy/shell.json on stdout, but only when that path is
# still an ordinary, reasonably sized config file.
#
# The widget reads this file live (see "authoritative settings" in Panel.qml),
# from a shell process that stays up for the whole session. Reading the path
# directly would mean whatever sits there gets loaded: a symlink would make
# the shell follow a file the user never pointed it at, a FIFO or device node
# would block it indefinitely on open, and an oversized file would be pulled
# into memory whole. None of those are normal states for a config file, so
# this script refuses them instead of reading.
#
# Contract, relied on by Panel.qml:
#   - missing file  -> exit 0, empty stdout (normal on first run)
#   - refused path  -> non-zero exit, empty stdout, one line on stderr
#   - otherwise     -> exit 0, file contents on stdout
# Either empty-stdout case leaves the widget on its injected settings
# snapshot, which is the same fallback an unreadable file had before.
#
# Nothing about the *contents* is checked here, and a refusal never echoes
# them; parsing stays in SettingsMerge.js, which already returns null for
# anything unparseable.
set -euo pipefail

# 512 KiB. A real shell.json is a few kilobytes — this is a backstop against
# an unbounded read, not a limit anyone should reach. Enforced twice: once up
# front against the file's size, and again on the read itself, so a file that
# grows between the two still cannot stream more than this.
readonly MAX_BYTES=524288

CONFIG="$HOME/.config/omarchy/shell.json"

refuse() {
  printf 'safe-read-shell-json: refusing to read %s: %s\n' "$CONFIG" "$1" >&2
  exit 1
}

# Symlinks first: -e and -f both follow the link, so they would report on the
# target rather than on the path that was actually replaced.
[[ -L $CONFIG ]] && refuse "path is a symlink"

# Missing is a normal first-run state, not something to report.
[[ -e $CONFIG ]] || exit 0

[[ -f $CONFIG ]] || refuse "path is not a regular file"

size=$(stat -c %s -- "$CONFIG")
(( size <= MAX_BYTES )) || refuse "file is $size bytes, over the $MAX_BYTES byte cap"

head -c "$MAX_BYTES" -- "$CONFIG"
