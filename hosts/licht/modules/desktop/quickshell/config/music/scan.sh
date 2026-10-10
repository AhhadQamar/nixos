#!/usr/bin/env bash
# List the audio files under $1 (default ~/Music), one per line:
#   path <TAB> artist <TAB> album <TAB> title <TAB> track number
# Tags come from ffprobe when it exists; otherwise (or when a tag is empty)
# they are read from the folder layout: Artist/Album/01 Title.ext
dir=${1:-$HOME/Music}
export dir

one() {
  local f=$1 rel parts n title album="" artist="" track="" k v
  rel=${f#"$dir"/}
  IFS=/ read -ra parts <<<"$rel"
  n=${#parts[@]}
  title=${parts[n-1]%.*}
  title=$(sed -E 's/^[0-9]+[ ._-]+//' <<<"$title")
  track=$(sed -nE 's/^([0-9]+)[ ._-].*/\1/p' <<<"${parts[n-1]}")
  [ "$n" -ge 2 ] && album=${parts[n-2]}
  [ "$n" -ge 3 ] && artist=${parts[n-3]}
  if command -v ffprobe >/dev/null 2>&1; then
    while IFS== read -r k v; do
      v=${v//$'\t'/ }
      [ -n "$v" ] || continue
      case "${k,,}" in
        tag:title) title=$v ;;
        tag:artist) artist=$v ;;
        tag:album) album=$v ;;
        tag:track) track=${v%%/*} ;;
      esac
    done < <(ffprobe -v error -show_entries format_tags=title,artist,album,track -of default=noprint_wrappers=1 "$f" 2>/dev/null)
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$artist" "$album" "$title" "$track"
}
export -f one

find -L "$dir" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \
  -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.aac' -o -iname '*.wma' \) -print0 \
  | xargs -0 -r -n 1 -P 6 bash -c 'one "$1"' _
