#!/bin/bash
# Shared theme helpers for the Theme Rotate scripts. Sourced, never run
# directly: rotate-random.sh needs light/dark classification to honor
# "follow the sun", and list-themes.sh needs the same classification plus
# a wallpaper for the picker overlay. Keeping one copy means the picker
# can never disagree with the rotator about what a theme is.

OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
USER_THEMES_PATH="$HOME/.config/omarchy/themes"

# "Rose Pine" -> "rose-pine", matching the on-disk theme directory names
# that `omarchy theme list` pretty-prints from.
slugify() {
  echo "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# User themes shadow the ones shipped with Omarchy, same as the CLI.
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

theme_toml_value() {
  local slug="$1" key="$2" colors
  colors="$(theme_dir "$slug")/colors.toml"
  [[ -f $colors ]] || return 0
  grep -E "^${key}[[:space:]]*=" "$colors" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true
}

# A theme's background color as #rrggbb, or empty when colors.toml has none.
theme_color() {
  local hex
  hex=$(theme_toml_value "$1" background)
  [[ $hex =~ ^#[0-9A-Fa-f]{6}$ ]] && printf '%s\n' "$hex"
}

# light/dark for a theme. Prefers the declared `mode`, falls back to the
# luminance of the background color, and assumes dark when neither is
# readable so an odd theme never lands in the daytime pool by accident.
theme_mode() {
  local slug="$1" mode hex y
  mode=$(theme_toml_value "$slug" mode)
  if [[ $mode == light || $mode == dark ]]; then
    printf '%s\n' "$mode"
    return
  fi
  hex=$(theme_color "$slug")
  if [[ -n $hex ]]; then
    y=$(hex_luminance "$hex" 2>/dev/null || echo 0)
    if python3 -c "import sys; sys.exit(0 if float('$y') > 0.5 else 1)" 2>/dev/null; then
      printf '%s\n' light
      return
    fi
  fi
  printf '%s\n' dark
}

# The image that represents a theme in the picker: its first wallpaper,
# falling back to the theme preview. Empty when a theme ships neither.
theme_image() {
  local slug="$1" dir candidate
  dir=$(theme_dir "$slug")
  if [[ -d $dir/backgrounds ]]; then
    while IFS= read -r candidate; do
      [[ -f $candidate ]] || continue
      case "${candidate,,}" in
        *.png|*.jpg|*.jpeg|*.webp|*.gif|*.bmp) printf '%s\n' "$candidate"; return ;;
      esac
    done < <(printf '%s\n' "$dir"/backgrounds/* | sort)
  fi
  [[ -f $dir/preview.png ]] && printf '%s\n' "$dir/preview.png"
}
