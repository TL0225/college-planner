#!/usr/bin/env python3
"""Refresh performance-file-manifest-index.tsv for post-reorg paths."""
from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/performance-file-manifest-index.tsv"
MAP = ROOT / "docs/reorg-move-map.csv"


def load_map() -> dict[str, str]:
    m: dict[str, str] = {}
    if not MAP.is_file():
        return m
    with MAP.open(newline="") as f:
        for row in csv.DictReader(f):
            o, n = row["old_path"], row["new_path"]
            if o.endswith("/"):
                continue
            m[o] = n
    return m


def remap(path: str, path_map: dict[str, str]) -> str | None:
    if (ROOT / path).is_file():
        return path
    # longest prefix match
    best = None
    best_len = -1
    for old, new in path_map.items():
        if path == old:
            return new
        prefix = old if old.endswith("/") else old + "/"
        if path.startswith(prefix) and len(prefix) > best_len:
            best_len = len(prefix)
            best = new + path[len(old.rstrip("/")) :]
    if best and (ROOT / best).is_file():
        return best
    # Features/Core heuristic
    parts = path.split("/")
    if len(parts) < 3 or parts[0] != "College":
        return None
    top = parts[1]
    rest = "/".join(parts[2:])
    candidates = [
        f"College/Features/{top}/{rest}",
        f"College/Core/{top}/{rest}",
        f"College/Core/Data/{rest}" if top == "Data" else None,
        f"College/Core/Services/{rest}" if top == "Services" else None,
        f"College/Core/DesignSystem/{rest}" if top == "DesignSystem" else None,
    ]
    for c in candidates:
        if c and (ROOT / c).is_file():
            return c
    return None


def module_for(path: str) -> str:
    parts = path.split("/")
    if len(parts) >= 3 and parts[1] == "Features":
        return parts[2]
    if len(parts) >= 2:
        return parts[1]
    return "College"


def main() -> None:
    path_map = load_map()
    rows: list[tuple[str, str, str, str, str]] = []
    seen: set[str] = set()

    if OUT.is_file():
        with OUT.open() as f:
            reader = csv.DictReader(f, delimiter="\t")
            for row in reader:
                old_path = row["path"]
                new_path = remap(old_path, path_map) or old_path
                if not (ROOT / new_path).is_file():
                    continue
                lines = str(sum(1 for _ in (ROOT / new_path).open(encoding="utf-8", errors="replace")))
                mod = module_for(new_path)
                rows.append(
                    (
                        new_path,
                        lines,
                        mod,
                        row.get("coverage", "5c"),
                        row.get("risk_hint", "Y"),
                    )
                )
                seen.add(new_path)

    for swift in sorted((ROOT / "College").rglob("*.swift")):
        rel = swift.relative_to(ROOT).as_posix()
        if rel in seen:
            continue
        lines = str(sum(1 for _ in swift.open(encoding="utf-8", errors="replace")))
        rows.append((rel, lines, module_for(rel), "5c", "Y"))

    rows.sort(key=lambda r: r[0])
    with OUT.open("w") as f:
        f.write("path\tlines\tmodule\tcoverage\trisk_hint\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(f"wrote {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
