#!/usr/bin/env python3
"""
Keep qBittorrent.conf's WebUI\\Password_PBKDF2 in sync with a plaintext
password read from a secret file (e.g. an agenix-decrypted secret).

Usage: sync-webui-password.py <password-file> <qBittorrent.conf path>

- If the conf file already has a Password_PBKDF2 line whose hash verifies
  against the current password, nothing is written and "unchanged" is
  printed.
- Otherwise a new PBKDF2-HMAC-SHA512 hash (100000 iterations, 16-byte
  salt) is generated, the line is inserted/replaced in place, and
  "changed" is printed so the caller knows whether to restart the
  running qbittorrent-nox service.

This mirrors exactly what qBittorrent itself does when you set a password
via the WebUI (see src/base/utils/password.cpp upstream), so the resulting
hash is a normal, valid WebUI password - not a workaround.
"""

import base64
import hashlib
import os
import re
import sys

ITERATIONS = 100_000
SALT_SIZE = 16

PBKDF2_LINE_RE = re.compile(r"^WebUI\\Password_PBKDF2=.*$", re.MULTILINE)
BYTEARRAY_RE = re.compile(r"@ByteArray\(([^:]+):([^)]+)\)")
USERNAME_LINE_RE = re.compile(r"^WebUI\\Username=.*$", re.MULTILINE)


def make_hash(password: bytes) -> str:
    salt = os.urandom(SALT_SIZE)
    digest = hashlib.pbkdf2_hmac("sha512", password, salt, ITERATIONS)
    return "@ByteArray(" + base64.b64encode(salt).decode() + ":" + base64.b64encode(digest).decode() + ")"


def verifies(password: bytes, existing_value: str) -> bool:
    m = BYTEARRAY_RE.search(existing_value)
    if not m:
        return False
    salt = base64.b64decode(m.group(1))
    expected = base64.b64decode(m.group(2))
    return hashlib.pbkdf2_hmac("sha512", password, salt, ITERATIONS) == expected


def main() -> None:
    password_file, conf_file = sys.argv[1], sys.argv[2]
    password = open(password_file, "rb").read().strip()
    conf = open(conf_file).read()

    existing = PBKDF2_LINE_RE.search(conf)
    if existing and verifies(password, existing.group(0)):
        print("unchanged")
        return

    new_line = 'WebUI\\Password_PBKDF2="' + make_hash(password) + '"'

    if existing:
        conf = PBKDF2_LINE_RE.sub(lambda _: new_line, conf, count=1)
    elif USERNAME_LINE_RE.search(conf):
        conf = USERNAME_LINE_RE.sub(lambda mo: mo.group(0) + "\n" + new_line, conf, count=1)
    else:
        conf = conf.rstrip("\n") + "\n" + new_line + "\n"

    with open(conf_file, "w") as f:
        f.write(conf)

    print("changed")


if __name__ == "__main__":
    main()
