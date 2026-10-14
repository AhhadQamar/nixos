#!/usr/bin/env python3
"""screentime: tiny ActivityWatch-style tracker for Hyprland."""
import fcntl
import json
import os
import signal
import socket
import sys
import time
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

DATA = Path.home() / ".local/share/screentime"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
IDLE_FLAG = RUNTIME / "screentime-idle"  # touched by hypridle when idle
LIVE = RUNTIME / "screentime-live.json"  # in-progress event, so the panel is fresh
LOCK = RUNTIME / "screentime.lock"  # only one logger at a time

TICK = 2  # seconds between checks
GAP = 10  # silence longer than this (suspend, stall) breaks an event
IDLE_TIMEOUT = 120  # MUST match the screentime listener in hypridle.conf
FLUSH_EVERY = 60  # write long sessions out in chunks (crash safety)
MAX_FAILS = 30  # consecutive failed polls (~1 min) before assuming Hyprland is gone


# ---------------------------------------------------------------- logger ----


def sockets():
    """Hyprland command sockets, newest first (survives compositor restarts)."""
    found = []
    for p in (RUNTIME / "hypr").glob("*/.socket.sock"):
        try:
            found.append((p.stat().st_mtime, p))
        except OSError:
            pass
    return [p for _, p in sorted(found, reverse=True)]


def active_window():
    """(class, title) of the focused window, None if nothing is focused.
    Raises OSError when no Hyprland socket answers."""
    for path in sockets():
        try:
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(2)
                s.connect(str(path))
                s.sendall(b"j/activewindow")
                buf = b""
                while chunk := s.recv(4096):
                    buf += chunk
            win = json.loads(buf or b"{}")
        except (OSError, ValueError):
            continue  # stale socket or garbage reply: try the next one
        if isinstance(win, dict) and win.get("class"):
            return win["class"], win.get("title", "")
        return None
    raise OSError("no reachable Hyprland socket")


def idle_since():
    """Time of the last input if hypridle says we're idle, else None.
    hypridle touches the flag IDLE_TIMEOUT seconds after the last input."""
    try:
        return IDLE_FLAG.stat().st_mtime - IDLE_TIMEOUT
    except OSError:
        return None


def flush(ev):
    if ev and ev["end"] > ev["start"]:
        DATA.mkdir(parents=True, exist_ok=True)
        day = time.strftime("%F", time.localtime(ev["start"]))
        with open(DATA / f"{day}.jsonl", "a") as f:
            f.write(json.dumps(ev) + "\n")


def commit_old(ev):
    """Write out the part of a long event that can no longer be trimmed by an
    idle report (anything older than IDLE_TIMEOUT + GAP), keep the rest."""
    upto = min(ev["end"], time.time() - IDLE_TIMEOUT - GAP)
    if upto - ev["start"] >= FLUSH_EVERY:
        flush({**ev, "end": upto})
        ev["start"] = upto


def set_live(ev):
    try:
        if ev:
            tmp = LIVE.with_suffix(".tmp")
            tmp.write_text(json.dumps(ev))
            tmp.replace(LIVE)
        else:
            LIVE.unlink(missing_ok=True)
    except OSError:
        pass


def log():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("screentime: a logger is already running", file=sys.stderr)
        return
    IDLE_FLAG.unlink(missing_ok=True)  # stale flag from a previous session
    set_live(None)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))

    ev = None
    fails = 0
    try:
        while fails < MAX_FAILS:
            now = time.time()
            last_input = idle_since()
            cur = None
            if last_input is None:
                try:
                    cur = active_window()
                    fails = 0
                except OSError:
                    fails += 1

            if last_input is not None:
                # idle: only credit time up to the last real input
                if ev:
                    ev["end"] = max(ev["start"], min(ev["end"], last_input))
                    flush(ev)
                ev = None
            elif cur is None:
                # nothing focused / Hyprland unreachable: close the event
                flush(ev)
                ev = None
            elif ev and (ev["class"], ev["title"]) == cur and now - ev["end"] <= GAP:
                ev["end"] = now
                commit_old(ev)
            else:
                # window switch (or first sample / resume after a gap)
                if ev and now - ev["end"] <= GAP:
                    ev["end"] = now  # old window was in use until the switch
                flush(ev)
                ev = {"start": now, "end": now, "class": cur[0], "title": cur[1]}
            set_live(ev)
            time.sleep(TICK)
    finally:
        flush(ev)
        set_live(None)


# --------------------------------------------------------------- reports ----


def read_day(d):
    """All valid events logged on day d. Corrupt lines are skipped."""
    out = []
    try:
        lines = (DATA / f"{d}.jsonl").read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        try:
            e = json.loads(line)
            e["end"] - e["start"]
            e["class"]
        except (ValueError, KeyError, TypeError):
            continue
        out.append(e)
    return out


def live_event():
    """The logger's in-progress event (ignored if the logger died)."""
    try:
        if time.time() - LIVE.stat().st_mtime < GAP:
            e = json.loads(LIVE.read_text())
            e["end"] - e["start"]
            e["class"]
            return e
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def events_between(start, end):
    """Yield (day, event) from start to end (dates, inclusive), live event included."""
    d = start
    while d <= end:
        for e in read_day(d):
            yield str(d), e
        d += timedelta(days=1)
    live = live_event()
    if live:
        ld = date.fromtimestamp(live["start"])
        if start <= ld <= end:
            yield str(ld), live


def events(days):
    """Yield (day, event) for the last `days` days, today included."""
    today = date.today()
    return events_between(today - timedelta(days=days - 1), today)


def fmt(sec):
    h, m = divmod(round(sec / 60), 60)
    return f"{h}h {m:02d}m"


def report(days, by_title=False, top=15):
    totals = defaultdict(float)
    for _, e in events(days):
        key = f"{e['class']}: {e.get('title', '')[:50]}" if by_title else e["class"]
        totals[key] += e["end"] - e["start"]
    if not totals:
        print("no data yet")
        return
    for key, sec in sorted(totals.items(), key=lambda x: -x[1])[:top]:
        print(f"{fmt(sec):>8}  {key}")
    print(f"{'--------':>8}\n{fmt(sum(totals.values())):>8}  total")


def summary(days):
    apps = defaultdict(float)
    per_day = {str(date.today() - timedelta(days=i)): 0.0 for i in range(days)}
    for d, e in events(days):
        sec = e["end"] - e["start"]
        apps[e["class"]] += sec
        if d in per_day:
            per_day[d] += sec
    return {
        "total": sum(apps.values()),
        "apps": sorted(([k, v] for k, v in apps.items()), key=lambda x: -x[1]),
        "days": sorted(([k, v] for k, v in per_day.items())),
    }


# ----------------------------------------------------------------- panel ----

# Window-class substrings (lowercase) -> category. First match wins; add your own.
CATEGORIES = [
    ("Browsing", ("firefox", "brave", "chromium", "zen", "librewolf", "qutebrowser")),
    ("Terminal", ("kitty", "alacritty", "foot", "wezterm", "ghostty")),
    ("Code", ("codium", "code", "jetbrains", "zed", "neovide")),
    ("Media", ("mpv", "vlc", "spotify", "celluloid", "imv")),
    (
        "Chat",
        ("discord", "vesktop", "telegram", "signal", "whatsapp", "element", "slack"),
    ),
    ("Reading", ("zathura", "okular", "evince", "obsidian", "libreoffice", "calibre")),
    ("Files", ("thunar", "nautilus", "dolphin", "nemo", "yazi", "pcmanfm")),
]
OTHER = "Other"
SESSION_GAP = 300  # idle longer than this ends a session
TOP_APPS = 12
TOP_TITLES = 5
SPANS = {"day": 1, "week": 7, "month": 30}


def category(cls):
    c = cls.lower()
    for i, (_, keys) in enumerate(CATEGORIES):
        if any(k in c for k in keys):
            return i
    return len(CATEGORIES)


def category_name(i):
    return CATEGORIES[i][0] if i < len(CATEGORIES) else OTHER


GENERIC_TAIL = {"desktop", "app", "client", "gui", "main", "bin"}


def pretty(cls):
    """Window class -> display name (org.gnome.Nautilus -> Nautilus,
    org.telegram.desktop -> Telegram)."""
    parts = [x for x in cls.split(".") if x]
    while len(parts) > 1 and parts[-1].lower() in GENERIC_TAIL:
        parts.pop()
    name = (parts[-1] if parts else cls).replace("-", " ").replace(
        "_", " "
    ).strip() or cls
    return name[:1].upper() + name[1:] if name.islower() else name


def short(d):
    return f"{d.day} {d:%b}"


def with_weekday(d):
    return f"{d:%a} {d.day} {d:%b}"


def add_hours(buckets, e):
    """Spread an event over the clock hours it covers."""
    t, end = e["start"], e["end"]
    while t < end:
        lt = time.localtime(t)
        to_next = 3600 - lt.tm_min * 60 - lt.tm_sec - (t - int(t))
        stop = min(end, t + to_next)
        buckets[lt.tm_hour] += stop - t
        t = stop


def session_lengths(evs):
    """Active seconds per session; idle gaps over SESSION_GAP split sessions."""
    out, cur, last_end = [], 0.0, None
    for e in sorted(evs, key=lambda e: e["start"]):
        if last_end is not None and e["start"] - last_end > SESSION_GAP:
            out.append(cur)
            cur = 0.0
        cur += e["end"] - e["start"]
        last_end = e["end"] if last_end is None else max(last_end, e["end"])
    if last_end is not None:
        out.append(cur)
    return out


def previous_total(rng, offset, start, n):
    """Total of the period just before this one. For today, only up to the same
    time of day, so a half-finished day isn't compared with a whole one."""
    pstart, pend = start - timedelta(days=n), start - timedelta(days=1)
    lo = hi = None
    if rng == "day" and offset == 0:
        lo = time.mktime(pstart.timetuple())
        hi = lo + (time.time() - time.mktime(date.today().timetuple()))
    total = 0.0
    for _, e in events_between(pstart, pend):
        s, en = e["start"], e["end"]
        if lo is not None:
            s, en = max(s, lo), min(en, hi)
        total += max(0.0, en - s)
    return total


def panel(rng="day", offset=0):
    if rng not in SPANS:
        rng = "day"
    offset = max(0, int(offset))
    n = SPANS[rng]
    today = date.today()
    end = today - timedelta(days=n * offset)
    start = end - timedelta(days=n - 1)

    by_day = defaultdict(list)
    for d, e in events_between(start, end):
        by_day[d].append(e)

    apps = defaultdict(float)
    titles = defaultdict(lambda: defaultdict(float))
    cats = defaultdict(float)
    hours = [0.0] * 24
    sessions = []
    days = []
    starts, ends = [], []
    d = start
    while d <= end:
        evs = by_day.get(str(d), [])
        day_total = 0.0
        for e in evs:
            sec = e["end"] - e["start"]
            day_total += sec
            cls = e["class"]
            apps[cls] += sec
            titles[cls][(e.get("title") or "")[:70]] += sec
            cats[category(cls)] += sec
            add_hours(hours, e)
            starts.append(e["start"])
            ends.append(e["end"])
        sessions += session_lengths(evs)
        days.append([str(d), day_total])
        d += timedelta(days=1)

    total = sum(apps.values())
    first_day = next((i for i, x in enumerate(days) if x[1] > 0), None)
    active_days = len(days) - first_day if first_day is not None else 0

    if offset == 0:
        label = "Today" if rng == "day" else f"Last {n} days"
        sub = (
            f"{start:%A} {short(start)}"
            if rng == "day"
            else f"{short(start)} to {short(end)}"
        )
        vs = "yesterday at this time" if rng == "day" else f"the previous {n} days"
    else:
        if rng == "day":
            label = "Yesterday" if offset == 1 else with_weekday(start)
            sub = f"{start:%A} {short(start)}" if offset == 1 else f"{offset} days ago"
            vs = "the day before"
        else:
            label = f"{short(start)} to {short(end)}"
            sub = f"ends {n * offset} days ago"
            vs = f"the {n} days before"

    stems = sorted(p.stem for p in DATA.glob("*.jsonl")) if DATA.exists() else []
    live = live_event() if offset == 0 else None
    return {
        "range": rng,
        "offset": offset,
        "label": label,
        "sublabel": sub,
        "vs": vs,
        "start": str(start),
        "end": str(end),
        "total": total,
        "prev_total": previous_total(rng, offset, start, n),
        "avg": total / active_days if active_days else 0.0,
        "apps": [
            {
                "name": pretty(cls),
                "class": cls,
                "sec": sec,
                "cat": category(cls),
                "titles": [
                    [t, v]
                    for t, v in sorted(titles[cls].items(), key=lambda x: -x[1])[
                        :TOP_TITLES
                    ]
                ],
            }
            for cls, sec in sorted(apps.items(), key=lambda x: -x[1])[:TOP_APPS]
        ],
        "app_count": len(apps),
        "categories": [
            {"name": category_name(i), "idx": i, "sec": sec}
            for i, sec in sorted(cats.items(), key=lambda x: -x[1])
        ],
        "days": days,
        "hours": hours,
        "sessions": len(sessions),
        "longest": max(sessions, default=0.0),
        "first": time.strftime("%H:%M", time.localtime(min(starts))) if starts else "",
        "last": time.strftime("%H:%M", time.localtime(max(ends))) if ends else "",
        "now": (
            {
                "name": pretty(live["class"]),
                "title": (live.get("title") or "")[:80],
            }
            if live
            else None
        ),
        "any_data": bool(stems),
        "has_older": bool(stems) and stems[0] < str(start),
    }


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "today"
    if cmd == "log":
        log()
    elif cmd == "today":
        report(1)
    elif cmd == "week":
        report(7)
    elif cmd == "titles":
        report(1, by_title=True)
    elif cmd == "panel":
        rng = sys.argv[2] if len(sys.argv) > 2 else "day"
        try:
            offset = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        except ValueError:
            offset = 0
        print(json.dumps(panel(rng, offset)))
    elif cmd == "json":
        print(json.dumps({"today": summary(1), "week": summary(7)}))
    else:
        print(
            "usage: screentime [log|today|week|titles|json|panel [day|week|month] [offset]]"
        )


if __name__ == "__main__":
    main()
