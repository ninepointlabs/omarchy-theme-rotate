#!/bin/bash
# Picks a random Omarchy theme (different from the current one, when more
# than one theme is installed), applies it, and prints the name that was
# picked so the caller can display/persist it.
set -euo pipefail

current="$(omarchy theme current)"
mapfile -t themes < <(omarchy theme list)

if [ "${#themes[@]}" -le 1 ]; then
  pick="${themes[0]:-}"
else
  pick="$current"
  while [ "$pick" == "$current" ]; do
    pick="${themes[RANDOM % ${#themes[@]}]}"
  done
fi

omarchy theme set "$pick"
printf '%s' "$pick"
