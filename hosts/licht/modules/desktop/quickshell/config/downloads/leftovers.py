#!/usr/bin/env python3
"""What failed downloads leave behind, and sweeping it up. One JSON line on stdout.

  leftovers.py scan   '<json>'
  leftovers.py delete '<json>'          (the same json, plus "paths": [what to remove])

json: {"aria_dirs": [...], "video_dirs": [...], "active": [...],
       "min_age_min": 10, "video_age_h": 24}

What counts, and nothing else:
  aria2     an X.aria2 control file (with its data file X, if there is one) that
            aria2 is not working on: the download was removed or failed, and its
            half-written file stayed. Looked for in aria_dirs, three levels deep.
  yt-dlp    X.part, X.ytdl and X.part-FragN files of video grabs that did not
            finish, in video_dirs only, and only once they are a day old.
Anything in `active` (the paths aria2 and the panel are using right now) and
anything younger than min_age_min is left alone. `delete` runs the scan again
itself and removes only what both it and the request name: a path that is not a
leftover cannot be removed through it.

Answers: {"ok": true, "items": [{"name", "size", "kind", "paths": [...]}], "count", "total"}
         {"ok": true, "removed": n, "freed": bytes, "failed": n}
"""
import json
import os
import re
import sys
import time

MAX_DEPTH = 3
YT_RE = re.compile(r"(\.part|\.ytdl|\.part-Frag\d+)$")


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def walk(root, depth=MAX_DEPTH):
    root = os.path.abspath(os.path.expanduser(root))
    base = root.rstrip(os.sep).count(os.sep)
    for d, dirs, files in os.walk(root, followlinks=False):
        if d.count(os.sep) - base >= depth:
            dirs[:] = []
        for f in files:
            yield os.path.join(d, f)


def size_of(p):
    try:
        return os.path.getsize(p)
    except OSError:
        return 0


def age_s(p):
    try:
        return time.time() - os.path.getmtime(p)
    except OSError:
        return 0


def safe_dir(d):
    """Never the home folder itself or something above it."""
    p = os.path.abspath(os.path.expanduser(d))
    home = os.path.abspath(os.path.expanduser("~"))
    return p.startswith(home + os.sep) and p != home


def scan(req):
    active = {os.path.abspath(p) for p in req.get("active", [])}
    min_age = float(req.get("min_age_min", 10)) * 60
    video_age = float(req.get("video_age_h", 24)) * 3600
    items, seen = [], set()
    for d in req.get("aria_dirs", []):
        if not safe_dir(d) or not os.path.isdir(os.path.expanduser(d)):
            continue
        for p in walk(d):
            if not p.endswith(".aria2") or p in seen:
                continue
            seen.add(p)
            data = p[:-6]
            if os.path.abspath(data) in active or os.path.abspath(p) in active:
                continue
            if age_s(p) < min_age or (os.path.exists(data) and age_s(data) < min_age):
                continue
            paths = [p] + ([data] if os.path.isfile(data) else [])
            items.append({"name": os.path.basename(data), "size": sum(size_of(x) for x in paths), "kind": "aria2", "paths": paths})
    for d in req.get("video_dirs", []):
        if not safe_dir(d) or not os.path.isdir(os.path.expanduser(d)):
            continue
        for p in walk(d):
            if not YT_RE.search(p) or p in seen:
                continue
            seen.add(p)
            if os.path.abspath(p) in active or age_s(p) < video_age:
                continue
            items.append({"name": os.path.basename(p), "size": size_of(p), "kind": "yt-dlp", "paths": [p]})
    items.sort(key=lambda i: -i["size"])
    return items


def main(argv):
    if len(argv) < 2 or argv[0] not in ("scan", "delete"):
        return out({"ok": False, "error": "usage: leftovers.py scan|delete <json>"})
    try:
        req = json.loads(argv[1])
    except ValueError:
        return out({"ok": False, "error": "bad json"})
    items = scan(req)
    if argv[0] == "scan":
        return out({"ok": True, "items": items, "count": len(items), "total": sum(i["size"] for i in items)})
    wanted = set(req.get("paths", []))
    removed = failed = freed = 0
    for it in items:
        for p in it["paths"]:
            if p not in wanted:
                continue
            sz = size_of(p)
            try:
                os.remove(p)
                removed += 1
                freed += sz
            except OSError:
                failed += 1
    out({"ok": True, "removed": removed, "freed": freed, "failed": failed})


if __name__ == "__main__":
    main(sys.argv[1:])
