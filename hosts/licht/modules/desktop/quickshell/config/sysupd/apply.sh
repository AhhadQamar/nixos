#!/usr/bin/env bash
# Build as the normal user, then let root only activate the result. Root never
# evaluates the flake, so git ownership of the repo is not an issue.
# The new flake.lock is written into the repo only after the switch worked.
#   $1 flake dir   $2 candidate lock (empty = rebuild with the repo lock)
#   $3 work dir    $4 host
exec 2>&1
set -eo pipefail
flake=$1 lock=$2 work=$3 host=$4
mkdir -p "$work"
args=(--no-write-lock-file --out-link "$work/result" --print-build-logs)
[ -n "$lock" ] && args+=(--reference-lock-file "$lock")
cd "$flake"
echo "==> building"
nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" "${args[@]}"
out=$(readlink -f "$work/result")
echo "==> switching (authentication required)"
pkexec /run/current-system/sw/bin/bash -c \
  "/run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set \"\$1\" && \"\$1/bin/switch-to-configuration\" switch" _ "$out"
if [ -n "$lock" ]; then
  cp flake.lock "$work/flake.lock.bak"
  cp "$lock" flake.lock
  echo "==> flake.lock updated (previous copy: $work/flake.lock.bak)"
fi
echo "==> done"
