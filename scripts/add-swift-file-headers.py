#!/usr/bin/env python3
"""Insert Feature/Purpose file headers for Swift sources under College/ and CollegeTests/."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FEATURE_FROM_PATH = [
    (r"College/Features/([^/]+)/", 1),
    (r"CollegeTests/Features/([^/]+)/", 1),
    (r"College/App/", "App"),
    (r"College/Core/Data/", "Core/Data"),
    (r"College/Core/", "Core"),
    (r"College/Debug/", "Debug"),
]

SKIP_PREFIXES = ("// ", "//Feature:", "//Purpose:", "//Data:")


def infer_feature(rel: str) -> str:
    for pattern, group in FEATURE_FROM_PATH:
        if isinstance(group, int):
            m = re.search(pattern, rel)
            if m:
                return m.group(group)
        elif pattern in rel:
            return str(group)
    if rel.startswith("College/"):
        parts = rel.split("/")
        if len(parts) > 2 and parts[1] not in ("Features", "Core", "App", "Debug"):
            return parts[1]
    return "Shared"


def primary_type(content: str, filename: str) -> str:
    for kind in ("struct", "class", "enum", "actor", "protocol"):
        m = re.search(rf"\b{kind}\s+(\w+)", content)
        if m:
            return m.group(1)
    return Path(filename).stem


def has_header(content: str) -> bool:
    lines = content.splitlines()[:8]
    return any("Purpose:" in ln or "Feature:" in ln for ln in lines)


def purpose_line(rel: str, type_name: str, feature: str) -> str:
    label = feature.replace("/", " · ")
    return f"// Purpose: {label} — {type_name}."


def process(path: Path) -> bool:
    rel = path.relative_to(ROOT).as_posix()
    content = path.read_text(encoding="utf-8", errors="replace")
    if has_header(content):
        return False
    feature = infer_feature(rel)
    type_name = primary_type(content, path.name)
    header = (
        f"// {path.name}\n"
        f"// Feature: {feature}\n"
        f"{purpose_line(rel, type_name, feature)}\n"
        f"// Data: CollegePersistence / repositories when applicable.\n"
    )
    # Preserve shebang or leading comments block only if file starts with import
    stripped = content.lstrip()
    if stripped.startswith("import "):
        new_content = header + "\n" + content
    else:
        new_content = header + "\n" + content
    path.write_text(new_content, encoding="utf-8")
    return True


def main() -> None:
    changed = 0
    for base in ("College", "CollegeTests"):
        for path in (ROOT / base).rglob("*.swift"):
            if process(path):
                changed += 1
    print(f"headers added: {changed}")


if __name__ == "__main__":
    main()
