#!/usr/bin/env bash
# Ask nix what `flake update` would do, without touching the repo.
#   $1  flake directory          $2  where to write the candidate flake.lock
# Prints the current lock after ###OLD and the candidate after ###NEW.
set -u
flake=$1 new=$2
mkdir -p "$(dirname "$new")"
rm -f "$new"
cd "$flake" 2>/dev/null || { echo "###ERR flake directory not found: $flake"; exit 1; }
[ -f flake.lock ] || { echo "###ERR no flake.lock in $flake"; exit 1; }
if ! nix flake update --output-lock-file "$new" >/dev/null 2>"$new.err"; then
  echo "###ERR $(tail -n 3 "$new.err" | tr "\n" " ")"
  exit 1
fi
echo "###OLD"; cat flake.lock
echo "###NEW"; cat "$new"
