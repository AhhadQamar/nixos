#!/usr/bin/env bash
# Build the package index from the nixpkgs your flake is pinned to, so what
# you find is what your system can install. The first run evaluates all of
# nixpkgs and takes a minute or two; after that searching is instant.
#   $1 flake dir   $2 index directory
exec 2>&1
set -o pipefail
flake=$1 dir=$2
mkdir -p "$dir"
command -v jq >/dev/null || { echo "jq is needed to build the index"; exit 1; }
ref=nixpkgs
if [ -f "$flake/flake.lock" ]; then
  r=$(jq -r '.nodes.nixpkgs.locked | if .rev then "github:\(.owner)/\(.repo)/\(.rev)" else empty end' "$flake/flake.lock" 2>/dev/null)
  [ -n "$r" ] && ref=$r
fi
echo "==> indexing $ref"
if ! nix search "$ref" '^' --json 2>"$dir/index.err" \
  | jq -r 'to_entries[] | [(.key | split(".") | .[2:] | join(".")), (.value.version // ""), ((.value.description // "") | gsub("[\t\n]"; " "))] | @tsv' \
  > "$dir/index.tsv.new"; then
  tail -n 4 "$dir/index.err"
  rm -f "$dir/index.tsv.new"
  exit 1
fi
[ -s "$dir/index.tsv.new" ] || { echo "nothing came back from nix search"; tail -n 4 "$dir/index.err"; exit 1; }
mv "$dir/index.tsv.new" "$dir/index.tsv"
printf '%s\n' "$ref" > "$dir/ref"
echo "==> $(wc -l < "$dir/index.tsv") packages"
