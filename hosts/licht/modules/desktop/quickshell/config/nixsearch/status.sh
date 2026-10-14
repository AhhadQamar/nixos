#!/usr/bin/env bash
# Prints: package count <TAB> built (unix time) <TAB> nixpkgs ref. Nothing if there is no index.
#   $1 index directory
dir=$1
[ -s "$dir/index.tsv" ] || exit 0
printf '%s\t%s\t%s\n' "$(wc -l < "$dir/index.tsv")" "$(stat -c %Y "$dir/index.tsv")" "$(cat "$dir/ref" 2>/dev/null)"
