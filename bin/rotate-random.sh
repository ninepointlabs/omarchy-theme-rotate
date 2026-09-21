#!/bin/bash
# Picks a random Omarchy theme (different from the current one, when more
# than one candidate is available), applies it, and prints:
#   action<TAB>theme
# action is "set" when the theme changed, "keep" when it did not.
#
# Options:
#   --only NAME    Restrict the pool to this theme; repeatable. No --only
#                  at all means every installed theme is eligible.
#   --follow-sun   Restrict the pool to light themes during the day and
#                  dark themes at night (sunrise/sunset via sun-status.sh).
#   --if-needed    Do nothing if the current theme is already inside the
#                  eligible pool (after --only and --follow-sun filtering).
#   --debounce-ms N  Keep the current theme if another run applied one less
#                  than N ms ago. Reading the current theme, deciding, and
#                  recording the result all happen under a lock, so several
#                  widget instances firing at the same instant still produce
#                  exactly one rotation.
#   --dry-run      Print the pick without applying it.
#   --classify     Print every installed theme and its light/dark mode.
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=theme-lib.sh
source "$PLUGIN_DIR/bin/theme-lib.sh"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-theme-rotate"
LOCK_FILE="$STATE_DIR/rotate.lock"
STAMP_FILE="$STATE_DIR/last-rotation-ms"

FOLLOW_SUN=0
IF_NEEDED=0
DRY_RUN=0
CLASSIFY=0
DEBOUNCE_MS=0
ONLY=()

while (( $# )); do
  case "$1" in
    --only)
      [[ $# -ge 2 ]] || { echo "--only needs a theme name" >&2; exit 2; }
      ONLY+=("$2")
      shift 2
      ;;
    --only=*) ONLY+=("${1#*=}"); shift ;;
    --debounce-ms)
      [[ $# -ge 2 ]] || { echo "--debounce-ms needs a number" >&2; exit 2; }
      DEBOUNCE_MS="$2"
      shift 2
      ;;
    --debounce-ms=*) DEBOUNCE_MS="${1#*=}"; shift ;;
    --follow-sun) FOLLOW_SUN=1; shift ;;
    --if-needed) IF_NEEDED=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --classify) CLASSIFY=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[[ $DEBOUNCE_MS =~ ^[0-9]+$ ]] || { echo "--debounce-ms must be a whole number of milliseconds" >&2; exit 2; }

now_ms() {
  date +%s%3N
}

# Serialize the whole decide-and-apply section across every caller, so the
# current theme this run reads can't be changed by another run mid-flight.
# Failing to take the lock keeps the theme rather than risking a second
# rotation on top of whoever is holding it.
take_lock() {
  mkdir -p "$STATE_DIR"
  exec 9>"$LOCK_FILE"
  flock -w 20 9
}

debounced() {
  local last now
  (( DEBOUNCE_MS > 0 )) || return 1
  [[ -f $STAMP_FILE ]] || return 1
  last=$(<"$STAMP_FILE")
  [[ $last =~ ^[0-9]+$ ]] || return 1
  now=$(now_ms)
  (( now - last < DEBOUNCE_MS ))
}

sun_want() {
  local period
  period=$("$PLUGIN_DIR/bin/sun-status.sh" | cut -f1)
  if [[ $period == day ]]; then
    printf '%s\n' light
  else
    printf '%s\n' dark
  fi
}

in_only() {
  local name="$1" allowed
  for allowed in "${ONLY[@]}"; do
    [[ $name == "$allowed" ]] && return 0
  done
  return 1
}

mapfile -t themes < <(omarchy theme list)

if (( CLASSIFY )); then
  for name in "${themes[@]}"; do
    slug=$(slugify "$name")
    printf '%s\t%s\t%s\n' "$name" "$slug" "$(theme_mode "$slug")"
  done
  exit 0
fi

if (( ! DRY_RUN )); then
  if ! take_lock; then
    printf 'keep\t%s\n' "$(omarchy theme current)"
    exit 0
  fi
fi

current="$(omarchy theme current)"

if debounced; then
  printf 'keep\t%s\n' "$current"
  exit 0
fi

# The user's chosen rotation set narrows the pool first; the sun filter then
# narrows that. An --only list naming nothing installed is ignored rather
# than left to strand the rotation on a single theme forever.
pool=("${themes[@]}")
if (( ${#ONLY[@]} > 0 )); then
  chosen=()
  for name in "${themes[@]}"; do
    in_only "$name" && chosen+=("$name")
  done
  if (( ${#chosen[@]} > 0 )); then
    pool=("${chosen[@]}")
  fi
fi

want=""
if (( FOLLOW_SUN )); then
  want=$(sun_want)
fi

candidates=()
for name in "${pool[@]}"; do
  slug=$(slugify "$name")
  if [[ -n $want && $(theme_mode "$slug") != "$want" ]]; then
    continue
  fi
  candidates+=("$name")
done

# If the sun-filtered pool is empty (no light themes selected, etc.), fall
# back to the chosen pool rather than getting stuck.
if (( ${#candidates[@]} == 0 )); then
  candidates=("${pool[@]}")
fi

current_in_pool=0
for name in "${candidates[@]}"; do
  if [[ $name == "$current" ]]; then
    current_in_pool=1
    break
  fi
done

if (( IF_NEEDED && current_in_pool )); then
  printf 'keep\t%s\n' "$current"
  exit 0
fi

if (( ${#candidates[@]} == 1 )); then
  pick="${candidates[0]}"
else
  pick="$current"
  # Prefer a different theme when we have a choice.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pick="${candidates[RANDOM % ${#candidates[@]}]}"
    [[ $pick != "$current" ]] && break
  done
fi

if [[ $pick == "$current" ]]; then
  printf 'keep\t%s\n' "$current"
  exit 0
fi

if (( DRY_RUN )); then
  printf 'set\t%s\n' "$pick"
  exit 0
fi

omarchy theme set "$pick"
printf '%s\n' "$(now_ms)" >"$STAMP_FILE"
printf 'set\t%s\n' "$pick"
