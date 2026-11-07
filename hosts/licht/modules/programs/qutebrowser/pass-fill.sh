# Fill a login from `pass` into the focused field of the current page.
# Run from qutebrowser:  spawn --userscript qute-pass-fill [both|user|pass|otp]
#
# Entries are matched by site name: an entry named  github.com/licht  or
# github.com  is offered on github.com and on any sub-domain of it.
set -u

mode="${1:-both}"
store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

say() { printf '%s\n' "$1" >> "$QUTE_FIFO"; }
fail() { say "message-error '$1'"; exit 0; }

# --- Which site are we on? -------------------------------------------------
host="${QUTE_URL#*://}"
host="${host%%/*}"
host="${host%%:*}"
host="${host#www.}"
[ -n "$host" ] || fail "No site in this page"

# accounts.google.com -> accounts.google.com, google.com
cands=()
h="$host"
while :; do
  cands+=("$h")
  case "$h" in
    *.*.*) h="${h#*.}" ;;
    *) break ;;
  esac
done

# --- Find matching entries -------------------------------------------------
mapfile -t all < <(cd "$store" 2>/dev/null && find . -name '*.gpg' -type f | sed 's|^\./||; s|\.gpg$||' | sort)

matches=()
for e in "${all[@]}"; do
  for cand in "${cands[@]}"; do
    case "/$e/" in
      */"$cand"/*)
        matches+=("$e")
        break
        ;;
    esac
  done
done

[ "${#matches[@]}" -gt 0 ] || fail "No pass entry for $host. Name one $host/username"

if [ "${#matches[@]}" -eq 1 ]; then
  entry="${matches[0]}"
else
  args=()
  cfg="$HOME/.cache/wal/colors-fuzzel.ini"
  [ -f "$cfg" ] && args=(--config "$cfg")
  entry="$(printf '%s\n' "${matches[@]}" | fuzzel --dmenu "${args[@]}" 2>/dev/null)" || exit 0
  [ -n "$entry" ] || exit 0
fi

# --- Read it (gpg may ask for the passphrase here) --------------------------
content="$(pass show "$entry" 2>/dev/null)" || fail "Could not open $entry"
password="${content%%$'\n'*}"

user="$(printf '%s\n' "$content" | sed -n -E 's/^(user|username|login|email)[[:space:]]*:[[:space:]]*//Ip' | head -n 1)"
if [ -z "$user" ]; then
  case "$entry" in
    */*) user="${entry##*/}" ;;
  esac
fi

# --- Type it into the page --------------------------------------------------
type_text() {
  local text="$1" i ch
  for ((i = 0; i < ${#text}; i++)); do
    ch="${text:i:1}"
    if [ "$ch" = " " ]; then
      say 'fake-key " "'
    else
      say "fake-key \\$ch"
    fi
  done
}

case "$mode" in
  user)
    [ -n "$user" ] || fail "No username in $entry"
    type_text "$user"
    ;;
  pass)
    type_text "$password"
    ;;
  both)
    if [ -n "$user" ]; then
      type_text "$user"
      say 'fake-key <Tab>'
    fi
    type_text "$password"
    ;;
  otp)
    code="$(pass otp "$entry" 2>/dev/null)" || fail "No OTP set up in $entry"
    type_text "$code"
    ;;
  *)
    fail "Unknown mode $mode"
    ;;
esac

say "message-info 'Filled from $entry'"
