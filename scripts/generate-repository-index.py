#!/usr/bin/env python3
"""Generate or validate docs/REPOSITORY.md from git-tracked paths."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = REPO_ROOT / "docs" / "REPOSITORY.md"

# Folder-level descriptions for College/ and other top-level trees.
FOLDER_DESCRIPTIONS: dict[str, str] = {
    "College/App": "Launch shell, navigation, onboarding, menu bar, and app coordinators.",
    "College/App/Toolbar": "Window-scoped toolbar providers and dispatch for each app page.",
    "College/Core": "Cross-cutting infrastructure shared across features.",
    "College/Core/Data": "SwiftData schema, persistence, repositories, and storage.",
    "College/Core/Data/Persistence": "CollegePersistence extensions and academic computation.",
    "College/Core/Data/Repositories": "Feature-facing repository CRUD and query adapters.",
    "College/Core/Data/Storage": "Model container factory, migrations, and store maintenance.",
    "College/Core/DesignSystem": "Shared UI tokens, headers, and toolbar metrics.",
    "College/Core/Location": "Location permission and picker utilities.",
    "College/Core/Notifications": "Academic notification scheduling.",
    "College/Core/Platform": "Platform helpers, commands, focus blocks, and undo/toast.",
    "College/Core/Platform/Availability": "Free/busy availability link helpers.",
    "College/Core/Platform/Commands": "App-wide command palette and menu commands.",
    "College/Core/Platform/Focus": "Focus block scheduling integration.",
    "College/Core/Platform/Integrations": "Cloud and third-party integration ports.",
    "College/Core/Platform/Intelligence": "Shared intelligence/embedding helpers.",
    "College/Core/Platform/Undo": "Undo coordinator and toast host.",
    "College/Core/Security": "App lock, privacy overview, backup, and data wipe.",
    "College/Core/Services": "Shared services (vault, catalog sync, email, PDF, etc.).",
    "College/Core/Utilities": "Shared helper utilities.",
    "College/Core/WebShortcuts": "Embedded web shortcut coordinator and favicon store.",
    "College/Core/Translation": "On-device UI translation host and policy.",
    "College/Debug": "Diagnostics center, crash reports, and DEBUG-only tooling.",
    "College/Features/Academics": "Semester planner UI, degree audit panel, GPA/credit views, and graduation timeline.",
    "College/Features/Assistant": "On-device AI assistant, tool routing, and conversation UI.",
    "College/Features/Assistant/AssistantInference": "Local LLM inference sessions and prompt builders.",
    "College/Features/Assistant/Resources": "Assistant bundled resources and model assets.",
    "College/Features/Calendar": "Calendar grid UI, editor overlays, and academic calendar helpers.",
    "College/Features/Calendar/Editor": "Scrollable calendar item editor decomposition.",
    "College/Features/Calendar/ICS": "ICS subscription parsing helpers.",
    "College/Features/Calendar/Views": "Calendar subviews and layout components.",
    "College/Features/Career": "Career workspace shell, navigation, and shared career UI.",
    "College/Features/Career/Applications": "Application tracker models and kanban/list views.",
    "College/Features/Career/Applications/Views": "Application tracker view components.",
    "College/Features/Career/Design": "Career design tokens and shared styling.",
    "College/Features/Career/Interview": "Interview prep stories and practice flows.",
    "College/Features/Career/Job Board": "Job board UI and posting presentation.",
    "College/Features/Career/Job Board Scrapers": "External job board scraper implementations.",
    "College/Features/Career/Job Board Scrapers/Greenhouse": "Greenhouse ATS scraper.",
    "College/Features/Career/Job Board Scrapers/ICIMS": "iCIMS ATS scraper.",
    "College/Features/Career/Job Board Scrapers/Lever": "Lever ATS scraper.",
    "College/Features/Career/Job Board Scrapers/Oracle": "Oracle HCM scraper.",
    "College/Features/Career/Job Board Scrapers/Talemetry": "Talemetry ATS scraper.",
    "College/Features/Career/Job Board Scrapers/Workday": "Workday ATS scraper.",
    "College/Features/Career/Job Board/Views": "Job board view components.",
    "College/Features/Career/Networking": "Networking tracker UI and detail panes.",
    "College/Features/Career/Nearby": "Nearby employers map, geocoding, and App Intents.",
    "College/Features/Career/Resumes": "Resume library, builder sheets, and autofill review.",
    "College/Features/Career/Services": "Resume parsing, ATS scoring, and career enrichment services.",
    "College/Features/Career/Stats": "Career funnel KPI views.",
    "College/Features/Career/Workspace": "Career workspace layout and sub-view routing.",
    "College/Features/Catalog": "School catalog scrape, ingest, search, and vector index.",
    "College/Features/Catalog/CatalogEmbed": "MLX sentence embedding bundle and vector search.",
    "College/Features/Catalog/CatalogParsing": "Shared catalog HTML/XML parsing utilities.",
    "College/Features/Catalog/CourseLeaf": "CourseLeaf-specific catalog discovery and parsing.",
    "College/Features/Catalog/Discovery": "Catalog platform discovery and graph building.",
    "College/Features/Catalog/Ingest": "Catalog download, scrape transactions, and import pipeline.",
    "College/Features/Catalog/ModernCampus": "Modern Campus catalog engine and IR adapters.",
    "College/Features/Catalog/PDF": "PDF catalog extraction and normalization.",
    "College/Features/Catalog/PDF/Profiles": "Per-school PDF layout profiles.",
    "College/Features/Catalog/Store": "Catalog store snapshots and security bridges.",
    "College/Features/Catalog/Vector": "Catalog vector store lifecycle and embedding spikes.",
    "College/Features/Courses": "Course detail sheets and catalog search UI.",
    "College/Features/Degree": "Degree validation, configuration, and major/minor detail views.",
    "College/Features/Documents": "Document Vault UI, grid/list layouts, and file actions.",
    "College/Features/LMS": "Embedded LMS portal, import flows, and credential storage.",
    "College/Features/Overview": "Dashboard hub, widgets, needs-attention strip, and quick actions.",
    "College/Features/Profile": "Identity, experience, achievements, and portfolio UI.",
    "College/Features/Resume": "Detached resume builder window and Typst export path.",
    "College/Features/Settings": "Preferences, catalog sync settings, and diagnostics cards.",
    "College/Features/SyllabusAI": "Syllabus PDF analysis, event extraction, and review flows.",
    "College/Features/Transfer": "Transfer equivalency lookup and degree impact scoring.",
    "CollegeShareExtension": "macOS Share Extension for saving files into the Document Vault.",
    "CollegeTests": "Unit and integration tests mirroring production feature layout.",
    "CollegeTests/App": "App shell and toolbar architecture tests.",
    "CollegeTests/Core": "Cross-cutting Core regression tests.",
    "CollegeTests/Features": "Feature-scoped unit tests.",
    "CollegeTests/Fixtures": "Catalog scrape fixtures (CourseLeaf XML, HTML, golden JSON).",
    "CollegeTests/Performance": "Launch and performance baseline acceptance tests.",
    "CollegeTests/Persistence": "Schema migration, backup, and persistence harness tests.",
    "CollegeTests/Support": "Shared test helpers and snapshot harnesses.",
    "CollegeTests/__Snapshots__": "Visual regression snapshots for toolbar tests.",
    "CollegeUITests": "UI tests for Assistant scenarios and Settings flows.",
    "Packages/CollegeAcademics": "Shared academics types, GPA formatting, and graduation timeline engine.",
    "Packages/CollegeCalendar": "Calendar UI package with Google/Apple/Outlook sync adapters.",
    "Packages/CollegeCareer": "Shared career navigation types and job posting enrichment.",
    "Packages/CollegePlatformBoundary": "Feature module registry and import boundary enforcement.",
    "VecturaService": "Isolated MLX sentence embedding service (768-d) for catalog vector search.",
    "scripts": "Build gates, catalog parity tools, test runners, and repo maintenance scripts.",
    ".github/workflows": "GitHub Actions CI workflows for PR gates, catalog tests, and release hardening.",
    "docs": "Architecture docs, ADRs, sign-off checklists, and performance baselines.",
    "docs/assets/readme": "Screenshot and icon assets referenced by the GitHub README.",
    "docs/adr": "Architecture Decision Records for major design choices.",
    "docs/archive": "Superseded migration notes and audit artifacts.",
    "docs/pdf-baselines": "PDF catalog ingest baseline corpora for regression comparison.",
}

ROOT_FILE_DESCRIPTIONS: dict[str, str] = {
    ".gitignore": "Git ignore rules for build artifacts, secrets, and local editor state.",
    ".gitleaks.toml": "Secret scanning configuration for CI and local gitleaks runs.",
    "Config.xcconfig": "Xcode build configuration; includes Secrets.xcconfig for local keys.",
    "Secrets.xcconfig.example": "Template for local-only API keys and OAuth client IDs.",
    "Inspection": "SwiftLint/static analysis configuration or inspection profile.",
    "LICENSE": "MIT license for project source code.",
    "README.md": "Product landing page and link hub for the repository.",
    "toolbar-health-report.json": "Generated toolbar architecture health report artifact.",
}

DOC_FILE_DESCRIPTIONS: dict[str, str] = {
    "docs/DEVELOPMENT.md": "Clone, build, test tiers, and contributor setup guide.",
    "docs/REPOSITORY.md": "Tiered inventory of every tracked file and its purpose.",
    "docs/ARCHITECTURE.md": "Module layout, data flow, and feature-first tree map.",
    "docs/assets/readme/README.md": "Documents expected screenshot assets for the GitHub README.",
}

README_ASSET_DESCRIPTIONS: dict[str, str] = {
    "docs/assets/readme/app-icon.png": "GitHub README hero icon (512×512 graduation cap).",
    "docs/assets/readme/hero-overview.png": "GitHub README screenshot — Overview dashboard.",
    "docs/assets/readme/feature-sidebar.png": "GitHub README screenshot — sidebar navigation.",
    "docs/assets/readme/feature-academics.png": "GitHub README screenshot — Academics planner and audit.",
    "docs/assets/readme/feature-transfer.png": "GitHub README screenshot — Transfer Database.",
    "docs/assets/readme/feature-calendar.png": "GitHub README screenshot — Calendar month view.",
    "docs/assets/readme/feature-career.png": "GitHub README screenshot — Career application board.",
    "docs/assets/readme/feature-documents.png": "GitHub README screenshot — Documents Repository.",
    "docs/assets/readme/feature-profile.png": "GitHub README screenshot — Profile page.",
    "docs/assets/readme/feature-settings.png": "GitHub README screenshot — Settings and privacy.",
}

WORKFLOW_DESCRIPTIONS: dict[str, str] = {
    "catalog-tests.yml": "Runs catalog ingest and parser test suite on PRs.",
    "feature-boundaries.yml": "Enforces feature module import boundaries.",
    "release-hardening.yml": "Release build hardening and sign-off gates.",
    "secret-scan.yml": "Scans commits for leaked secrets via gitleaks.",
    "toolbar-architecture.yml": "Validates toolbar provider registry architecture.",
    "toolbar-health-check.yml": "Runs toolbar health check script and reports drift.",
    "app-ship-gates.yml": "PR ship gates — unit tests and blocking pattern checks.",
    "snow-leopard-nightly.yml": "Nightly performance and health metrics CI run.",
    "release-notarization.yml": "macOS release notarization workflow.",
}

SCRIPT_DESCRIPTIONS: dict[str, str] = {
    "add-swift-file-headers.py": "Adds standard file header comments to Swift sources.",
    "catalog_ingest_parity_diff.swift": "Diffs catalog ingest outputs for parity regression.",
    "check-feature-imports.sh": "Verifies feature modules do not import across boundaries.",
    "check-neutral-persistence-labels.sh": "Enforces technology-neutral persistence naming.",
    "check-no-coredata.sh": "Guards against Core Data usage in SwiftData codebase.",
    "check-no-gemma4.sh": "Guards against disallowed Gemma 4 model references.",
    "check-no-vision-llm.sh": "Guards against Vision LLM dependencies.",
    "check-platform-boundary.sh": "Validates CollegePlatformBoundary import rules.",
    "compare_catalog_exports.py": "Compares catalog export bundles for structural diffs.",
    "fix_container_aliases.py": "Migration helper for AppContainer DI alias cleanup.",
    "generate-repository-index.py": "Generates and validates docs/REPOSITORY.md from git ls-files.",
    "migrate_app_container_di.py": "Migration script for AppContainer dependency injection.",
    "record_toolbar_snapshots.sh": "Records toolbar visual regression snapshots.",
    "refresh-performance-manifest.py": "Regenerates performance file manifest from codebase.",
    "refresh-performance-manifest.sh": "Shell wrapper for performance manifest refresh.",
    "reorg-college-tests.py": "Mechanical test file reorg helper.",
    "run-college-unit-tests.sh": "Runs College unit test shard locally or in CI.",
    "run-performance-gates.sh": "Runs launch and performance acceptance gates.",
    "run_catalog_tests.sh": "Runs catalog-specific test suite.",
    "run_toolbar_tests.sh": "Runs toolbar architecture and visual tests.",
    "slim-xcode-project-for-github.py": "Strips local-only references from Xcode project for git.",
    "test_compare_catalog_exports.py": "Unit tests for catalog export comparison script.",
    "test_dsu_catalog_scraper.py": "Tests Dakota State University catalog scraper fixtures.",
    "toolbar-health-check.sh": "Checks toolbar provider health and writes report JSON.",
    "train_intent_text_classifier.swift": "Trains Assistant intent text classifier model.",
    "validate_courseleaf_requirements.sh": "Validates CourseLeaf requirement parser output.",
}

LOCAL_ONLY_PATHS: list[tuple[str, str]] = [
    ("College.xcodeproj", "Xcode project (tracked for CI; may be absent in sparse checkouts)."),
    ("rust-typst/", "Optional Rust/Typst resume PDF bridge (local build artifacts in target/ are gitignored)."),
    ("Secrets.xcconfig", "Local-only secrets file — never commit."),
    (".build/", "Swift Package Manager build output."),
    ("DerivedData/", "Xcode derived data."),
]


# Files added by the README/docs work that may not yet be `git add`ed.
ALWAYS_INCLUDE = [
    "LICENSE",
    "docs/DEVELOPMENT.md",
    "docs/REPOSITORY.md",
    "docs/assets/readme/README.md",
    "scripts/generate-repository-index.py",
]


def git_tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files"],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def all_documented_paths() -> list[str]:
    paths = set(git_tracked_files())
    for rel in ALWAYS_INCLUDE:
        if (REPO_ROOT / rel).exists():
            paths.add(rel)
    assets_dir = REPO_ROOT / "docs" / "assets" / "readme"
    if assets_dir.is_dir():
        for item in assets_dir.iterdir():
            if item.is_file():
                paths.add(str(item.relative_to(REPO_ROOT)))
    return sorted(paths)


def extract_swift_purpose(path: Path) -> str | None:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[:12]
    except OSError:
        return None
    for line in lines:
        match = re.match(r"^//\s*Purpose:\s*(.+)$", line.strip())
        if match:
            return match.group(1).strip()
    return None


def infer_purpose(rel_path: str) -> str:
    path = REPO_ROOT / rel_path
    name = Path(rel_path).name

    if rel_path in ROOT_FILE_DESCRIPTIONS:
        return ROOT_FILE_DESCRIPTIONS[rel_path]

    if rel_path in DOC_FILE_DESCRIPTIONS:
        return DOC_FILE_DESCRIPTIONS[rel_path]

    if rel_path in README_ASSET_DESCRIPTIONS:
        return README_ASSET_DESCRIPTIONS[rel_path]

    if rel_path.startswith(".github/workflows/"):
        wf = Path(rel_path).name
        return WORKFLOW_DESCRIPTIONS.get(wf, "GitHub Actions CI workflow.")

    if rel_path.startswith("scripts/"):
        return SCRIPT_DESCRIPTIONS.get(name, "Repository maintenance or CI helper script.")

    if rel_path.endswith(".swift"):
        purpose = extract_swift_purpose(path)
        if purpose:
            return purpose
        if name.endswith("Tests.swift"):
            return f"Unit tests for {name.removesuffix('Tests.swift')}."
        return f"Swift source — {name.removesuffix('.swift')}."

    if rel_path.endswith("Package.swift"):
        return "Swift Package Manager manifest."

    if rel_path.endswith(".md"):
        return "Documentation."

    if rel_path.endswith((".xml", ".html", ".json", ".pdf", ".tsv", ".txt", ".csv", ".png")):
        return "Test fixture or documentation artifact."

    if rel_path.endswith((".yml", ".yaml")):
        return "Configuration or CI workflow."

    if rel_path.endswith((".plist", ".entitlements")):
        return "App or extension bundle configuration."

    if rel_path.endswith(".xcstrings"):
        return "Localized string catalog."

    return "Repository file."


def folder_description(folder: str) -> str:
    if folder in FOLDER_DESCRIPTIONS:
        return FOLDER_DESCRIPTIONS[folder]
    parts = folder.split("/")
    if len(parts) >= 2:
        parent = "/".join(parts[:-1])
        if parent in FOLDER_DESCRIPTIONS:
            return f"{FOLDER_DESCRIPTIONS[parent]} (continued)"
    return "Project files for this directory."


def parse_documented_paths(content: str) -> set[str]:
    documented: set[str] = set()
    section = content.split("## Local-only / not tracked (reference)")[0]
    for line in section.splitlines():
        match = re.match(r"^\| `([^`]+)` \|", line)
        if match:
            documented.add(match.group(1))
    return documented


def render_markdown(tracked: list[str]) -> str:
    by_folder: dict[str, list[str]] = defaultdict(list)
    root_files: list[str] = []

    for rel in sorted(tracked):
        if rel == "docs/REPOSITORY.md":
            continue
        if "/" not in rel:
            root_files.append(rel)
        else:
            folder = rel.rsplit("/", 1)[0]
            by_folder[folder].append(rel)

    lines: list[str] = [
        "# Repository guide",
        "",
        "> Every path tracked in git is listed here with its purpose.",
        "> Regenerate: `python3 scripts/generate-repository-index.py --write`",
        "",
        "For module-level architecture, see [ARCHITECTURE.md](ARCHITECTURE.md).",
        "",
        "---",
        "",
        "## Root files",
        "",
        "| File | Purpose |",
        "|------|---------|",
    ]

    for rel in sorted(root_files):
        lines.append(f"| `{rel}` | {infer_purpose(rel)} |")

    # Top-level sections in stable order
    section_roots = [
        "College",
        "CollegeShareExtension",
        "CollegeTests",
        "CollegeUITests",
        "Packages",
        "VecturaService",
        "scripts",
        ".github",
        "docs",
    ]

    emitted_folders: set[str] = set()

    def emit_folder(folder: str) -> None:
        if folder in emitted_folders:
            return
        emitted_folders.add(folder)
        files = by_folder.get(folder, [])
        if not files:
            return
        lines.extend(["", f"### `{folder}/`", "", folder_description(folder), "", "| File | Purpose |", "|------|---------|"])
        for rel in sorted(files):
            filename = Path(rel).name
            lines.append(f"| `{rel}` | {infer_purpose(rel)} |")

    for root in section_roots:
        matching = [f for f in by_folder if f == root or f.startswith(root + "/")]
        if not matching and root != "College":
            continue
        lines.extend(["", f"## {root}", ""])
        if root == "College":
            lines.append("Main macOS app target — SwiftUI views, persistence, and feature modules.")
        elif root == "Packages":
            lines.append("Extracted Swift packages shared across the app and tests.")
        elif root == ".github":
            lines.append("GitHub Actions CI configuration.")
        for folder in sorted(matching):
            emit_folder(folder)

    # Any remaining folders not covered
    remaining = sorted(set(by_folder) - emitted_folders)
    if remaining:
        lines.extend(["", "## Other tracked paths", ""])
        for folder in remaining:
            emit_folder(folder)

    lines.extend(["", "---", "", "## Local-only / not tracked (reference)", ""])
    lines.append("| Path | Notes |")
    lines.append("|------|-------|")
    for path, note in LOCAL_ONLY_PATHS:
        lines.append(f"| `{path}` | {note} |")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Write docs/REPOSITORY.md")
    parser.add_argument("--check", action="store_true", help="Verify REPOSITORY.md covers tracked git paths plus ALWAYS_INCLUDE")
    args = parser.parse_args()

    if not args.write and not args.check:
        parser.error("Specify --write or --check")

    tracked = all_documented_paths()
    if args.write:
        content = render_markdown(tracked)
        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_PATH.write_text(content, encoding="utf-8")
        print(f"Wrote {OUTPUT_PATH} ({len(tracked)} paths)")

    if args.check:
        if not OUTPUT_PATH.exists():
            print(f"Missing {OUTPUT_PATH}; run with --write first.", file=sys.stderr)
            return 1
        content = OUTPUT_PATH.read_text(encoding="utf-8")
        documented = parse_documented_paths(content)
        tracked_set = set(tracked) - {"docs/REPOSITORY.md"}
        missing = sorted(tracked_set - documented)
        extra = sorted(documented - tracked_set)
        if missing:
            print(f"Missing from REPOSITORY.md ({len(missing)}):", file=sys.stderr)
            for path in missing[:20]:
                print(f"  - {path}", file=sys.stderr)
            if len(missing) > 20:
                print(f"  ... and {len(missing) - 20} more", file=sys.stderr)
            return 1
        if extra:
            print(f"Warning: {len(extra)} documented paths not in index (stale entries).", file=sys.stderr)
        print(f"OK — {len(tracked_set)} paths documented.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
