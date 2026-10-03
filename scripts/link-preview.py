#!/usr/bin/env python3

import html
import json
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse


class OpenGraphParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.values = {}

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "meta":
            return
        values = {str(key).lower(): value for key, value in attrs if value is not None}
        name = (values.get("property") or values.get("name") or "").lower()
        if name in ("og:description", "og:image", "og:url") and name not in self.values:
            content = values.get("content", "").strip()
            if content:
                self.values[name] = content


def web_url(value):
    try:
        parsed = urlparse(value)
        return value if parsed.scheme in ("http", "https") and parsed.netloc else ""
    except ValueError:
        return ""


def main():
    source_url = web_url(sys.argv[1] if len(sys.argv) > 1 else "")
    if not source_url:
        return 1

    parser = OpenGraphParser()
    document = sys.stdin.buffer.read(1_048_576).decode("utf-8", errors="replace")
    parser.feed(document)
    description = re.sub(r"\s+", " ", html.unescape(parser.values.get("og:description", ""))).strip()
    preview_url = web_url(urljoin(source_url, parser.values.get("og:url", "")))
    image_url = web_url(urljoin(preview_url or source_url, parser.values.get("og:image", "")))
    if not description and not preview_url and not image_url:
        return 1

    print(json.dumps({
        "description": description[:1000],
        "image": image_url,
        "url": preview_url,
    }, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
