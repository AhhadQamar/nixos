#!/usr/bin/env bash
# Build the system (no activation). Used for the package preview.
#   $1 flake dir   $2 candidate lock file (empty = use the repo lock)
#   $3 out-link    $4 host
exec 2>&1
set -o pipefail
flake=$1 lock=$2 out=$3 host=$4
args=(--no-write-lock-file --out-link "$out" --print-build-logs)
[ -n "$lock" ] && args+=(--reference-lock-file "$lock")
cd "$flake" || exit 1
nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" "${args[@]}"
