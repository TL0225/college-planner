#!/usr/bin/env python3
"""Mirror CollegeTests under Features/ and rename legacy SwiftData paths (no code edits)."""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "CollegeTests"

# Filename renames (basename only)
FILE_RENAMES = {
    "SwiftDataTestCase.swift": "PersistenceTestCase.swift",
    "SwiftDataTestHarness.swift": "PersistenceTestHarness.swift",
    "SwiftDataFixtureFactory.swift": "PersistenceFixtureFactory.swift",
    "ProfilePlannerModelsSwiftDataTests.swift": "ProfilePlannerModelsStoreTests.swift",
    "ProfileDomainRepositoriesSwiftDataTests.swift": "ProfileDomainRepositoriesStoreTests.swift",
    "DataWipeSwiftDataTests.swift": "DataWipeStoreTests.swift",
    "CatalogModelsSwiftDataTests.swift": "CatalogModelsStoreTests.swift",
    "CatalogChunkProjectionSwiftDataTests.swift": "CatalogChunkProjectionStoreTests.swift",
    "CatalogBackgroundSyncSwiftDataTests.swift": "CatalogBackgroundSyncStoreTests.swift",
    "CareerRepositorySwiftDataTests.swift": "CareerRepositoryStoreTests.swift",
    "CalendarSearchSwiftDataTests.swift": "CalendarSearchStoreTests.swift",
    "AppBackupRestoreSwiftDataTests.swift": "AppBackupRestoreStoreTests.swift",
    "AcademicsAuditSnapshotSwiftDataTests.swift": "AcademicsAuditSnapshotStoreTests.swift",
}

# Move from Persistence/ (or anywhere under TESTS) to Features/<feature>/
FEATURE_PREFIXES: list[tuple[str, str]] = [
    ("Overview", "Overview"),
    ("Profile", "Profile"),
    ("Calendar", "Calendar"),
    ("Career", "Career"),
    ("Catalog", "Catalog"),
    ("Vault", "Documents"),
    ("Academics", "Academics"),
    ("Workday", "Career"),
    ("Assistant", "Assistant"),
    ("AIAssistant", "Assistant"),
    ("FMRegistry", "Assistant"),
    ("PlannerChunk", "Assistant"),
    ("PlannerVector", "Assistant"),
    ("RequirementFulfillment", "Academics"),
    ("RequirementProgress", "Academics"),
    ("RequirementDisplay", "Academics"),
    ("RequirementBreakdown", "Academics"),
    ("DegreeType", "Degree"),
    ("MinorProgram", "Profile"),
    ("CourseLeaf", "Catalog"),
    ("NYUCourseLeaf", "Catalog"),
    ("ProgramCatalog", "Catalog"),
    ("DSUProgram", "Catalog"),
    ("PDFCatalog", "Catalog"),
    ("DakotaState", "Catalog"),
    ("LocalLLM", "Assistant"),
    ("QwenJson", "Assistant"),
    ("AppUpdate", "Settings"),
    ("UserDefaults", "Core"),
    ("CollegeCore", "Core"),
]

ROOT_KEEP = {
    "TestFixturePaths.swift",
    "CollegeTests+LiveNetwork.swift",
    "Info.plist",
}

PERF_TESTS = {
    "LaunchPerformanceAcceptanceTests.swift",
    "PerformanceBaselineAcceptanceTests.swift",
}

PERSISTENCE_KEEP = {
    "PersistenceTestCase.swift",
    "PersistenceTestHarness.swift",
    "PersistenceFixtureFactory.swift",
    "SchemaMigrationPlanTests.swift",
    "LaunchSingleCatalogMmapTests.swift",
}


def feature_for(name: str) -> str | None:
    for prefix, feat in FEATURE_PREFIXES:
        if name.startswith(prefix):
            return feat
    return None


def rename_in_dir(directory: Path) -> None:
    for old, new in FILE_RENAMES.items():
        src = directory / old
        if src.is_file():
            dst = directory / new
            if dst.exists():
                continue
            src.rename(dst)
            print(f"rename {src.relative_to(ROOT)} -> {new}")


def ensure_persistence_dir() -> Path:
    p = TESTS / "Persistence"
    p.mkdir(parents=True, exist_ok=True)
    return p


def move_to_features() -> None:
    persistence = ensure_persistence_dir()
    # SwiftData folder may still exist
    legacy = TESTS / "SwiftData"
    if legacy.is_dir():
        for item in legacy.iterdir():
            dest = persistence / item.name
            if not dest.exists():
                shutil.move(str(item), str(dest))
        legacy.rmdir()
        print("moved SwiftData/ -> Persistence/")

    rename_in_dir(persistence)

    for path in list(TESTS.rglob("*.swift")):
        if "Features" in path.parts or path.parent == TESTS:
            continue
        if path.parent == persistence:
            base = path.name
            if base in PERSISTENCE_KEEP:
                continue
            feat = feature_for(path.stem)
            if feat is None:
                continue
            dest_dir = TESTS / "Features" / feat
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / base
            if dest.exists():
                continue
            shutil.move(str(path), str(dest))
            print(f"feature {path.relative_to(ROOT)} -> Features/{feat}/")

    # Root-level tests -> Features / Performance / Core
    perf_dir = TESTS / "Performance"
    perf_dir.mkdir(parents=True, exist_ok=True)
    core_dir = TESTS / "Core"
    core_dir.mkdir(parents=True, exist_ok=True)
    support_dir = TESTS / "Support"
    support_dir.mkdir(parents=True, exist_ok=True)

    for path in list(TESTS.glob("*.swift")):
        base = path.name
        if base in ROOT_KEEP:
            dest = support_dir / base
            if not dest.exists():
                shutil.move(str(path), str(dest))
                print(f"support {base}")
            continue
        if base in PERF_TESTS:
            dest = perf_dir / base
            if not dest.exists():
                shutil.move(str(path), str(dest))
                print(f"performance {base}")
            continue
        if base.startswith("CollegeCore") or base.startswith("UserDefaults"):
            dest = core_dir / base
            if not dest.exists():
                shutil.move(str(path), str(dest))
                print(f"core {base}")
            continue
        feat = feature_for(path.stem)
        if feat is None:
            continue
        dest_dir = TESTS / "Features" / feat
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / path.name
        if dest.exists():
            continue
        shutil.move(str(path), str(dest))
        print(f"root -> Features/{feat}/{path.name}")


if __name__ == "__main__":
    move_to_features()
    print("done")
