#!/bin/bash
# Prints the current solar period for this machine, using the same location
# source as Omarchy weather (stored weather.json, otherwise wttr.in by IP).
#
# Output (tab-separated, one line):
#   period  sunrise  sunset  source
# period is "day" or "night". Times are local 12-hour clocks from wttr
# (e.g. "06:54 AM"). source is "wttr", "cache", or "fallback".
#
# Caches today's sunrise/sunset under XDG_CACHE_HOME so a once-a-minute
# caller does not hit the network every time. Falls back to 06:00–18:00
# local if wttr is unreachable and there is no cache yet.
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-rotate"
CACHE_FILE="$CACHE_DIR/sun.tsv"
TODAY="$(date +%F)"

period_from_times() {
  local sunrise="$1" sunset="$2"
  local now sunrise_epoch sunset_epoch
  now=$(date +%s)
  sunrise_epoch=$(date -d "today $sunrise" +%s 2>/dev/null || echo 0)
  sunset_epoch=$(date -d "today $sunset" +%s 2>/dev/null || echo 0)
  if (( sunrise_epoch > 0 && sunset_epoch > 0 && (now < sunrise_epoch || now >= sunset_epoch) )); then
    printf '%s\n' night
  else
    printf '%s\n' day
  fi
}

print_row() {
  local period sunrise sunset source
  period=$(period_from_times "$1" "$2")
  printf '%s\t%s\t%s\t%s\n' "$period" "$1" "$2" "$3"
}

read_cache() {
  local date sunrise sunset
  [[ -f $CACHE_FILE ]] || return 1
  IFS=$'\t' read -r date sunrise sunset <"$CACHE_FILE" || return 1
  [[ $date == "$TODAY" && -n $sunrise && -n $sunset ]] || return 1
  print_row "$sunrise" "$sunset" cache
}

write_cache() {
  mkdir -p "$CACHE_DIR"
  printf '%s\t%s\t%s\n' "$TODAY" "$1" "$2" >"$CACHE_FILE"
}

fetch_wttr() {
  local query="" location weather_data sunrise sunset
  if [[ -s $HOME/.local/state/omarchy/settings/weather.json ]]; then
    location=$(omarchy weather location 2>/dev/null || true)
    [[ -n $location ]] && query=$(jq -rn --arg location "$location" '$location | @uri')
  fi
  weather_data=$(curl -fsS --max-time 4 "https://wttr.in/${query}?format=j1" 2>/dev/null \
    | jq -er '[.weather[0].astronomy[0].sunrise, .weather[0].astronomy[0].sunset]
              | select(all(. != null and . != "")) | @tsv' 2>/dev/null) || return 1
  IFS=$'\t' read -r sunrise sunset <<<"$weather_data"
  [[ $sunrise =~ ^[0-9]{1,2}:[0-9]{2}\ [AP]M$ && $sunset =~ ^[0-9]{1,2}:[0-9]{2}\ [AP]M$ ]] || return 1
  write_cache "$sunrise" "$sunset"
  print_row "$sunrise" "$sunset" wttr
}

if row=$(read_cache); then
  printf '%s\n' "$row"
  exit 0
fi

if row=$(fetch_wttr); then
  printf '%s\n' "$row"
  exit 0
fi

# Last resort: 6am–6pm local so the feature still does something offline.
print_row "06:00 AM" "06:00 PM" fallback
