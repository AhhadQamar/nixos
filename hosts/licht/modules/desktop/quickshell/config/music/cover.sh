#!/usr/bin/env bash
# Print the path of cover art for the audio file $1, or nothing.
# A cover/folder image next to the file wins; otherwise the art embedded in
# the file is extracted once into the runtime dir.
f=$1
d=$(dirname "$f")
for n in cover folder front album Cover Folder Front Album; do
  for e in jpg jpeg png webp; do
    [ -f "$d/$n.$e" ] && { echo "$d/$n.$e"; exit 0; }
  done
done
out="${XDG_RUNTIME_DIR:-/tmp}/qs-music/cover-$(printf '%s' "$f" | md5sum | cut -c1-12).jpg"
mkdir -p "$(dirname "$out")"
[ -s "$out" ] && { echo "$out"; exit 0; }
command -v ffmpeg >/dev/null 2>&1 || exit 0
ffmpeg -v error -y -i "$f" -an -frames:v 1 "$out" 2>/dev/null
[ -s "$out" ] && echo "$out"
exit 0
