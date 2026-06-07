#!/usr/bin/env python3
"""Smoke-test Dakota State University Modern Campus catalog scraping."""

from __future__ import annotations

import re
import subprocess
import sys

CATALOG_BASE = "https://catalog.dsu.edu"
CATALOG_LIST = f"{CATALOG_BASE}/misc/catalog_list.php"


def fetch(url: str) -> str:
    return subprocess.check_output(
        ["curl", "-sL", url],
        text=True,
        timeout=60,
    )


def discover_current_catalogs(html: str) -> dict[str, str]:
    """Return label -> catoid for non-archived undergraduate/graduate catalogs."""
    found: dict[str, str] = {}
    for match in re.finditer(
        r"href=['\"]/index\.php\?catoid=(\d+)['\"][^>]*>([^<]+)</a>",
        html,
        flags=re.IGNORECASE,
    ):
        catoid, title = match.group(1), match.group(2).strip()
        if re.search(r"archived", title, re.IGNORECASE):
            continue
        lower = title.lower()
        if "undergraduate" in lower and "undergraduate" not in found:
            found["Undergraduate"] = catoid
        elif re.search(r"\bgraduate\b", lower) and "Graduate" not in found:
            found["Graduate"] = catoid
    return found


def count_program_links(html: str) -> int:
    return len(re.findall(r"preview_program\.php\?[^\"']*poid=", html, flags=re.IGNORECASE))


def main() -> int:
    print("Fetching DSU catalog gateway…")
    list_html = fetch(CATALOG_LIST)
    catalogs = discover_current_catalogs(list_html)
    print(f"Discovered catalogs: {catalogs}")
    if "Undergraduate" not in catalogs or "Graduate" not in catalogs:
        print("FAIL: expected current Undergraduate and Graduate catalogs")
        return 1

    undergrad_catoid = catalogs["Undergraduate"]
    index_url = f"{CATALOG_BASE}/index.php?catoid={undergrad_catoid}"
    print(f"Fetching undergraduate index ({index_url})…")
    index_html = fetch(index_url)

    # Prefer "Academic Programs" (DSU lists majors/degrees here).
    nav_match = re.search(
        r'content\.php\?catoid=' + re.escape(undergrad_catoid) + r'&navoid=(\d+)"[^>]*>Academic Programs',
        index_html,
        flags=re.IGNORECASE,
    )
    if not nav_match:
        nav_match = re.search(
            r"content\.php\?catoid=" + re.escape(undergrad_catoid) + r"&navoid=(\d+)",
            index_html,
            flags=re.IGNORECASE,
        )
    program_count = 0
    if nav_match:
        navoid = nav_match.group(1)
        content_url = f"{CATALOG_BASE}/content.php?catoid={undergrad_catoid}&navoid={navoid}"
        print(f"Fetching program listing page ({content_url})…")
        content_html = fetch(content_url)
        program_count = count_program_links(content_html)

    print(f"Undergraduate program links found: {program_count}")
    if program_count < 5:
        print("FAIL: expected multiple preview_program links on DSU undergraduate catalog")
        return 1

    print("PASS: DSU Modern Campus catalog scraper smoke test succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
