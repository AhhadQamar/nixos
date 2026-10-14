#!/usr/bin/env bash
# Ask nix what `flake update` would do, without touching the repo.
#   $1  flake directory          $2  where to write the candidate flake.lock
# Prints ###HASH (sha256 of the candidate), then the current lock after ###OLD
# and the candidate after ###NEW. TERM stops the running nix (Cancel button).
set -u
flake=$1 new=$2
mkdir -p "$(dirname "$new")"
rm -f "$new"
cd "$flake" 2>/dev/null || { echo "###ERR flake directory not found: $flake"; exit 1; }
[ -f flake.lock ] || { echo "###ERR no flake.lock in $flake"; exit 1; }
nix flake update --output-lock-file "$new" >/dev/null 2>"$new.err" &
pid=$!
# Bash only runs a trap between commands, so nix runs in the background and
# we wait on it: that is what lets TERM reach it straight away.
trap 'kill "$pid" 2>/dev/null' TERM INT
if ! wait "$pid"; then
  echo "###ERR $(tail -n 3 "$new.err" | tr "\n" " ")"
  exit 1
fi
echo "###HASH $(sha256sum "$new" | cut -d" " -f1)"
echo "###OLD"; cat flake.lock
echo "###NEW"; cat "$new"
