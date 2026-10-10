#!/usr/bin/env bash
# Delete system generations.
#   $1  "all"  everything except the current generation, then collect garbage
#       N      just generation N (the current one is refused)
# Like apply.sh, the root step runs as a transient unit and checks its input.
# Afterwards the boot menu is rebuilt so it no longer lists deleted entries.
exec 2>&1
set -eo pipefail
what=$1
case "$what" in
  all) ;;
  "" | *[!0-9]*) echo "bad argument: $what"; exit 1 ;;
  *) [ -e "/nix/var/nix/profiles/system-$what-link" ] || { echo "generation $what does not exist"; exit 1; } ;;
esac
echo "==> deleting (authentication required)"
pkexec /run/current-system/sw/bin/systemd-run --collect --pipe --quiet \
  --service-type=exec --unit=sysupd-clean -- \
  /run/current-system/sw/bin/bash -c '
    set -e
    p=/nix/var/nix/profiles/system
    nixenv=/run/current-system/sw/bin/nix-env
    case "$1" in
      all)
        "$nixenv" -p "$p" --delete-generations old
        /run/current-system/sw/bin/nix-collect-garbage
        ;;
      "" | *[!0-9]*) exit 1 ;;
      *)
        if [ "$(readlink -f "$p")" = "$(readlink -f "${p}-$1-link")" ]; then
          echo "refusing to delete the current generation"; exit 1
        fi
        "$nixenv" -p "$p" --delete-generations "$1"
        ;;
    esac
    "$p/bin/switch-to-configuration" boot
  ' _ "$what"
echo "==> done"
