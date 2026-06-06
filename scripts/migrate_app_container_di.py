#!/usr/bin/env python3
"""Migrate @EnvironmentObject to @Environment(AppContainer.self) via computed property aliases."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
COLLEGE = REPO / "College"

SKIP_PREFIXES = ("College/Features/Catalog/Ingest/",)

# (regex for declaration line, alias property line)
DECLARATIONS: list[tuple[str, str]] = [
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+collegePersistence:\s*CollegePersistence\s*\n",
        "private var collegePersistence: CollegePersistence { container.persistence }\n",
    ),
    (
        r"@EnvironmentObject\s+var\s+collegePersistence:\s*CollegePersistence\s*\n",
        "var collegePersistence: CollegePersistence { container.persistence }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+persistence:\s*CollegePersistence\s*\n",
        "private var persistence: CollegePersistence { container.persistence }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+appDataStore:\s*AppDataStore\s*\n",
        "private var appDataStore: AppDataStore { container.appDataStore }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+appNotifications:\s*AppNotificationCenter\s*\n",
        "private var appNotifications: AppNotificationCenter { container.appNotifications }\n",
    ),
    (
        r"@EnvironmentObject\s+var\s+appNotificationCenter:\s*AppNotificationCenter\s*\n",
        "var appNotificationCenter: AppNotificationCenter { container.appNotifications }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+notifications:\s*AppNotificationCenter\s*\n",
        "private var notifications: AppNotificationCenter { container.appNotifications }\n",
    ),
    (
        r"@EnvironmentObject\s+var\s+notifications:\s*AppNotificationCenter\s*\n",
        "var notifications: AppNotificationCenter { container.appNotifications }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+calendarManager:\s*CalendarIntegrationManager\s*\n",
        "private var calendarManager: CalendarIntegrationManager { container.calendarManager }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+locationPermissionService:\s*LocationPermissionService\s*\n",
        "private var locationPermissionService: LocationPermissionService { container.locationPermissionService }\n",
    ),
    (
        r"@EnvironmentObject\s+var\s+locationService:\s*LocationPermissionService\s*\n",
        "var locationService: LocationPermissionService { container.locationPermissionService }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+locationService:\s*LocationPermissionService\s*\n",
        "private var locationService: LocationPermissionService { container.locationPermissionService }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+securityManager:\s*SecurityManager\s*\n",
        "private var securityManager: SecurityManager { container.securityManager }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+brightspaceCoordinator:\s*BrightspaceWebCoordinator\s*\n",
        "private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }\n",
    ),
    (
        r"@EnvironmentObject\s+(?:private\s+)?var\s+coordinator:\s*BrightspaceWebCoordinator\s*\n",
        "private var coordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }\n",
    ),
    (
        r"@Environment\(ModalCoordinator\.self\)\s+(?:private\s+)?var\s+modalCoordinator\s*\n",
        "private var modalCoordinator: ModalCoordinator { container.modalCoordinator }\n",
    ),
    (
        r"@Environment\(ModalCoordinator\.self\)\s+var\s+modalCoordinator\s*\n",
        "var modalCoordinator: ModalCoordinator { container.modalCoordinator }\n",
    ),
    (
        r"@Environment\(AcademicMetricsStore\.self\)\s+(?:private\s+)?var\s+academicMetricsStore\s*\n",
        "private var academicMetricsStore: AcademicMetricsStore { container.academicMetricsStore }\n",
    ),
    (
        r"@Environment\(AuditSnapshotStore\.self\)\s+(?:private\s+)?var\s+auditSnapshotStore\s*\n",
        "private var auditSnapshotStore: AuditSnapshotStore { container.auditSnapshotStore }\n",
    ),
    (
        r"@Environment\(LaunchPreloadCoordinator\.self\)\s+(?:private\s+)?var\s+launchPreloadCoordinator\s*\n",
        "private var launchPreloadCoordinator: LaunchPreloadCoordinator { container.launchPreloadCoordinator }\n",
    ),
    (
        r"@Environment\(AppActivityCoordinator\.self\)\s+(?:private\s+)?var\s+appActivity\s*\n",
        "private var appActivity: AppActivityCoordinator { container.appActivity }\n",
    ),
]

CONTAINER_DECL = "    @Environment(AppContainer.self) private var container\n"

INJECT_REMOVE = [
    r"\.environmentObject\(collegePersistence\)\s*\n?",
    r"\.environmentObject\(appDataStore\)\s*\n?",
    r"\.environmentObject\(appNotifications\)\s*\n?",
    r"\.environmentObject\(calendarManager\)\s*\n?",
    r"\.environmentObject\(locationPermissionService\)\s*\n?",
    r"\.environmentObject\(securityManager\)\s*\n?",
    r"\.environmentObject\(brightspaceCoordinator\)\s*\n?",
    r"\.environmentObject\(CollegePersistence\.shared\)\s*\n?",
    r"\.environmentObject\(AppNotificationCenter\.shared\)\s*\n?",
    r"\.environmentObject\(SecurityManager\.shared\)\s*\n?",
    r"\.environment\(container\.modalCoordinator\)\s*\n?",
    r"\.environment\(appContainer\.modalCoordinator\)\s*\n?",
    r"\.environment\(container\.academicMetricsStore\)\s*\n?",
    r"\.environment\(container\.auditSnapshotStore\)\s*\n?",
    r"\.environment\(container\.launchPreloadCoordinator\)\s*\n?",
    r"\.environment\(container\.appActivity\)\s*\n?",
    r"\.environment\(appContainer\.appActivity\)\s*\n?",
]


def should_skip(path: Path) -> bool:
    rel = str(path.relative_to(REPO)).replace("\\", "/")
    return any(rel.startswith(p) for p in SKIP_PREFIXES)


def insert_container_after_opening_brace(source: str, struct_pattern: str) -> str:
    """Insert container declaration at each struct/class that had a migration."""
    lines = source.splitlines(keepends=True)
    result: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        result.append(line)
        if re.match(struct_pattern, line.strip()):
            # Find opening brace on this or next lines
            j = i
            while j < len(lines) and "{" not in lines[j]:
                j += 1
            if j < len(lines) and "{" in lines[j]:
                # Copy lines between i+1 and j into result if not already done
                for k in range(i + 1, j + 1):
                    if k > i:
                        result.append(lines[k])
                brace_line = lines[j]
                if "@Environment(AppContainer.self)" not in "".join(result[-8:]):
                    indent = re.match(r"^(\s*)", brace_line).group(1) + "    "
                    result.append(f"{indent}@Environment(AppContainer.self) private var container\n")
                i = j
        i += 1
    return "".join(result)


def migrate_struct_block(block: str) -> tuple[str, bool]:
    changed = False
    new_block = block
    had_migration = False

    for pattern, alias in DECLARATIONS:
        if re.search(pattern, new_block):
            # Skip if alias already present
            alias_name = alias.split(":")[0].split()[-1]
            if f"{alias_name}:" in new_block and "container." in new_block:
                new_block = re.sub(pattern, "", new_block)
                had_migration = True
                changed = True
                continue
            new_block = re.sub(pattern, alias, new_block)
            had_migration = True
            changed = True

    if had_migration and "@Environment(AppContainer.self)" not in new_block:
        # Insert after first line with opening brace
        m = re.search(r"(\{)\s*\n", new_block)
        if m:
            insert_pos = m.end()
            new_block = new_block[:insert_pos] + CONTAINER_DECL + new_block[insert_pos:]
            changed = True

    return new_block, changed


def split_swift_structs(source: str) -> list[str]:
    """Rough split on struct/class boundaries for per-type migration."""
    parts = re.split(r"(?=^(?:struct|class|private struct|private class|fileprivate struct)\s)", source, flags=re.MULTILINE)
    return parts if parts else [source]


def migrate_file(path: Path) -> bool:
    if should_skip(path):
        return False

    source = path.read_text(encoding="utf-8")
    original = source

    for pattern in INJECT_REMOVE:
        source = re.sub(pattern, "", source)

    # Per-block migration
    parts = split_swift_structs(source)
    new_parts = []
    any_changed = False
    for part in parts:
        new_part, changed = migrate_struct_block(part)
        new_parts.append(new_part)
        any_changed = any_changed or changed

    source = "".join(new_parts)

    # Files without struct split (top-level only) — whole file pass
    new_source, changed = migrate_struct_block(source)
    if changed:
        source = new_source
        any_changed = True

    # Normalize duplicate container declarations in same struct
    source = re.sub(
        r"(@Environment\(AppContainer\.self\) private var container\s*\n){2,}",
        "@Environment(AppContainer.self) private var container\n",
        source,
    )

    # ContentView uses appContainer — rename for consistency with existing code
    if path.name == "ContentView.swift":
        source = source.replace(
            "@Environment(AppContainer.self) private var container\n",
            "@Environment(AppContainer.self) private var appContainer\n",
        )
        source = re.sub(
            r"container\.(persistence|appDataStore|appNotifications|calendarManager|locationPermissionService|securityManager|brightspaceCoordinator|modalCoordinator|academicMetricsStore|auditSnapshotStore|launchPreloadCoordinator|appActivity)",
            r"appContainer.\1",
            source,
        )

    # AcademicsView etc. already have appContainer — avoid duplicate
    source = re.sub(
        r"@Environment\(AppContainer\.self\) private var container\n(\s*)@Environment\(AppContainer\.self\) private var appContainer\n",
        r"@Environment(AppContainer.self) private var appContainer\n",
        source,
    )
    # If file has appContainer, use appContainer in aliases instead of container
    if "@Environment(AppContainer.self) private var appContainer" in source:
        source = source.replace("{ container.", "{ appContainer.")
        source = re.sub(
            r"@Environment\(AppContainer\.self\) private var container\n",
            "",
            source,
        )

    if source != original:
        path.write_text(source, encoding="utf-8")
        return True
    return False


def main() -> int:
    changed = []
    for path in sorted(COLLEGE.rglob("*.swift")):
        if migrate_file(path):
            changed.append(path.relative_to(REPO))
    print(f"Migrated {len(changed)} files")
    for p in changed:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
