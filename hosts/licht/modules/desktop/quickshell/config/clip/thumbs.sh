#!/usr/bin/env bash
# Decode the newest image entries of the clipboard history into files the panel
# can show as thumbnails, once each. Prints the id of every image that is ready.
#   $1 output directory   $2 how many image entries to look at (default 24)
out=${1:?output directory}
max=${2:-24}
mkdir -p "$out"
# Forget thumbnails nobody has asked for in a day
find "$out" -type f -mtime +1 -delete 2>/dev/null || true
cliphist list | grep -m "$max" -E $'^[0-9]+\t\\[\\[ binary data' | while IFS=$'\t' read -r id _; do
  f="$out/$id.img"
  [ -s "$f" ] || cliphist decode "$id" > "$f" 2>/dev/null || rm -f "$f"
  [ -s "$f" ] && printf '%s\n' "$id"
done
exit 0
