#!/usr/bin/env bash
# Small facts about the machine, one per line.
#   $1 flake dir
b=/run/booted-system c=/run/current-system prof=/nix/var/nix/profiles/system
reb=0
for f in kernel initrd kernel-modules; do
  [ "$(readlink -f "$b/$f")" != "$(readlink -f "$c/$f")" ] && reb=1
done
echo "reboot=$reb"
# 1 when the next boot would not come up in the system that is running now
# (after a test, or a boot-only switch)
run=$(readlink -f "$c")
cur=$(readlink -f "$prof")
[ "$cur" != "$run" ] && echo "bootdiff=1" || echo "bootdiff=0"
echo "kernel=$(uname -r)"
echo "failed=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)"
systemctl --failed --no-legend --plain 2>/dev/null | while read -r u _; do echo "U|$u"; done
echo "dirty=$(git -C "$1" status --porcelain 2>/dev/null | wc -l)"
read -r used avail < <(df -B1 --output=used,avail /nix/store 2>/dev/null | tail -n 1)
echo "disk=${used:-0}|${avail:-0}"
for l in /nix/var/nix/profiles/system-*-link; do
  [ -e "$l" ] || continue
  t=$(readlink -f "$l"); n=${l##*/system-}; n=${n%-link}
  k=$(readlink -f "$t/kernel" | sed -E "s|.*linux-([0-9.]+)/.*|\1|")
  v=$(cat "$t/nixos-version" 2>/dev/null)
  echo "G|$n|$(stat -c %Y "$l")|$v|$k|$([ "$t" = "$cur" ] && echo 1 || echo 0)|$([ "$t" = "$run" ] && echo 1 || echo 0)"
done
