#!/usr/bin/env python3
"""Give a captured image a stable, typed filename for file URL drags."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys


EXTENSIONS = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/bmp": ".bmp",
    "image/tiff": ".tiff",
    "image/avif": ".avif",
    "image/svg+xml": ".svg",
}


def prepare(path: str, mime: str, state_root: Path) -> str:
    normalized_mime = mime.lower()
    extension = EXTENSIONS.get(normalized_mime)
    if not extension:
        subtype = normalized_mime.removeprefix("image/")
        if normalized_mime.startswith("image/") and re.fullmatch(r"[a-z0-9][a-z0-9-]*", subtype):
            extension = "." + subtype
    if not extension or not path.startswith("/") or "\x00" in path:
        return ""
    source = Path(path)
    try:
        details = source.stat()
        if not stat.S_ISREG(details.st_mode) or not os.access(source, os.R_OK):
            return ""
    except OSError:
        return ""

    if source.suffix.lower() == extension or (normalized_mime == "image/jpeg" and source.suffix.lower() == ".jpeg"):
        return str(source)

    cache = state_root / "omarchy/qick-paste-drag-images"
    key = hashlib.sha256(f"{path}\0{details.st_size}\0{details.st_mtime_ns}".encode()).hexdigest()
    destination = cache / f"{key}{extension}"
    try:
        cache.mkdir(parents=True, exist_ok=True)
        if not destination.is_file():
            temporary = cache / f".{key}.{os.getpid()}.tmp"
            try:
                if source.is_relative_to(state_root / "omarchy/qick-paste-items"):
                    try:
                        os.link(source, temporary)
                    except OSError:
                        shutil.copyfile(source, temporary)
                else:
                    shutil.copyfile(source, temporary)
                os.replace(temporary, destination)
            finally:
                temporary.unlink(missing_ok=True)
        return str(destination)
    except OSError:
        return ""


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--files":
        try:
            paths = json.loads(sys.argv[2])
            ready = (isinstance(paths, list) and bool(paths)
                     and all(isinstance(path, str) and path.startswith("/")
                             and "\x00" not in path and os.access(path, os.R_OK)
                             and (Path(path).is_file() or Path(path).is_dir())
                             for path in paths))
            print("1" if ready else "")
        except (OSError, ValueError, TypeError):
            print("")
    elif len(sys.argv) == 3:
        root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
        print(prepare(sys.argv[1], sys.argv[2], root))
