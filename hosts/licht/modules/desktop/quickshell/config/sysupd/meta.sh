#!/usr/bin/env bash
# Small facts about the machine, one per line.
#   $1 flake dir
b=/run/booted-system c=/run/current-system
reb=0
for f in kernel initrd kernel-modules; do
  [ "$(readlink -f "$b/$f")" != "$(readlink -f "$c/$f")" ] && reb=1
done
echo "reboot=$reb"
echo "failed=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)"
echo "dirty=$(git -C "$1" status --porcelain 2>/dev/null | wc -l)"
cur=$(readlink -f /nix/var/nix/profiles/system)
for l in /nix/var/nix/profiles/system-*-link; do
  [ -e "$l" ] || continue
  t=$(readlink -f "$l"); n=${l##*/system-}; n=${n%-link}
  k=$(readlink -f "$t/kernel" | sed -E "s|.*linux-([0-9.]+)/.*|\1|")
  v=$(cat "$t/nixos-version" 2>/dev/null)
  echo "G|$n|$(stat -c %Y "$l")|$v|$k|$([ "$t" = "$cur" ] && echo 1 || echo 0)"
done
