#!/usr/bin/env bash
# Build as the normal user, then let root only activate the result. Root never
# evaluates the flake, so git ownership of the repo is not an issue.
# The new flake.lock is written into the repo only after the activation worked.
#   $1 flake dir   $2 candidate lock (empty = rebuild with the repo lock)
#   $3 work dir    $4 host
#   $5 commit flag (1 = commit flake.lock locally after a good switch; never pushes)
#   $6 summary of the moved inputs, used as the commit body
#   $7 expected sha256 of the candidate lock (refuses to apply a different one)
#   $8 mode, like the nh aliases:
#        switch  activate now and make it the boot default      (u / uu)
#        test    activate now, boot default unchanged           (ut)
#        boot    make it the boot default, activate at reboot   (ub)
#      test leaves flake.lock alone; switch and boot write it.
# TERM during the build stops it (the panel's Cancel button). Once the build is
# done TERM is ignored, so a late Cancel cannot leave the system and flake.lock
# out of step.
exec 2>&1
set -eo pipefail
flake=$1 lock=$2 work=$3 host=$4 commit=${5:-0} summary=${6:-} expect=${7:-} mode=${8:-switch}
case "$mode" in switch | test | boot) ;; *) echo "bad mode: $mode"; exit 1 ;; esac
. "$(dirname "$0")/lib.sh"
require_helper
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
# Background + wait so TERM (Cancel) reaches nix straight away
nix build "$flake#nixosConfigurations.$host.config.system.build.toplevel" "${args[@]}" &
pid=$!
trap 'kill "$pid" 2>/dev/null' TERM INT
wait "$pid"
# From here on a stop request must not interrupt anything: the switch has to
# finish so flake.lock below stays in step with the system. Ignored signals are
# inherited, so pkexec and the helper ignore TERM and INT too.
trap "" TERM INT
out=$(readlink -f "$work/result")
echo "==> activating ($mode, authentication required)"
pkexec "$helper" activate "$mode" "$out"
if [ -n "$lock" ] && [ "$mode" != test ]; then
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
