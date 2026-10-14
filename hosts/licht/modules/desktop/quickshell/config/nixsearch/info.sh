#!/usr/bin/env bash
# Details for one package: whether it is already in home.nix, and its meta.
# Prints "listed=0|1", then one line of JSON (empty if nix could not evaluate).
#   $1 nixpkgs ref   $2 attribute   $3 home.nix
ref=$1 attr=$2 home=$3
case "$attr" in "" | *[!A-Za-z0-9_.+-]*) exit 2 ;; esac
esc=$(printf '%s' "$attr" | sed 's/[.+]/\\&/g')
listed=0
[ -f "$home" ] && grep -qE "^[[:space:]]+$esc[[:space:]]*$" "$home" && listed=1
echo "listed=$listed"
nix eval --json "$ref#$attr.meta" --apply '
  m:
  let
    l = m.license or null;
    one = x: if builtins.isAttrs x then (x.spdxId or x.shortName or x.fullName or "?") else toString x;
    names = if l == null then [ ] else if builtins.isList l then map one l else [ (one l) ];
    h = m.homepage or "";
  in {
    homepage = if builtins.isList h then (if h == [ ] then "" else builtins.head h) else h;
    license = builtins.concatStringsSep ", " names;
    mainProgram = m.mainProgram or "";
    unfree = m.unfree or false;
    broken = m.broken or false;
    longDescription = m.longDescription or "";
  }' 2>/dev/null | tr -d '\n'
echo
exit 0
