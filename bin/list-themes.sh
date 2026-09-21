#!/bin/bash
# Lists every installed Omarchy theme for the picker overlay, one per line:
#
#   name<TAB>slug<TAB>mode<TAB>image<TAB>background
#
# mode is "light" or "dark", image is an absolute path to the theme's first
# wallpaper (empty when it has none), and background is the theme's #rrggbb
# background color (empty when colors.toml doesn't declare one), used as the
# placeholder tile for imageless themes.
#
# TSV rather than JSON so the widget parses it with a split() and the script
# keeps working without jq.
set -euo pipefail

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=theme-lib.sh
source "$PLUGIN_DIR/bin/theme-lib.sh"

mapfile -t themes < <(omarchy theme list)

for name in "${themes[@]}"; do
  [[ -n $name ]] || continue
  slug=$(slugify "$name")
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$slug" "$(theme_mode "$slug")" "$(theme_image "$slug")" "$(theme_color "$slug")"
done
