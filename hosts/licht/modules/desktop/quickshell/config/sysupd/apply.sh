#!/usr/bin/env bash
# Build as the normal user, then let root only activate the result. Root never
# evaluates the flake, so git ownership of the repo is not an issue.
# The new flake.lock is written into the repo only after the switch worked.
#   $1 flake dir   $2 candidate lock (empty = rebuild with the repo lock)
#   $3 work dir    $4 host
#   $5 commit flag (1 = commit flake.lock locally after a good switch; never pushes)
#   $6 summary of the moved inputs, used as the commit body
#   $7 expected sha256 of the candidate lock (refuses to apply a different one)
#   $8 mode: switch (default) or test. test activates the system without making
#      it the boot default and leaves flake.lock alone, like `nh os test`
exec 2>&1
set -eo pipefail
flake=$1 lock=$2 work=$3 host=$4 commit=${5:-0} summary=${6:-} expect=${7:-} mode=${8:-switch}
case "$mode" in switch|test) ;; *) echo "bad mode: $mode"; exit 1 ;; esac
mkdir -p "$work"

# One apply at a time
exec 9>"$work/apply.lock"
flock -n 9 || { echo "another update is already running"; exit 1; }

# Apply exactly the lock the panel showed, not whatever is on disk now
if [ -n "$lock" ] && [ -n "$expect" ]; then
  actual=$(sha256sum "$lock" | cut -d" " -f1)
  [ "$actual" = "$expect" ] || { echo "the update changed since it was checked; check again"; exit 3; }
fi
args=(--no-write-lock-file --out-link "$work/result" --print-build-logs)
[ -n "$lock" ] && args+=(--reference-lock-file "$lock")
cd "$flake"
# Flakes only see files git knows about. Mark brand-new files as "to be added"
# (nothing is staged or committed) so they are not silently left out of the build.
git ls-files --others --exclude-standard -z | xargs -0 -r git add --intent-to-add -- 2>/dev/null || true
echo "==> building"
nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" "${args[@]}"
out=$(readlink -f "$work/result")
echo "==> activating ($mode, authentication required)"
# The switch runs as a transient system unit (the way nixos-rebuild does it),
# so closing or reloading the shell cannot cut it off half way. Root only
# accepts a real system closure from the store.
pkexec /run/current-system/sw/bin/systemd-run --collect --pipe --quiet \
  --service-type=exec --unit=sysupd-switch -- \
  /run/current-system/sw/bin/bash -c '
    set -e
    case "$1" in
      /nix/store/*-nixos-system-*) ;;
      *) echo "refusing to switch: not a system closure: $1"; exit 1 ;;
    esac
    [ -x "$1/bin/switch-to-configuration" ] || { echo "refusing to switch: no switch-to-configuration in $1"; exit 1; }
    case "$2" in switch | test) ;; *) exit 1 ;; esac
    if [ "$2" = switch ]; then
      /run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set "$1"
    fi
    "$1/bin/switch-to-configuration" "$2"
  ' _ "$out" "$mode"
if [ -n "$lock" ] && [ "$mode" = switch ]; then
  cp flake.lock "$work/flake.lock.bak"
  cp "$lock" flake.lock
  echo "==> flake.lock updated (previous copy: $work/flake.lock.bak)"
  if [ "$commit" = 1 ]; then
    # Only flake.lock is committed (the pathspec leaves anything else you have
    # staged alone), and nothing is pushed: run `git push` or `u` when ready.
    if git commit -q -m "Update flake inputs" -m "$summary" -- flake.lock; then
      echo "==> committed flake.lock locally (not pushed)"
    else
      echo "==> could not commit flake.lock; commit it yourself"
    fi
  fi
fi
echo "==> done"
