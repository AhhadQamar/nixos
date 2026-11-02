#!/usr/bin/env bash
# Download one track or one album/playlist with the same settings as the ytm
# aliases (yt-dlp/music.conf), printing progress lines the player reads:
#   PCT <percent> <playlist index> <playlist size>
#   ERROR: ...
#
#   dl.sh track <url | ytsearch1:words>
#   dl.sh album <playlist url | browse:<album browseId>>
mode=${1:-track}
target=$2
conf=${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp/music.conf
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec 2>&1

[ -n "$target" ] || { echo "ERROR: nothing to download"; exit 2; }

if [[ $target == browse:* ]]; then
  target=$(qs-music-py "$here/search.py" playlist-url "${target#browse:}") || exit 1
fi

args=(--ignore-config --config-locations "$conf" --no-colors --newline
  --progress-template "download:PCT %(progress._percent_str)s %(info.playlist_index)s %(info.n_entries)s")
if [ "$mode" = album ]; then
  args+=(--yes-playlist --parse-metadata "playlist_index:%(track_number)s")
else
  args+=(--no-playlist)
fi

yt-dlp "${args[@]}" -- "$target"
