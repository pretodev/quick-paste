#!/usr/bin/env python3
"""Read a clipboard URI payload and return local file paths as JSON."""

import json
import os
import sys
from urllib.parse import unquote_to_bytes, urlsplit


def paths_from_payload(payload, mime):
    try:
        lines = payload.decode("utf-8-sig").splitlines()
    except UnicodeDecodeError:
        return []
    if mime == "x-special/gnome-copied-files":
        if not lines or lines[0] not in ("copy", "cut"):
            return []
        lines = lines[1:]
    else:
        lines = [line for line in lines if not line.startswith("#")]

    paths = []
    for line in lines:
        line = line.rstrip("\r")
        if not line:
            continue
        try:
            uri = urlsplit(line)
            if uri.scheme.lower() != "file" or uri.netloc.lower() not in ("", "localhost"):
                return []
            if uri.query or uri.fragment:
                return []
            path = os.fsdecode(unquote_to_bytes(uri.path))
            if not path.startswith("/") or "\x00" in path:
                return []
        except (ValueError, UnicodeError):
            return []
        paths.append(path)
    return paths


if __name__ == "__main__":
    with open(sys.argv[1], "rb") as source:
        payload = source.read()
    print(json.dumps(paths_from_payload(payload, sys.argv[2]), ensure_ascii=True))
