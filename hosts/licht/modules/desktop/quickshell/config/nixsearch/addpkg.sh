#!/usr/bin/env bash
# Add a package to the home.packages list in home.nix, just before its closing
# "];". Nothing is committed or rebuilt. Prints a one-line result.
#   $1 home.nix   $2 attribute
file=$1 pkg=$2
case "$pkg" in "" | *[!A-Za-z0-9_.+-]*) echo "Not a valid package name"; exit 2 ;; esac
[ -f "$file" ] || { echo "Could not find $file"; exit 2; }
esc=$(printf '%s' "$pkg" | sed 's/[.+]/\\&/g')
grep -qE "^[[:space:]]+$esc[[:space:]]*$" "$file" && { echo "$pkg is already in home.nix"; exit 3; }
grep -q 'home\.packages = with pkgs; \[' "$file" || { echo "No home.packages list found in home.nix"; exit 4; }
tmp=$(mktemp)
awk -v pkg="$pkg" '
  !done && /home\.packages = with pkgs; \[/ { inlist = 1 }
  inlist && /^[[:space:]]*\];/ { print "    " pkg; inlist = 0; done = 1 }
  { print }
' "$file" > "$tmp" && cat "$tmp" > "$file"
rm -f "$tmp"
echo "Added $pkg to home.nix (not committed)"
