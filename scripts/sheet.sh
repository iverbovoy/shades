#!/bin/bash
# Render a contact sheet of the wall: every theme at a few times of day, taken
# from the running shell. Your settings and the time preview are put back
# afterwards.
#
#   scripts/sheet.sh [out.jpg] [theme ...]
set -euo pipefail

out=${1:-/tmp/shades-sheet.jpg}
shift || true
config=$HOME/.config/shades/config.json
work=$(mktemp -d)
ipc() { omarchy-shell shades "$@"; }

[ -f "$config" ] && cp "$config" "$work/config.json"
preview=$(ipc preview)
restore() {
  [ -f "$work/config.json" ] && cp "$work/config.json" "$config"
  sleep 0.5
  if [ "${preview%%.*}" -lt 0 ] 2>/dev/null; then ipc follow; else ipc time "$preview"; fi
  rm -rf "$work"
}
trap restore EXIT

themes=("$@")
[ ${#themes[@]} -gt 0 ] || read -ra themes <<<"$(ipc theme '')"
hours=(8.5 12 15.5 23)

# a clear sky and the light as the themes have it, with nothing passing by,
# so that sheets can be compared from day to day and from one desk to another
plain() {
  ipc set overcast '"off"'; ipc set rain false; ipc set motion '""'
  ipc set brightness 1; ipc set softness 1; ipc set tint '""'
  ipc set blindsFollow '"none"'; ipc set windowShadows false
  ipc set visitors false; ipc set headlights false; ipc set text false
}
plain >/dev/null
sleep 4.5 # the clouds take their time to part

n=0
for theme in "${themes[@]}"; do
  ipc theme "$theme" >/dev/null
  sleep 1.2 # the blinds shut and open on the new theme
  for hour in "${hours[@]}"; do
    ipc time "$hour"
    sleep 0.9
    shot=$work/$(printf %03d $n).png
    ipc snapshot "$shot"
    sleep 0.9
    n=$((n + 1))
  done
done

ffmpeg -loglevel error -y -framerate 1 -i "$work/%03d.png" \
  -vf "scale=640:-1,tile=${#hours[@]}x${#themes[@]}:padding=4" -frames:v 1 -q:v 3 "$out"
echo "$out"
