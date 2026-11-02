#!/usr/bin/env python3
"""YouTube Music lookups for the Quickshell player. One JSON line on stdout.

  search.py search <top|songs|albums|playlists|artists> <query> [limit]
  search.py tracks <album|playlist|artist> <id>
  search.py playlist-url <album browseId>        (plain URL, used by dl.sh)

Needs ytmusicapi (no login: search, albums, playlists and artists are public).
Songs fall back to `yt-dlp ytsearchN:` when ytmusicapi is missing or fails.
"""
import json
import re
import subprocess
import sys

WATCH = "https://music.youtube.com/watch?v="
PLAYLIST = "https://music.youtube.com/playlist?list="


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def fail(msg):
    out({"ok": False, "error": str(msg)[:200]})
    sys.exit(0)


def cover(thumbs):
    """The largest thumbnail, resized to a card-sized square when Google lets us."""
    if not thumbs:
        return ""
    url = (thumbs[-1] or {}).get("url", "")
    if ("googleusercontent.com" in url or "ggpht.com" in url) and "=" in url:
        url = url.split("=")[0] + "=w226-h226-l90-rj"
    return url


def names(artists):
    if not artists:
        return ""
    if isinstance(artists, str):
        return artists
    return ", ".join(a.get("name", "") for a in artists if a and a.get("name"))


def seconds(t):
    s = t.get("duration_seconds")
    if isinstance(s, (int, float)):
        return int(s)
    d = t.get("duration") or ""
    if isinstance(d, str) and re.fullmatch(r"(\d+:)?\d{1,2}:\d{2}", d):
        n = 0
        for p in d.split(":"):
            n = n * 60 + int(p)
        return n
    return 0


def album_name(a):
    if isinstance(a, dict):
        return a.get("name", "")
    return a or ""


def song(t, album="", art=""):
    vid = t.get("videoId")
    if not vid:
        return None
    return {
        "kind": "song",
        "id": vid,
        "path": WATCH + vid,
        "title": t.get("title", ""),
        "artist": names(t.get("artists")),
        "album": album_name(t.get("album")) or album,
        "duration": seconds(t),
        "cover": cover(t.get("thumbnails") or t.get("thumbnail")) or art,
    }


def client():
    from ytmusicapi import YTMusic

    return YTMusic()


def plist_url(pid):
    return PLAYLIST + re.sub(r"^VL", "", pid) if pid else ""


def ytdlp_songs(query, limit):
    p = subprocess.run(
        ["yt-dlp", "ytsearch%d:%s" % (limit, query), "--flat-playlist", "-j", "--no-warnings"],
        capture_output=True, text=True, timeout=40,
    )
    items = []
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not e.get("id"):
            continue
        art = re.sub(r" - Topic$", "", e.get("channel") or e.get("uploader") or "")
        items.append({
            "kind": "song", "id": e["id"], "path": WATCH + e["id"],
            "title": e.get("title", ""), "artist": art, "album": "",
            "duration": int(e.get("duration") or 0), "cover": cover(e.get("thumbnails")),
        })
    return items


def do_search(kind, query, limit):
    rtypes = {"top": None, "songs": "song", "albums": "album", "playlists": "playlist", "artists": "artist"}
    if kind not in rtypes:
        fail("unknown kind " + kind)
    try:
        res = client().search(query, filter=None if kind == "top" else kind, limit=limit)
    except Exception as e:  # ytmusicapi missing, offline, or YouTube changed something
        if kind in ("songs", "top"):
            try:
                return out({"ok": True, "source": "yt-dlp", "items": ytdlp_songs(query, limit)})
            except Exception as e2:
                fail("search failed: %s / %s" % (e, e2))
        fail("search failed: %s" % e)
    items = []
    for r in res:
        rt = rtypes[kind] or r.get("resultType")
        if rt in ("song", "video"):
            s = song(r)
            if s:
                items.append(s)
        elif rt == "album" and r.get("browseId"):
            items.append({
                "kind": "album", "id": r["browseId"], "playlist": plist_url(r.get("playlistId", "")),
                "title": r.get("title", ""), "artist": names(r.get("artists")),
                "album": r.get("title", ""), "year": r.get("year") or "",
                "type": r.get("type") or "Album", "cover": cover(r.get("thumbnails")),
            })
        elif rt == "playlist" and r.get("browseId"):
            items.append({
                "kind": "playlist", "id": r["browseId"], "playlist": plist_url(r["browseId"]),
                "title": r.get("title", ""), "artist": r.get("author") or "",
                "count": r.get("itemCount") or "", "cover": cover(r.get("thumbnails")),
            })
        elif rt == "artist" and r.get("browseId"):
            items.append({
                "kind": "artist", "id": r["browseId"], "title": r.get("artist") or r.get("title", ""),
                "artist": "", "cover": cover(r.get("thumbnails")),
            })
    out({"ok": True, "source": "ytmusicapi", "items": items})


def do_tracks(kind, ident):
    try:
        yt = client()
        if kind == "album":
            a = yt.get_album(ident)
            art = cover(a.get("thumbnails"))
            items = [s for s in (song(t, a.get("title", ""), art) for t in a.get("tracks", [])) if s]
            for s in items:
                if not s["artist"]:
                    s["artist"] = names(a.get("artists"))
            return out({"ok": True, "title": a.get("title", ""), "cover": art,
                        "playlist": plist_url(a.get("audioPlaylistId", "")), "items": items})
        if kind == "playlist":
            p = yt.get_playlist(re.sub(r"^VL", "", ident), limit=200)
            items = [s for s in (song(t) for t in p.get("tracks", [])) if s]
            return out({"ok": True, "title": p.get("title", ""), "cover": cover(p.get("thumbnails")),
                        "playlist": plist_url(ident), "items": items})
        if kind == "artist":
            a = yt.get_artist(ident)
            songs = a.get("songs") or {}
            rows = songs.get("results") or []
            if songs.get("browseId"):
                try:
                    rows = yt.get_playlist(songs["browseId"], limit=50).get("tracks", rows)
                except Exception:
                    pass
            items = [s for s in (song(t) for t in rows) if s]
            return out({"ok": True, "title": a.get("name", ""), "cover": cover(a.get("thumbnails")),
                        "playlist": "", "items": items})
    except Exception as e:
        fail("could not load: %s" % e)
    fail("unknown kind " + kind)


def do_playlist_url(ident):
    try:
        url = plist_url(client().get_album(ident).get("audioPlaylistId", ""))
    except Exception as e:
        sys.stderr.write("ERROR: %s\n" % e)
        sys.exit(1)
    if not url:
        sys.stderr.write("ERROR: no playlist for that album\n")
        sys.exit(1)
    print(url)


def main(argv):
    if len(argv) >= 3 and argv[0] == "search":
        limit = int(argv[3]) if len(argv) > 3 else 20
        return do_search(argv[1], argv[2], limit)
    if len(argv) >= 3 and argv[0] == "tracks":
        return do_tracks(argv[1], argv[2])
    if len(argv) >= 2 and argv[0] == "playlist-url":
        return do_playlist_url(argv[1])
    fail("usage: search.py search|tracks|playlist-url ...")


if __name__ == "__main__":
    main(sys.argv[1:])
