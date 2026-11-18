#!/usr/bin/env python3
"""Peaks of an audio file, for the player's waveform.

  wave.py <file> [bars]

Prints `bars` numbers (default 64) between 0 and 1 on one line: the loudest
sample in each slice of the song, scaled so the loudest slice is 1. Prints
nothing when ffmpeg is missing or cannot read the file (the player then shows
a plain ruler instead). The result is cached next to the covers, one small
file per song, so a song is only read once.
"""

import array
import hashlib
import os
import subprocess
import sys


def main():
    if len(sys.argv) < 2:
        return
    path = sys.argv[1]
    bars = int(sys.argv[2]) if len(sys.argv) > 2 else 64
    cache_dir = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-music")
    key = hashlib.md5(("%s:%d" % (path, bars)).encode()).hexdigest()[:12]
    cache = os.path.join(cache_dir, "wave-%s.txt" % key)
    try:
        with open(cache) as f:
            sys.stdout.write(f.read())
            return
    except OSError:
        pass
    try:
        out = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-vn", "-ac", "1", "-ar", "2000", "-f", "s16le", "-"],
            capture_output=True,
            timeout=40,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return
    samples = array.array("h")
    samples.frombytes(out[: len(out) - (len(out) % 2)])
    if len(samples) < bars * 4:
        return
    step = len(samples) / bars
    peaks = []
    for i in range(bars):
        chunk = samples[int(i * step) : int((i + 1) * step)]
        peaks.append(max((abs(s) for s in chunk), default=0))
    top = max(peaks) or 1
    # A little compression, so quiet passages still show
    text = " ".join("%.3f" % ((p / top) ** 0.7) for p in peaks)
    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(cache, "w") as f:
            f.write(text)
    except OSError:
        pass
    sys.stdout.write(text)


main()
