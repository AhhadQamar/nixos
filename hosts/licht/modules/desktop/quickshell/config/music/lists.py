#!/usr/bin/env python3
"""Playlists for the Quickshell player: plain .m3u8 files, readable by any player.

  lists.py <dir> list                      name TAB count, "Liked Songs" first
  lists.py <dir> show <name>               path TAB title TAB artist TAB album TAB seconds TAB cover
  lists.py <dir> add <name> <json>         json: [{path,title,artist,album,duration,cover}]
  lists.py <dir> remove <name> <path>
  lists.py <dir> create <name>
  lists.py <dir> delete <name>

An entry is   #EXTINF:secs,Artist - Title / #EXTALB / #EXTART / #EXTIMG / path-or-url
"""
import json
import os
import sys

LIKED = "Liked Songs"


def clean(s):
    return str(s if s is not None else "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def safe(name):
    n = clean(name).replace("/", "-").replace("\\", "-").lstrip(".")
    return n[:120]


def file_of(d, name):
    return os.path.join(d, safe(name) + ".m3u8")


def read(d, name):
    p = file_of(d, name)
    entries = []
    if not os.path.isfile(p):
        return entries
    cur = {}
    with open(p, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            if line.startswith("#EXTINF:"):
                head, _, text = line[8:].partition(",")
                try:
                    cur["duration"] = max(0, int(float(head)))
                except ValueError:
                    cur["duration"] = 0
                cur["text"] = text
            elif line.startswith("#EXTALB:"):
                cur["album"] = line[8:]
            elif line.startswith("#EXTART:"):
                cur["artist"] = line[8:]
            elif line.startswith("#EXTIMG:"):
                cur["cover"] = line[8:]
            elif line.startswith("#"):
                continue
            else:
                artist = cur.get("artist", "")
                title = cur.get("text", "")
                if artist and title.startswith(artist + " - "):
                    title = title[len(artist) + 3:]
                if not title:
                    title = os.path.splitext(os.path.basename(line))[0]
                entries.append({
                    "path": line, "title": title, "artist": artist,
                    "album": cur.get("album", ""), "duration": cur.get("duration", 0),
                    "cover": cur.get("cover", ""),
                })
                cur = {}
    return entries


def write(d, name, entries):
    os.makedirs(d, exist_ok=True)
    p = file_of(d, name)
    lines = ["#EXTM3U"]
    for e in entries:
        artist, title = clean(e.get("artist")), clean(e.get("title"))
        lines.append("#EXTINF:%d,%s" % (int(e.get("duration") or 0), (artist + " - " + title) if artist else title))
        if artist:
            lines.append("#EXTART:" + artist)
        if clean(e.get("album")):
            lines.append("#EXTALB:" + clean(e["album"]))
        if clean(e.get("cover")):
            lines.append("#EXTIMG:" + clean(e["cover"]))
        lines.append(clean(e["path"]))
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, p)


def main(argv):
    if len(argv) < 2:
        sys.exit("usage: lists.py <dir> <op> ...")
    d, op, rest = argv[0], argv[1], argv[2:]
    if op == "list":
        names = []
        if os.path.isdir(d):
            names = sorted((f[:-5] for f in os.listdir(d) if f.endswith(".m3u8")), key=str.lower)
        names = [n for n in names if n != LIKED]
        for n in [LIKED] + names:
            print("%s\t%d" % (n, len(read(d, n))))
    elif op == "show" and rest:
        for e in read(d, rest[0]):
            print("\t".join(clean(e[k]) for k in ("path", "title", "artist", "album", "duration", "cover")))
    elif op == "add" and len(rest) >= 2:
        have = read(d, rest[0])
        seen = {e["path"] for e in have}
        added = 0
        for e in json.loads(rest[1]):
            if e.get("path") and e["path"] not in seen:
                seen.add(e["path"])
                have.append(e)
                added += 1
        write(d, rest[0], have)
        print("added %d" % added)
    elif op == "remove" and len(rest) >= 2:
        write(d, rest[0], [e for e in read(d, rest[0]) if e["path"] != rest[1]])
    elif op == "create" and rest:
        if not os.path.isfile(file_of(d, rest[0])):
            write(d, rest[0], [])
    elif op == "delete" and rest:
        if rest[0] != LIKED and os.path.isfile(file_of(d, rest[0])):
            os.remove(file_of(d, rest[0]))
    else:
        sys.exit("bad arguments")


if __name__ == "__main__":
    main(sys.argv[1:])
