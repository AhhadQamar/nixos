# shellcheck shell=bash
# Recolor the Papirus folder icons to match the wallpaper accent.
#
#   recolor-icons           run by hand after `wal -i`: always re-applies, then asks Nautilus to quit
#   recolor-icons --quiet   run by Home Manager on every switch: silent, and does nothing when
#                           neither the wallpaper accent nor the Papirus package has changed
#
# PAPIRUS_SRC is set by theme/default.nix to the papirus-icon-theme share/icons directory.

: "${PAPIRUS_SRC:?PAPIRUS_SRC is set by theme/default.nix}"

quiet=0
if [ "${1:-}" = "--quiet" ]; then quiet=1; fi

say() {
  if [ "$quiet" -eq 0 ]; then echo "$@"; fi
}

icons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors"
source_stamp="$icons_dir/.papirus-source"
preset_stamp="$icons_dir/.papirus-preset"

# Same rule as Colors.qml's _pickAccent(): of color1..color6, take the one with
# the highest saturation * (1 - |value - 0.65|). Prints "#rrggbb", or fails if
# the file has no usable colour.
pick_accent() {
  local -a lines
  local best="" best_score=-1 i hex r g b max min sat dist score
  mapfile -t lines <"$colors_file"
  for i in 1 2 3 4 5 6; do
    hex="${lines[$i]:-}"
    hex="${hex#\#}"
    [[ $hex =~ ^[0-9a-fA-F]{6}$ ]] || continue
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    max=$r
    min=$r
    if ((g > max)); then max=$g; fi
    if ((b > max)); then max=$b; fi
    if ((g < min)); then min=$g; fi
    if ((b < min)); then min=$b; fi
    sat=0
    if ((max > 0)); then sat=$(((max - min) * 1000 / max)); fi
    if ((max > 166)); then dist=$((max - 166)); else dist=$((166 - max)); fi
    score=$((sat * (1000 - dist * 1000 / 255) / 1000))
    if ((score > best_score)); then
      best_score=$score
      best="#$hex"
    fi
  done
  [ -n "$best" ] || return 1
  echo "$best"
}

# Split "#rrggbb" into HSV_H (0-359), HSV_S and HSV_V (0-100).
to_hsv() {
  local hex="${1#\#}" r g b max min d
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))
  max=$r
  min=$r
  if ((g > max)); then max=$g; fi
  if ((b > max)); then max=$b; fi
  if ((g < min)); then min=$g; fi
  if ((b < min)); then min=$b; fi
  d=$((max - min))
  if ((d == 0)); then
    HSV_H=0
  elif ((max == r)); then
    HSV_H=$(((60 * (g - b) / d + 360) % 360))
  elif ((max == g)); then
    HSV_H=$((60 * (b - r) / d + 120))
  else
    HSV_H=$((60 * (r - g) / d + 240))
  fi
  HSV_S=0
  if ((max > 0)); then HSV_S=$((d * 100 / max)); fi
  HSV_V=$((max * 100 / 255))
}

# Pick the Papirus folder preset for an accent. Hue decides; saturation and
# brightness only break ties (a bright orange is "deeporange", a muted tan is
# "brown"). The table holds the real main colour of each folder-<name>.svg in
# Papirus, so hues are what the icons really look like. Matching raw RGB
# distance instead turned pastel greens and pinks into tan folders. The style
# presets (adwaita, breeze, nordic, yaru) and white/palebrown are left out.
nearest_preset() {
  local name hex dh ds dv d best=grey best_d=2147483647 acc_h acc_s acc_v
  to_hsv "$1"
  acc_h=$HSV_H
  acc_s=$HSV_S
  acc_v=$HSV_V
  # Too grey for a hue to mean anything: choose by brightness.
  if ((acc_s < 15)); then
    if ((acc_v < 40)); then echo black; else echo grey; fi
    return
  fi
  while read -r name hex; do
    to_hsv "$hex"
    dh=$((acc_h - HSV_H))
    if ((dh < 0)); then dh=$((-dh)); fi
    if ((dh > 180)); then dh=$((360 - dh)); fi
    ds=$((acc_s - HSV_S))
    dv=$((acc_v - HSV_V))
    d=$((dh * dh * 100 + 15 * (ds * ds + dv * dv)))
    if ((d < best_d)); then
      best_d=$d
      best=$name
    fi
  done <<'TABLE'
red        bf4b4b
deeporange e95420
orange     dd772f
brown      957552
paleorange c89e6b
yellow     e19d00
green      60924b
teal       12806a
darkcyan   35818a
cyan       0096aa
bluegrey   4d646f
blue       4877b1
indigo     3f51b5
violet     5d399b
magenta    b259b8
pink       ec407a
carmine    7a0002
TABLE
  echo "$best"
}

# 1. Keep a writable copy of the theme in ~/.local/share/icons (papirus-folders
#    edits the theme in place, and the store is read-only). Copy again whenever
#    the Papirus package changes, so updates are not ignored.
changed=0
mkdir -p "$icons_dir"
copied_from=$(cat "$source_stamp" 2>/dev/null || true)
for variant in Papirus Papirus-Dark; do
  target="$icons_dir/$variant"
  if [ ! -d "$target" ] || [ ! -w "$target" ] || [ "$copied_from" != "$PAPIRUS_SRC" ]; then
    say "Copying $variant..."
    chmod -R u+w "$target" 2>/dev/null || true
    rm -rf "$target"
    cp -r --no-preserve=mode "$PAPIRUS_SRC/$variant" "$target"
    changed=1
  fi
done
echo "$PAPIRUS_SRC" >"$source_stamp"

# 2. Work out the folder colour for the current wallpaper.
if [ ! -s "$colors_file" ]; then
  say "No wal colors found. Run 'wal -i <wallpaper>' first."
  if [ "$quiet" -eq 1 ]; then exit 0; fi
  exit 1
fi
accent=$(pick_accent) || {
  say "No usable accent colour in $colors_file"
  exit 0
}
preset=$(nearest_preset "$accent")
say "Accent: $accent -> $preset"

# 3. Apply it, unless this is a silent run and nothing changed.
last=$(cat "$preset_stamp" 2>/dev/null || true)
if [ "$quiet" -eq 1 ] && [ "$changed" -eq 0 ] && [ "$last" = "$preset" ]; then
  exit 0
fi
if [ "$quiet" -eq 1 ]; then
  papirus-folders -C "$preset" --theme Papirus >/dev/null
else
  papirus-folders -C "$preset" --theme Papirus
fi
for variant in Papirus Papirus-Dark; do
  gtk-update-icon-cache -f "$icons_dir/$variant" 2>/dev/null || true
done
echo "$preset" >"$preset_stamp"

if [ "$quiet" -eq 0 ]; then
  nautilus -q 2>/dev/null || true
  echo "Done."
fi
