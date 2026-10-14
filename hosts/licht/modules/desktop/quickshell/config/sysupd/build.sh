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
# Flakes only see files git knows about. Mark brand-new files as "to be added"
# (nothing is staged or committed) so they are not silently left out of the build.
git ls-files --others --exclude-standard -z | xargs -0 -r git add --intent-to-add -- 2>/dev/null || true
# Background + wait so TERM (the Cancel button) reaches nix straight away
nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" "${args[@]}" &
pid=$!
trap 'kill "$pid" 2>/dev/null' TERM INT
wait "$pid"
