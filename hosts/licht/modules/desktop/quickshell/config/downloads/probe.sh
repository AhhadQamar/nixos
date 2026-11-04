#!/bin/sh
# Is this link a web page (a video may be on it) or a file? Prints one word:
#   page     an HTML page: hand it to yt-dlp
#   file     anything else the server sends as a download: hand it to aria2
#   unknown  the server did not say (offline, refused): treat as a file
url=$1
ua='Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0'

# The headers of the last hop, lower-cased, one "name: value" per line. First a
# HEAD request; some servers refuse that, so then a GET that stops at the headers.
last_block() {
  tr -d '\r' | awk 'BEGIN { RS = "" } { b = $0 } END { print tolower(b) }'
}
hdrs=$(curl -sIL -m 10 -A "$ua" -- "$url" 2>/dev/null | last_block)
status=$(printf '%s\n' "$hdrs" | head -n 1 | awk '{ print $2 }')
if [ -z "$status" ] || [ "$status" -ge 400 ] 2>/dev/null; then
  hdrs=$(curl -sL -m 8 -r 0-0 --max-filesize 1 -A "$ua" -D - -o /dev/null -- "$url" 2>/dev/null | last_block)
  status=$(printf '%s\n' "$hdrs" | head -n 1 | awk '{ print $2 }')
fi
if [ -z "$status" ] || [ "$status" -ge 400 ] 2>/dev/null; then
  echo unknown
  exit 0
fi

ctype=$(printf '%s\n' "$hdrs" | sed -n 's/^content-type: *//p' | head -n 1)
if printf '%s\n' "$hdrs" | grep -q '^content-disposition: *attachment'; then
  echo file
elif [ -z "$ctype" ]; then
  echo unknown
else
  case "$ctype" in
    text/html*|application/xhtml*) echo page ;;
    *) echo file ;;
  esac
fi
