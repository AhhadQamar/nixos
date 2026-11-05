#!/usr/bin/env python3
"""Lyrics for the Quickshell player. One JSON line on stdout.

  lyrics.py <path or url> <artist> <title> <album> <seconds> [save]

Looks, in this order, at: a .lrc (or .txt) next to the file, the cache in
~/.cache/quickshell/lyrics, then LRCLIB (https://lrclib.net, free, no key).
With `save` and a local file, lyrics found online are also written next to the
song as <name>.lrc, so any other player (and this one, offline) can use them.

Answers:
  {"ok": true, "synced": true,  "source": "...", "lines": [[seconds, "text"], ...]}
  {"ok": true, "synced": false, "source": "...", "lines": [[-1, "text"], ...]}
  {"ok": true, "none": true}                       nothing found
  {"ok": false, "error": "..."}                    the lookup itself failed
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("LRCLIB_URL", "https://lrclib.net").rstrip("/")
UA = "quickshell-music (personal desktop player)"
NEGATIVE_TTL = 12 * 3600


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


# ---- reading LRC ------------------------------------------------------------
STAMP = re.compile(r"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]")


def parse_lrc(text):
    """-> (synced, [[seconds, text], ...]). Plain text gives seconds = -1."""
    offset = 0.0
    m = re.search(r"^\[offset:\s*([+-]?\d+)\s*\]", text, re.M | re.I)
    if m:
        offset = int(m.group(1)) / 1000.0
    rows = []
    for raw in text.replace("\r", "").split("\n"):
        stamps = list(STAMP.finditer(raw))
        if not stamps:
            continue
        # A line that is all stamps and one more [tag:...] is metadata, not a lyric
        body = raw[stamps[-1].end():].strip()
        for s in stamps:
            frac = s.group(3) or "0"
            t = int(s.group(1)) * 60 + int(s.group(2)) + int(frac) / (10 ** len(frac))
            rows.append([max(0.0, round(t - offset, 2)), body])
    if rows:
        rows.sort(key=lambda r: r[0])
        return True, rows
    plain = [l.rstrip() for l in text.replace("\r", "").split("\n")]
    plain = [l for l in plain if not re.match(r"^\[[a-zA-Z]+:.*\]$", l.strip())]
    while plain and not plain[0].strip():
        plain.pop(0)
    while plain and not plain[-1].strip():
        plain.pop()
    return False, [[-1, l] for l in plain]


# ---- names ------------------------------------------------------------------
NOISE = re.compile(
    r"\s*[\(\[][^\)\]]*\b(official|video|audio|lyrics?|lyric video|visuali[sz]er|remaster(ed)?|mv|hd|4k|live|explicit|clean)\b[^\)\]]*[\)\]]",
    re.I,
)


def clean_title(t):
    t = NOISE.sub("", t or "").strip()
    return re.sub(r"\s{2,}", " ", t)


def strip_feat(t):
    return re.sub(r"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\b[^\)\]]*[\)\]]", "", t, flags=re.I).strip()


def clean_artist(a):
    a = re.sub(r"\s*-\s*Topic$", "", a or "", flags=re.I).strip()
    return re.split(r"\s*(?:,|&|;|\bfeat\.?\b|\bft\.?\b|\bx\b)\s*", a, maxsplit=1, flags=re.I)[0].strip() or a


def guess(artist, title):
    """A stream often has the artist inside the title: 'Artist - Song'."""
    if not artist and " - " in (title or ""):
        a, _, t = title.partition(" - ")
        return a.strip(), t.strip()
    return artist, title


# ---- places lyrics come from ---------------------------------------------------
def sidecar(path):
    if not path or re.match(r"^https?://", path) or not os.path.isfile(path):
        return None
    stem = os.path.splitext(path)[0]
    for ext in (".lrc", ".LRC", ".txt"):
        p = stem + ext
        if os.path.isfile(p):
            try:
                with open(p, encoding="utf-8", errors="replace") as f:
                    return f.read()
            except OSError:
                return None
    return None


def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "quickshell", "lyrics")


def cache_file(artist, title, secs):
    key = "%s|%s|%d" % (artist.lower(), title.lower(), int(round(secs / 5.0)) if secs else 0)
    return os.path.join(cache_dir(), hashlib.sha1(key.encode("utf-8")).hexdigest() + ".json")


def http_json(path, params):
    url = BASE + path + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def lrclib(artist, title, album, secs):
    """The best LRCLIB match as a dict, None if there is none. Raises on network errors."""
    tries = [(artist, title, album)]
    t2 = strip_feat(clean_title(title))
    if t2 != title:
        tries.append((artist, t2, ""))
    for a, t, al in tries:
        if not a or not t:
            continue
        params = {"artist_name": a, "track_name": t}
        if al:
            params["album_name"] = al
        if secs:
            params["duration"] = int(round(secs))
        try:
            return http_json("/api/get", params)
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
    # Looser: search, and take the closest in length, preferring synced lyrics
    best = None
    for a, t, _ in tries:
        q = {"track_name": t}
        if a:
            q["artist_name"] = a
        try:
            res = http_json("/api/search", q)
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            continue
        for r in res or []:
            if not (r.get("syncedLyrics") or r.get("plainLyrics") or r.get("instrumental")):
                continue
            d = abs((r.get("duration") or 0) - secs) if secs else 0
            if secs and d > 6:
                continue
            score = (0 if r.get("syncedLyrics") else 1, d)
            if best is None or score < best[0]:
                best = (score, r)
        if best:
            return best[1]
    return None


def main(argv):
    if len(argv) < 5:
        return out({"ok": False, "error": "usage: lyrics.py path artist title album seconds [save]"})
    path, artist, title, album = argv[0], argv[1], argv[2], argv[3]
    try:
        secs = float(argv[4])
    except ValueError:
        secs = 0.0
    save = len(argv) > 5 and argv[5] == "save"

    text = sidecar(path)
    if text:
        synced, lines = parse_lrc(text)
        if lines:
            return out({"ok": True, "synced": synced, "source": "file", "lines": lines})

    artist, title = guess(artist, title)
    artist, title = clean_artist(artist), clean_title(title)
    if not title:
        return out({"ok": True, "none": True})

    cf = cache_file(artist, title, secs)
    try:
        with open(cf, encoding="utf-8") as f:
            c = json.load(f)
        if c.get("none"):
            if time.time() - c.get("ts", 0) < NEGATIVE_TTL:
                return out({"ok": True, "none": True})
        else:
            return out(dict(c, source="cache"))
    except (OSError, ValueError):
        pass

    try:
        r = lrclib(artist, title, album, secs)
    except Exception as e:
        return out({"ok": False, "error": "lyrics lookup failed: %s" % e})

    def store(obj):
        try:
            os.makedirs(os.path.dirname(cf), exist_ok=True)
            with open(cf, "w", encoding="utf-8") as f:
                json.dump(obj, f)
        except OSError:
            pass

    if not r or r.get("instrumental") and not (r.get("syncedLyrics") or r.get("plainLyrics")):
        store({"none": True, "ts": time.time()})
        return out({"ok": True, "none": True})
    raw = r.get("syncedLyrics") or r.get("plainLyrics") or ""
    synced, lines = parse_lrc(raw)
    if not lines:
        store({"none": True, "ts": time.time()})
        return out({"ok": True, "none": True})
    result = {"ok": True, "synced": synced, "lines": lines}
    store(result)
    if save and synced and os.path.isfile(path) and not re.match(r"^https?://", path):
        try:
            with open(os.path.splitext(path)[0] + ".lrc", "w", encoding="utf-8") as f:
                f.write(raw if raw.endswith("\n") else raw + "\n")
        except OSError:
            pass
    out(dict(result, source="lrclib"))


if __name__ == "__main__":
    main(sys.argv[1:])
