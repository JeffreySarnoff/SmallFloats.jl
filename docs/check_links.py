#!/usr/bin/env python3
"""Fail when a generated Documenter site contains a broken internal link.

Usage: python docs/check_links.py docs/build

The checker intentionally works on rendered HTML.  That catches differences
between Documenter's local flat-file layout and its deployed pretty-URL layout,
as well as generated navigation links and Markdown links rewritten by
Documenter.
"""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if attributes.get("id"):
            self.ids.add(attributes["id"])
        if tag == "a" and attributes.get("href"):
            self.links.append(attributes["href"])


def external(url: str) -> bool:
    parts = urlsplit(url)
    return bool(parts.scheme or parts.netloc) or url.startswith(("mailto:", "javascript:", "data:"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path, help="Documenter HTML build directory")
    args = parser.parse_args()
    site = args.site.resolve()
    pages = sorted(site.rglob("*.html"))
    if not pages:
        raise SystemExit(f"No HTML pages found beneath {site}")

    parsed: dict[Path, Page] = {}
    for page in pages:
        document = Page()
        document.feed(page.read_text(encoding="utf-8"))
        parsed[page.resolve()] = document

    failures: list[str] = []
    for source, document in parsed.items():
        for href in document.links:
            if href in ("", "#") or external(href):
                continue
            parts = urlsplit(href)
            target = source if not parts.path else (source.parent / unquote(parts.path)).resolve()
            # A trailing slash is a URL for an HTML directory index.
            if parts.path.endswith("/"):
                target /= "index.html"
            if target.is_dir():
                target /= "index.html"
            if not target.is_file():
                failures.append(f"{source.relative_to(site)}: {href} -> missing {target.relative_to(site)}")
                continue
            if parts.fragment:
                target_page = parsed.get(target)
                if target_page is None or unquote(parts.fragment) not in target_page.ids:
                    failures.append(f"{source.relative_to(site)}: {href} -> missing anchor")

    if failures:
        raise SystemExit("Broken internal documentation links:\n" + "\n".join(failures))
    print(f"Checked {len(pages)} HTML pages: all internal links and anchors resolve.")


if __name__ == "__main__":
    main()
