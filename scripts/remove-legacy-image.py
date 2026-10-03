#!/usr/bin/env python3
"""Remove an older Quick Paste image from the native Omarchy history."""

import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile


def main() -> None:
    if len(sys.argv) != 2:
        return
    source = Path(sys.argv[1])
    history = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "omarchy/clipboard-history.json"
    try:
        with source.open("rb") as image:
            digest = hashlib.file_digest(image, "sha256").hexdigest()
        entries = json.loads(history.read_text(encoding="utf-8"))
        if not isinstance(entries, list):
            return
    except (OSError, ValueError, TypeError):
        return

    def matches(entry: object) -> bool:
        if not isinstance(entry, dict) or entry.get("type") != "image":
            return False
        path = entry.get("path")
        return (isinstance(path, str) and Path(path).parent.name == "clipboard-images"
                and Path(path).stem == digest)

    updated = [entry for entry in entries if not matches(entry)]
    if len(updated) == len(entries):
        return
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=history.parent,
                                         prefix=".clipboard-history.", delete=False) as output:
            temp_path = Path(output.name)
            json.dump(updated, output, ensure_ascii=False, indent=2)
            output.write("\n")
        os.replace(temp_path, history)
    except OSError:
        if "temp_path" in locals():
            temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
