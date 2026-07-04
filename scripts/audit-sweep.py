#!/usr/bin/env python3
"""Generate/update docs/audit-manifest.tsv and sweep Swift files for audit patterns."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "docs" / "audit-manifest.tsv"
OLD_MANIFEST = ROOT / "docs" / "performance-file-manifest-index.tsv"

PATTERNS = {
    "main_actor": re.compile(r"@MainActor|MainActor\.run"),
    "gcd": re.compile(r"DispatchQueue\.(global|main)"),
    "task": re.compile(r"Task\s*\{|Task\.detached|withTaskGroup"),
    "json_io": re.compile(r"JSONDecoder|JSONSerialization|Data\(contentsOf:"),
    "swiftdata": re.compile(r"ModelMergeCoalescer|flushNow|bumpCareerRevision|ModelContext|FetchDescriptor"),
    "memory": re.compile(r"\.sink\(|AnyCancellable|\[weak self\]|WKWebView|nonisolated\(unsafe\)"),
    "disabled": re.compile(r"#if\s+false|#if\s+0"),
}

def module_for(path: str) -> str:
    p = path.replace("\\", "/")
    if p.startswith("CollegeTests/"):
        return "Tests"
    if p.startswith("CollegeUITests/"):
        return "UITests"
    if p.startswith("CollegeShareExtension/"):
        return "ShareExtension"
    if p.startswith("VecturaService/"):
        return "VecturaService"
    if p.startswith("Packages/"):
        parts = p.split("/")
        return parts[1] if len(parts) > 1 else "Packages"
    if p.startswith("College/Features/"):
        parts = p.split("/")
        return parts[2] if len(parts) > 2 else "Features"
    if p.startswith("College/App/"):
        return "App"
    if p.startswith("College/Core/Data/"):
        return "Core/Data"
    if p.startswith("College/Core/"):
        parts = p.split("/")
        return "/".join(parts[1:3]) if len(parts) > 2 else "Core"
    if p.startswith("College/Debug/"):
        return "Debug"
    return "College"

def load_old_risk() -> dict[str, str]:
    risks: dict[str, str] = {}
    if not OLD_MANIFEST.exists():
        return risks
    for line in OLD_MANIFEST.read_text().splitlines()[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) >= 5:
            path = parts[0].replace("//", "/")
            risks[path] = parts[4]
    return risks

def sweep_file(path: Path) -> dict:
    rel = str(path.relative_to(ROOT)).replace("\\", "/")
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {"path": rel, "lines": 0, "error": "unreadable"}

    lines = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
    hits = {k: len(p.findall(text)) for k, p in PATTERNS.items()}
    hit_count = sum(1 for v in hits.values() if v > 0)
    risk_score = hit_count + (1 if hits["main_actor"] and hits["json_io"] else 0)
    risk_score += (2 if hits["main_actor"] and hits["swiftdata"] else 0)
    risk_score += (1 if hits["main_actor"] and hits["task"] else 0)

    is_test = rel.startswith("CollegeTests/") or rel.startswith("CollegeUITests/")

    if hit_count == 0 and lines < 80:
        status = "swept"
        concurrency = "none"
        memory = "none"
    elif is_test:
        status = "swept"
        concurrency = "none" if not hits["main_actor"] else "minor"
        memory = "none"
    elif risk_score >= 4 or (hits["main_actor"] and hits["swiftdata"]):
        status = "deep_read"
        concurrency = "stall" if hits["main_actor"] and hits["json_io"] else ("stall" if hits["swiftdata"] else "minor")
        memory = "medium" if hits["memory"] else "none"
    elif risk_score >= 2:
        status = "deep_read"
        concurrency = "minor"
        memory = "minor" if hits["memory"] else "none"
    else:
        status = "swept"
        concurrency = "none"
        memory = "none"

    notes = "clean"
    note_parts = []
    if hits["main_actor"] and hits["json_io"]:
        note_parts.append("main+JSON")
    if hits["main_actor"] and hits["swiftdata"]:
        note_parts.append("main+SwiftData")
    if hits["gcd"]:
        note_parts.append("GCD")
    if hits["disabled"]:
        note_parts.append("#if-false")
    if note_parts:
        notes = ";".join(note_parts)

    return {
        "path": rel,
        "lines": lines,
        "module": module_for(rel),
        "audit_status": status,
        "concurrency": concurrency,
        "memory": memory,
        "dead_code": "n/a_test" if is_test else "live",
        "notes": notes,
        "risk_score": risk_score,
        "hits": hits,
    }

def find_swift_files() -> list[Path]:
    skip = {".build", "DerivedData", ".git"}
    files = []
    for base in ["College", "CollegeTests", "CollegeUITests", "Packages", "VecturaService", "CollegeShareExtension"]:
        root = ROOT / base
        if not root.exists():
            continue
        for p in root.rglob("*.swift"):
            if any(s in p.parts for s in skip):
                continue
            files.append(p)
    return sorted(files, key=lambda p: str(p))

def main():
    files = find_swift_files()
    old_risk = load_old_risk()
    rows = []
    for p in files:
        r = sweep_file(p)
        rel = r["path"]
        if rel in old_risk and old_risk[rel] == "Y" and r["audit_status"] == "swept":
            r["audit_status"] = "deep_read"
            if r["concurrency"] == "none":
                r["concurrency"] = "minor"
        rows.append(r)

    header = "path\tlines\tmodule\taudit_status\tconcurrency\tmemory\tdead_code\tnotes"
    lines_out = [header]
    for r in rows:
        lines_out.append(
            f"{r['path']}\t{r['lines']}\t{r['module']}\t{r['audit_status']}\t{r['concurrency']}\t{r['memory']}\t{r['dead_code']}\t{r['notes']}"
        )
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text("\n".join(lines_out) + "\n")

    total = len(rows)
    swept = sum(1 for r in rows if r["audit_status"] == "swept")
    deep = sum(1 for r in rows if r["audit_status"] == "deep_read")
    blocking = sum(1 for r in rows if r["concurrency"] == "blocking")
    stall = sum(1 for r in rows if r["concurrency"] == "stall")

    print(f"Wrote {MANIFEST}")
    print(f"Total: {total} | swept: {swept} | deep_read: {deep} | stall: {stall} | blocking: {blocking}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
