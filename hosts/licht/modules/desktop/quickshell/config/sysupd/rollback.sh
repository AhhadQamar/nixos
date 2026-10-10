#!/usr/bin/env bash
# Switch back to an older system generation.
#   $1 generation number
# Like apply.sh, the root step runs as a transient unit and checks its input.
exec 2>&1
set -eo pipefail
id=$1
case "$id" in
  "" | *[!0-9]*) echo "bad generation number: $id"; exit 1 ;;
esac
[ -e "/nix/var/nix/profiles/system-$id-link" ] || { echo "generation $id does not exist"; exit 1; }
echo "==> switching to generation $id (authentication required)"
pkexec /run/current-system/sw/bin/systemd-run --collect --pipe --quiet \
  --service-type=exec --unit=sysupd-switch -- \
  /run/current-system/sw/bin/bash -c '
    set -e
    case "$1" in
      "" | *[!0-9]*) exit 1 ;;
    esac
    /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --switch-generation "$1"
    /nix/var/nix/profiles/system/bin/switch-to-configuration switch
  ' _ "$id"
echo "==> done"
