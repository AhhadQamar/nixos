#!/usr/bin/env bash
# Rank and print matches from the index: attr <TAB> version <TAB> description.
# Every word must appear in the attribute name or the description. Exact name
# first, then names that start with the first word, then names containing it,
# then description-only matches; shorter names win ties.
#   $1 index file   $2 query
export LC_ALL=C
idx=$1 q=$2
[ -s "$idx" ] || exit 0
awk -F'\t' -v q="$q" '
BEGIN {
  q = tolower(q); n = split(q, w, /[ \t]+/); m = 0
  for (i = 1; i <= n; i++) if (w[i] != "") t[++m] = w[i]
  if (m == 0) exit
}
{
  a = tolower($1); d = tolower($3); hay = a " " d; ok = 1
  for (i = 1; i <= m; i++) if (index(hay, t[i]) == 0) { ok = 0; break }
  if (!ok) next
  s = 0
  if (a == t[1]) s += 1000
  else if (index(a, t[1]) == 1) s += 500
  else if (index(a, t[1]) > 0) s += 200
  for (i = 1; i <= m; i++) if (index(a, t[i]) > 0) s += 20
  s -= length(a) / 100
  printf "%.3f\t%s\n", s, $0
}' "$idx" | sort -t "$(printf '\t')" -k1,1nr | head -80 | cut -f2-
