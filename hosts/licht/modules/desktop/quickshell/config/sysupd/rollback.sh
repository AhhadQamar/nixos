#!/usr/bin/env bash
# Switch back to an older system generation.
#   $1 generation number
exec 2>&1
set -eo pipefail
id=$1
case "$id" in
  "" | *[!0-9]*) echo "bad generation number: $id"; exit 1 ;;
esac
. "$(dirname "$0")/lib.sh"
require_helper
[ -e "/nix/var/nix/profiles/system-$id-link" ] || { echo "generation $id does not exist"; exit 1; }
echo "==> switching to generation $id (authentication required)"
pkexec "$helper" rollback "$id"
echo "==> done"
