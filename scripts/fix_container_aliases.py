#!/usr/bin/env python3
"""Add missing AppContainer computed-property aliases to Swift structs."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
COLLEGE = REPO / "College"

ALIASES = [
    ("calendarManager", "CalendarIntegrationManager", "calendarManager"),
    ("locationPermissionService", "LocationPermissionService", "locationPermissionService"),
    ("locationService", "LocationPermissionService", "locationPermissionService"),
    ("coordinator", "BrightspaceWebCoordinator", "brightspaceCoordinator"),
    ("brightspaceCoordinator", "BrightspaceWebCoordinator", "brightspaceCoordinator"),
    ("notifications", "AppNotificationCenter", "appNotifications"),
    ("appNotifications", "AppNotificationCenter", "appNotifications"),
    ("appNotificationCenter", "AppNotificationCenter", "appNotifications"),
    ("securityManager", "SecurityManager", "securityManager"),
    ("collegePersistence", "CollegePersistence", "persistence"),
    ("persistence", "CollegePersistence", "persistence"),
    ("appDataStore", "AppDataStore", "appDataStore"),
]

CONTAINER_PATTERNS = [
    r"@Environment\(AppContainer\.self\)\s+private\s+var\s+container",
    r"@Environment\(AppContainer\.self\)\s+private\s+var\s+appContainer",
]


def container_ref(block: str) -> str:
    return "appContainer" if "appContainer" in block else "container"


def has_alias(block: str, var_name: str) -> bool:
    return bool(re.search(rf"(?:private\s+)?var\s+{re.escape(var_name)}\s*:", block))


def uses_var(block: str, var_name: str) -> bool:
    return bool(re.search(rf"\b{re.escape(var_name)}\b", block))


def fix_block(block: str) -> str:
    if not any(re.search(p, block) for p in CONTAINER_PATTERNS):
        return block

    ref = container_ref(block)
    insertions: list[str] = []

    for var_name, type_name, path in ALIASES:
        if uses_var(block, var_name) and not has_alias(block, var_name):
            access = "var" if re.search(rf"@EnvironmentObject\s+var\s+{var_name}", block) else "private var"
            insertions.append(
                f"    {access} {var_name}: {type_name} {{ {ref}.{path} }}\n"
            )

    if not insertions:
        return block

    # Insert after container declaration line
    for pattern in CONTAINER_PATTERNS:
        m = re.search(pattern + r"\s*\n", block)
        if m:
            return block[: m.end()] + "".join(insertions) + block[m.end() :]
    return block


def split_top_level_declarations(source: str) -> list[str]:
    parts = re.split(
        r"(?=^(?:struct|class|private struct|fileprivate struct|extension)\s+\w+)",
        source,
        flags=re.MULTILINE,
    )
    return parts if parts else [source]


def migrate_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    parts = [fix_block(p) for p in split_top_level_declarations(original)]
    source = "".join(parts)
    if source != original:
        path.write_text(source, encoding="utf-8")
        return True
    return False


def main() -> None:
    changed = []
    for path in sorted(COLLEGE.rglob("*.swift")):
        if migrate_file(path):
            changed.append(path.relative_to(REPO))
    print(f"Fixed {len(changed)} files")
    for p in changed:
        print(f"  {p}")


if __name__ == "__main__":
    main()
