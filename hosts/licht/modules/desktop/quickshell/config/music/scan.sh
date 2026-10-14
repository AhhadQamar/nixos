#!/usr/bin/env bash
# List the audio files under $1 (default ~/Music), one per line:
#   path <TAB> artist <TAB> album <TAB> title <TAB> track number
# Tags come from ffprobe when it exists; otherwise (or when a tag is empty)
# they are read from the folder layout: Artist/Album/01 Title.ext
# Results are cached by path, size and modification time, so only new or
# changed files are probed again: the first scan of a big library takes a
# while, every later one is nearly instant. Delete the cache to force a full
# re-read ($QS_MUSIC_CACHE, default ~/.cache/quickshell/music-index.tsv).
dir=${1:-$HOME/Music}
cache=${QS_MUSIC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/music-index.tsv}
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

mkdir -p "$(dirname "$cache")" 2>/dev/null
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Cache lines: mtime <TAB> size <TAB> path <TAB> artist <TAB> album <TAB> title <TAB> track
declare -A hit
if [ -f "$cache" ]; then
  while IFS= read -r line; do
    m=${line%%$'\t'*}
    r=${line#*$'\t'}
    s=${r%%$'\t'*}
    r=${r#*$'\t'}
    p=${r%%$'\t'*}
    hit["$m|$s|$p"]=$r
  done <"$cache"
fi

: >"$tmp/new.list" # NUL-separated paths that still need probing
: >"$tmp/keep.tsv" # cache lines that are still valid, plus the new ones
declare -A meta
while IFS= read -r -d '' rec; do
  m=${rec%%$'\t'*}
  r=${rec#*$'\t'}
  m=${m%.*}
  s=${r%%$'\t'*}
  p=${r#*$'\t'}
  if [ -n "${hit["$m|$s|$p"]+x}" ]; then
    printf '%s\n' "${hit["$m|$s|$p"]}"
    printf '%s\t%s\t%s\n' "$m" "$s" "${hit["$m|$s|$p"]}" >>"$tmp/keep.tsv"
  else
    printf '%s\0' "$p" >>"$tmp/new.list"
    meta["$p"]="$m"$'\t'"$s"
  fi
done < <(find -L "$dir" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \
  -o -iname '*.m4a' -o -iname '*.wav' -o -iname '*.aac' -o -iname '*.wma' \) -printf '%T@\t%s\t%p\0')

if [ -s "$tmp/new.list" ]; then
  # Probe in parallel; results stream out as they finish and are kept for next time
  xargs -0 -r -n 1 -P 6 bash -c 'one "$1"' _ <"$tmp/new.list" | tee "$tmp/new.tsv"
  while IFS= read -r line; do
    p=${line%%$'\t'*}
    printf '%s\t%s\n' "${meta["$p"]}" "$line" >>"$tmp/keep.tsv"
  done <"$tmp/new.tsv"
fi

mv -f "$tmp/keep.tsv" "$cache" 2>/dev/null
exit 0
