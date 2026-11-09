#!/usr/bin/env python3
"""What is behind a link, before it is downloaded. One JSON line on stdout.

  preview.py <url> <folder it would go to>

  {"ok": true, "status": 200, "name": "file.iso", "size": 1503238553, "type": "application/x-iso9660-image",
   "resume": true, "url": "<where redirects ended>", "host": "example.com", "page": false, "free": 83000000000}
  {"ok": false, "error": "..."}        no answer at all

`size` and `resume` are null when the server does not say. `status` is the HTTP
status of the answer (400 and up: the server refused or has nothing there).
`page` is an HTML page rather than a file. `free` is the room left on the disk the
folder is on. A HEAD request is tried first; some servers refuse that, so then a
GET for one byte.
"""
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
TIMEOUT = 10


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def ask(url, method, extra=None):
    h = {"User-Agent": UA, "Accept": "*/*"}
    h.update(extra or {})
    req = urllib.request.Request(url, method=method, headers=h)
    try:
        r = urllib.request.urlopen(req, timeout=TIMEOUT)
        return r.status, r.headers, r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.geturl()


def filename(headers, final_url):
    cd = headers.get("Content-Disposition") or ""
    m = re.search(r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)", cd)
    if m:
        name = urllib.parse.unquote(m.group(1).strip().strip('"'))
    else:
        m = re.search(r'filename\s*=\s*"([^"]+)"', cd) or re.search(r"filename\s*=\s*([^;]+)", cd)
        name = m.group(1).strip() if m else ""
    if not name:
        path = urllib.parse.urlsplit(final_url).path
        name = urllib.parse.unquote(path.rstrip("/").split("/")[-1])
    name = name.replace("/", "_").replace("\\", "_").strip()
    return name or "download"


def free_space(folder):
    p = os.path.abspath(os.path.expanduser(folder or "."))
    while p and not os.path.exists(p):
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    try:
        return shutil.disk_usage(p).free
    except OSError:
        return None


def main(argv):
    if not argv:
        return out({"ok": False, "error": "usage: preview.py url folder"})
    url = argv[0]
    folder = argv[1] if len(argv) > 1 else ""
    if not re.match(r"^https?://", url, re.I):
        return out({"ok": False, "error": "only http and https links can be looked at"})
    status = headers = final = None
    err = None
    try:
        status, headers, final = ask(url, "HEAD")
        if status >= 400:
            # Many servers turn HEAD away: ask for the first byte instead
            s2, h2, f2 = ask(url, "GET", {"Range": "bytes=0-0"})
            if s2 < 400:
                status, headers, final = s2, h2, f2
    except Exception as e:
        err = e
        try:
            status, headers, final = ask(url, "GET", {"Range": "bytes=0-0"})
            err = None
        except Exception as e2:
            err = e2
    if err is not None or status is None:
        return out({"ok": False, "error": str(err)[:160] if err else "no answer"})

    size = None
    cr = headers.get("Content-Range") or ""
    m = re.search(r"/(\d+)\s*$", cr)
    if m:
        size = int(m.group(1))
    elif headers.get("Content-Length", "").isdigit() and status != 206:
        size = int(headers["Content-Length"])
    ar = (headers.get("Accept-Ranges") or "").lower()
    resume = True if (ar == "bytes" or status == 206) else (False if ar == "none" else None)
    ctype = (headers.get("Content-Type") or "").split(";")[0].strip().lower()
    attachment = "attachment" in (headers.get("Content-Disposition") or "").lower()
    page = ctype in ("text/html", "application/xhtml+xml") and not attachment
    out({
        "ok": True, "status": status, "name": filename(headers, final or url), "size": size,
        "type": ctype, "resume": resume, "url": final or url,
        "host": urllib.parse.urlsplit(final or url).hostname or "", "page": page,
        "free": free_space(folder),
    })


if __name__ == "__main__":
    main(sys.argv[1:])
