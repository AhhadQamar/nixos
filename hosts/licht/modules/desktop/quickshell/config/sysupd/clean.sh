#!/usr/bin/env bash
# Delete system generations, then collect garbage and rebuild the boot menu.
#   $1  all   everything except the current generation
#       old   everything older than $2 days (default 14)
#       N     just generation N (the current one is refused)
# "all" and "old" also clear old generations of your own profiles first.
exec 2>&1
set -eo pipefail
what=$1 days=${2:-14}
case "$what" in
  all | old) ;;
  "" | *[!0-9]*) echo "bad argument: $what"; exit 1 ;;
  *) [ -e "/nix/var/nix/profiles/system-$what-link" ] || { echo "generation $what does not exist"; exit 1; } ;;
esac
case "$days" in "" | *[!0-9]*) echo "bad age: $days"; exit 1 ;; esac
. "$(dirname "$0")/lib.sh"
require_helper
case "$what" in
  all) echo "==> cleaning your own profiles"; user_profile_cleanup ;;
  old) echo "==> cleaning your own profiles"; user_profile_cleanup "$days" ;;
esac
echo "==> deleting (authentication required)"
case "$what" in
  old) pkexec "$helper" clean old "$days" ;;
  *) pkexec "$helper" clean "$what" ;;
esac
echo "==> done"
