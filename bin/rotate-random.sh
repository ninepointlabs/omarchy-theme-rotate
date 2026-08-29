#!/bin/bash
# Picks a random Omarchy theme (different from the current one, when more
# than one candidate is available), applies it, and prints:
#   action<TAB>theme
# action is "set" when the theme changed, "keep" when it did not.
#
# Options:
#   --follow-sun   Restrict the pool to light themes during the day and
#                  dark themes at night (sunrise/sunset via sun-status.sh).
#   --if-needed    With --follow-sun, do nothing if the current theme is
#                  already in the correct pool.
#   --dry-run      Print the pick without applying it.
#   --classify     Print every installed theme and its light/dark mode.
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
USER_THEMES_PATH="$HOME/.config/omarchy/themes"

FOLLOW_SUN=0
IF_NEEDED=0
DRY_RUN=0
CLASSIFY=0

for arg in "$@"; do
  case "$arg" in
    --follow-sun) FOLLOW_SUN=1 ;;
    --if-needed) IF_NEEDED=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --classify) CLASSIFY=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

slugify() {
  echo "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

theme_dir() {
  local slug="$1"
  if [[ -d $USER_THEMES_PATH/$slug ]]; then
    printf '%s\n' "$USER_THEMES_PATH/$slug"
  else
    printf '%s\n' "$OMARCHY_THEMES_PATH/$slug"
  fi
}

hex_luminance() {
  python3 - "$1" <<'PY'
import sys
h = sys.argv[1].lstrip("#")
if len(h) != 6:
    print("0")
    raise SystemExit
r, g, b = int(h[0:2], 16)/255, int(h[2:4], 16)/255, int(h[4:6], 16)/255
def lin(c):
    return c/12.92 if c <= 0.04045 else ((c + 0.055)/1.055) ** 2.4
print(0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b))
PY
}

theme_mode() {
  local slug="$1" dir colors mode hex y
  dir=$(theme_dir "$slug")
  colors="$dir/colors.toml"
  if [[ -f $colors ]]; then
    mode=$(grep -E '^mode[[:space:]]*=' "$colors" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [[ $mode == light || $mode == dark ]]; then
      printf '%s\n' "$mode"
      return
    fi
    hex=$(grep -E '^background[[:space:]]*=' "$colors" | head -1 | sed -E 's/.*#([0-9A-Fa-f]{6}).*/\1/' || true)
    if [[ $hex =~ ^[0-9A-Fa-f]{6}$ ]]; then
      y=$(hex_luminance "$hex" 2>/dev/null || echo 0)
      if python3 -c "import sys; sys.exit(0 if float('$y') > 0.5 else 1)" 2>/dev/null; then
        printf '%s\n' light
        return
      fi
    fi
  fi
  printf '%s\n' dark
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

mapfile -t themes < <(omarchy theme list)

if (( CLASSIFY )); then
  for name in "${themes[@]}"; do
    slug=$(slugify "$name")
    printf '%s\t%s\t%s\n' "$name" "$slug" "$(theme_mode "$slug")"
  done
  exit 0
fi

current="$(omarchy theme current)"
want=""
if (( FOLLOW_SUN )); then
  want=$(sun_want)
fi

candidates=()
for name in "${themes[@]}"; do
  slug=$(slugify "$name")
  if [[ -n $want && $(theme_mode "$slug") != "$want" ]]; then
    continue
  fi
  candidates+=("$name")
done

# If the sun-filtered pool is empty (no light themes installed, etc.),
# fall back to the full list rather than getting stuck.
if (( ${#candidates[@]} == 0 )); then
  candidates=("${themes[@]}")
fi

current_in_pool=0
for name in "${candidates[@]}"; do
  if [[ $name == "$current" ]]; then
    current_in_pool=1
    break
  fi
done

if (( FOLLOW_SUN && IF_NEEDED && current_in_pool )); then
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
printf 'set\t%s\n' "$pick"
