#!/usr/bin/env python3
"""Compare baseline vs candidate ModernCampus catalog export CSV files.

This script is intentionally dependency-free and tailored to the export schema used by
College/CoreData/CoreDataManager.swift.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, UTC
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse


def _clean(value: str | None) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", value.replace("\u00a0", " ")).strip()


def _normalize_text(value: str | None) -> str:
    return _clean(value).lower()


def normalize_program_url(url: str) -> str:
    url = _clean(url)
    if not url:
        return ""
    parsed = urlparse(url)
    query = parse_qs(parsed.query, keep_blank_values=True)

    # Keep only keys that define program identity for comparisons.
    keys = ["poid", "catoid"]
    canon: dict[str, str] = {}
    for key in keys:
        vals = query.get(key)
        if vals and vals[0].strip():
            canon[key] = vals[0].strip()

    query_str = urlencode(canon)
    path = parsed.path or "/preview_program.php"
    scheme = parsed.scheme or "https"
    netloc = parsed.netloc or "catalogs.buffalo.edu"
    return f"{scheme}://{netloc}{path}?{query_str}" if query_str else f"{scheme}://{netloc}{path}"


def _to_float(value: str) -> float | None:
    value = _clean(value)
    if not value:
        return None
    m = re.search(r"\d+(?:\.\d+)?", value)
    if not m:
        return None
    try:
        return float(m.group(0))
    except ValueError:
        return None


@dataclass
class ProgramStats:
    url: str
    catoid: str
    degree_name: str
    catalog_rows: int = 0
    rows_with_category: int = 0
    rows_with_code: int = 0
    rows_complete: int = 0
    rows_missing_title: int = 0
    rows_missing_credits: int = 0
    rows_missing_description: int = 0
    requirement_missing_issue: int = 0

    def to_dict(self) -> dict[str, Any]:
        code_quality = self.rows_complete / self.rows_with_code if self.rows_with_code else 0.0
        return {
            "url": self.url,
            "catoid": self.catoid,
            "degreeName": self.degree_name,
            "catalogRows": self.catalog_rows,
            "rowsWithCategory": self.rows_with_category,
            "rowsWithCode": self.rows_with_code,
            "rowsComplete": self.rows_complete,
            "rowsMissingTitle": self.rows_missing_title,
            "rowsMissingCredits": self.rows_missing_credits,
            "rowsMissingDescription": self.rows_missing_description,
            "requirementMissingIssue": self.requirement_missing_issue,
            "codeQuality": round(code_quality, 6),
            "classification": classify_program(self),
            "pass": is_program_pass(self),
        }


def classify_program(stats: ProgramStats) -> str:
    if stats.requirement_missing_issue > 0 or stats.rows_with_code == 0:
        return "marker_only"

    quality = stats.rows_complete / stats.rows_with_code if stats.rows_with_code else 0.0
    if quality >= 0.99 and stats.rows_missing_title == 0 and stats.rows_missing_credits == 0:
        return "complete_parse"
    return "partial_parse"


def is_program_pass(stats: ProgramStats) -> bool:
    return classify_program(stats) == "complete_parse"


class ExportSnapshot:
    def __init__(self, csv_path: Path):
        self.csv_path = csv_path
        self.catalog_rows = 0
        self.audit_rows = 0
        self.programs: dict[str, ProgramStats] = {}
        self.audit_issue_counts: Counter[str] = Counter()
        self.catalog_by_catoid: Counter[str] = Counter()
        self.programs_by_catoid: defaultdict[str, set[str]] = defaultdict(set)
        self.pass_by_catoid: Counter[str] = Counter()
        self.classification_by_catoid: defaultdict[str, Counter[str]] = defaultdict(Counter)

        self._parse()
        self._post_compute()

    def _program_key(self, row: dict[str, str]) -> tuple[str, str, str]:
        url = normalize_program_url(row.get("Program URL", ""))
        catoid = _clean(row.get("Source Catoid", ""))
        degree_name = _clean(row.get("Degree Name", ""))
        return (url, catoid, degree_name)

    def _parse(self) -> None:
        with self.csv_path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                section = _normalize_text(row.get("Section"))
                url, catoid, degree_name = self._program_key(row)

                if section == "catalog":
                    self.catalog_rows += 1
                    self.catalog_by_catoid[catoid] += 1

                    if url:
                        if url not in self.programs:
                            self.programs[url] = ProgramStats(url=url, catoid=catoid, degree_name=degree_name)
                        p = self.programs[url]
                        p.catalog_rows += 1

                        category = _clean(row.get("Requirement Category", ""))
                        code = _clean(row.get("Course Code", ""))
                        title = _clean(row.get("Course Title", ""))
                        description = _clean(row.get("Course Description", ""))
                        credits = _clean(row.get("Credits", ""))

                        if category:
                            p.rows_with_category += 1
                        if code:
                            p.rows_with_code += 1
                            if title and description and credits:
                                p.rows_complete += 1
                            if not title:
                                p.rows_missing_title += 1
                            if not credits:
                                p.rows_missing_credits += 1
                            if not description:
                                p.rows_missing_description += 1

                elif section == "audit":
                    self.audit_rows += 1
                    issue = _clean(row.get("Issue", "")) or "(empty issue)"
                    self.audit_issue_counts[issue] += 1

                    # Program-level missing requirement marker.
                    if "program saved to database but no requirements found" in _normalize_text(issue):
                        if url:
                            if url not in self.programs:
                                self.programs[url] = ProgramStats(url=url, catoid=catoid, degree_name=degree_name)
                            self.programs[url].requirement_missing_issue += 1

    def _post_compute(self) -> None:
        for url, p in self.programs.items():
            catoid = p.catoid
            self.programs_by_catoid[catoid].add(url)
            cls = classify_program(p)
            self.classification_by_catoid[catoid][cls] += 1
            if is_program_pass(p):
                self.pass_by_catoid[catoid] += 1

    def to_summary(self) -> dict[str, Any]:
        total_programs = len(self.programs)
        pass_programs = sum(1 for p in self.programs.values() if is_program_pass(p))
        total_code_rows = sum(p.rows_with_code for p in self.programs.values())
        total_complete_rows = sum(p.rows_complete for p in self.programs.values())

        return {
            "csvPath": str(self.csv_path),
            "catalogRows": self.catalog_rows,
            "auditRows": self.audit_rows,
            "programCount": total_programs,
            "programPassCount": pass_programs,
            "programPassRate": _ratio(pass_programs, total_programs),
            "codedRowCount": total_code_rows,
            "codedRowCompleteCount": total_complete_rows,
            "codedRowCompleteness": _ratio(total_complete_rows, total_code_rows),
            "byCatoid": self._catoid_summary(),
            "topAuditIssues": self.audit_issue_counts.most_common(20),
        }

    def _catoid_summary(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        all_ids = set(self.programs_by_catoid.keys()) | set(self.catalog_by_catoid.keys())
        for catoid in sorted(all_ids, key=lambda x: (x == "", x)):
            program_count = len(self.programs_by_catoid.get(catoid, set()))
            pass_count = self.pass_by_catoid.get(catoid, 0)
            result[catoid] = {
                "programCount": program_count,
                "programPassCount": pass_count,
                "programPassRate": _ratio(pass_count, program_count),
                "catalogRows": self.catalog_by_catoid.get(catoid, 0),
                "classifications": dict(self.classification_by_catoid.get(catoid, Counter())),
            }
        return result


def _ratio(num: int, den: int) -> float:
    return round((num / den), 6) if den else 0.0


def _delta(baseline: float, candidate: float) -> float:
    return round(candidate - baseline, 6)


def compare_snapshots(baseline: ExportSnapshot, candidate: ExportSnapshot, gate_rate: float) -> dict[str, Any]:
    base_summary = baseline.to_summary()
    cand_summary = candidate.to_summary()

    base_programs = baseline.programs
    cand_programs = candidate.programs
    all_program_urls = set(base_programs.keys()) | set(cand_programs.keys())

    program_changes: list[dict[str, Any]] = []
    regressed_programs: list[dict[str, Any]] = []
    improved_programs: list[dict[str, Any]] = []

    for url in sorted(all_program_urls):
        b = base_programs.get(url)
        c = cand_programs.get(url)
        if b is None:
            change = {
                "url": url,
                "catoid": c.catoid,
                "degreeName": c.degree_name,
                "status": "added",
                "candidateClassification": classify_program(c),
                "candidatePass": is_program_pass(c),
            }
            program_changes.append(change)
            continue
        if c is None:
            change = {
                "url": url,
                "catoid": b.catoid,
                "degreeName": b.degree_name,
                "status": "removed",
                "baselineClassification": classify_program(b),
                "baselinePass": is_program_pass(b),
            }
            program_changes.append(change)
            continue

        bpass = is_program_pass(b)
        cpass = is_program_pass(c)
        bqual = b.rows_complete / b.rows_with_code if b.rows_with_code else 0.0
        cqual = c.rows_complete / c.rows_with_code if c.rows_with_code else 0.0
        changed = (
            classify_program(b) != classify_program(c)
            or bpass != cpass
            or not math.isclose(bqual, cqual, rel_tol=0, abs_tol=1e-9)
            or b.rows_missing_title != c.rows_missing_title
            or b.rows_missing_credits != c.rows_missing_credits
            or b.rows_missing_description != c.rows_missing_description
            or b.requirement_missing_issue != c.requirement_missing_issue
        )
        if not changed:
            continue

        change = {
            "url": url,
            "catoid": c.catoid or b.catoid,
            "degreeName": c.degree_name or b.degree_name,
            "status": "changed",
            "baselineClassification": classify_program(b),
            "candidateClassification": classify_program(c),
            "baselinePass": bpass,
            "candidatePass": cpass,
            "baselineCodeQuality": round(bqual, 6),
            "candidateCodeQuality": round(cqual, 6),
            "deltaCodeQuality": round(cqual - bqual, 6),
            "baselineMissingTitle": b.rows_missing_title,
            "candidateMissingTitle": c.rows_missing_title,
            "baselineMissingCredits": b.rows_missing_credits,
            "candidateMissingCredits": c.rows_missing_credits,
            "baselineMissingDescription": b.rows_missing_description,
            "candidateMissingDescription": c.rows_missing_description,
            "baselineRequirementMissingIssue": b.requirement_missing_issue,
            "candidateRequirementMissingIssue": c.requirement_missing_issue,
        }
        program_changes.append(change)

        if bpass and not cpass:
            regressed_programs.append(change)
        elif (not bpass and cpass) or change["deltaCodeQuality"] > 0:
            improved_programs.append(change)

    # Audit issue deltas.
    issue_deltas: list[dict[str, Any]] = []
    all_issues = set(baseline.audit_issue_counts.keys()) | set(candidate.audit_issue_counts.keys())
    for issue in sorted(all_issues):
        bcount = baseline.audit_issue_counts.get(issue, 0)
        ccount = candidate.audit_issue_counts.get(issue, 0)
        if bcount == ccount:
            continue
        issue_deltas.append({
            "issue": issue,
            "baseline": bcount,
            "candidate": ccount,
            "delta": ccount - bcount,
        })

    catoid_metrics = _compare_catoids(base_summary.get("byCatoid", {}), cand_summary.get("byCatoid", {}), gate_rate)

    result = {
        "generatedAt": datetime.now(UTC).isoformat(),
        "inputs": {
            "baselineCsv": str(baseline.csv_path),
            "candidateCsv": str(candidate.csv_path),
        },
        "gate": {
            "requiredProgramPassRate": gate_rate,
            "globalPass": cand_summary.get("programPassRate", 0.0) >= gate_rate,
            "perCatoid": catoid_metrics,
        },
        "baseline": base_summary,
        "candidate": cand_summary,
        "deltas": {
            "programPassRate": _delta(base_summary["programPassRate"], cand_summary["programPassRate"]),
            "codedRowCompleteness": _delta(base_summary["codedRowCompleteness"], cand_summary["codedRowCompleteness"]),
            "catalogRows": cand_summary["catalogRows"] - base_summary["catalogRows"],
            "auditRows": cand_summary["auditRows"] - base_summary["auditRows"],
        },
        "programChanges": {
            "count": len(program_changes),
            "improvedCount": len(improved_programs),
            "regressedCount": len(regressed_programs),
            "regressed": regressed_programs[:200],
            "improved": improved_programs[:200],
            "sample": program_changes[:400],
        },
        "auditIssueDeltas": issue_deltas[:300],
    }
    return result


def _compare_catoids(base: dict[str, Any], cand: dict[str, Any], gate_rate: float) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    ids = sorted(set(base.keys()) | set(cand.keys()), key=lambda x: (x == "", x))
    for cid in ids:
        b = base.get(cid, {})
        c = cand.get(cid, {})
        b_rate = float(b.get("programPassRate", 0.0))
        c_rate = float(c.get("programPassRate", 0.0))
        out.append(
            {
                "catoid": cid,
                "baselineProgramCount": int(b.get("programCount", 0)),
                "candidateProgramCount": int(c.get("programCount", 0)),
                "baselinePassRate": b_rate,
                "candidatePassRate": c_rate,
                "deltaPassRate": round(c_rate - b_rate, 6),
                "candidatePassesGate": c_rate >= gate_rate,
                "baselineClassifications": b.get("classifications", {}),
                "candidateClassifications": c.get("classifications", {}),
            }
        )
    return out


def write_markdown(report: dict[str, Any], output_path: Path) -> None:
    b = report["baseline"]
    c = report["candidate"]
    d = report["deltas"]
    gate = report["gate"]

    lines: list[str] = []
    lines.append("# Catalog Accuracy Comparison")
    lines.append("")
    lines.append(f"Generated: {report['generatedAt']}")
    lines.append("")
    lines.append("## Inputs")
    lines.append("")
    lines.append(f"- Baseline CSV: {report['inputs']['baselineCsv']}")
    lines.append(f"- Candidate CSV: {report['inputs']['candidateCsv']}")
    lines.append("")
    lines.append("## Global Metrics")
    lines.append("")
    lines.append("| Metric | Baseline | Candidate | Delta |")
    lines.append("|---|---:|---:|---:|")
    lines.append(f"| Program pass rate | {b['programPassRate']:.4f} | {c['programPassRate']:.4f} | {d['programPassRate']:+.4f} |")
    lines.append(f"| Coded-row completeness | {b['codedRowCompleteness']:.4f} | {c['codedRowCompleteness']:.4f} | {d['codedRowCompleteness']:+.4f} |")
    lines.append(f"| Catalog rows | {b['catalogRows']} | {c['catalogRows']} | {d['catalogRows']:+d} |")
    lines.append(f"| Audit rows | {b['auditRows']} | {c['auditRows']} | {d['auditRows']:+d} |")
    lines.append("")
    lines.append("## Gate Status")
    lines.append("")
    lines.append(f"- Required program pass rate: {gate['requiredProgramPassRate']:.4f}")
    lines.append(f"- Global pass: {'PASS' if gate['globalPass'] else 'FAIL'}")
    lines.append("")
    lines.append("### Per Catoid")
    lines.append("")
    lines.append("| Catoid | Baseline Programs | Candidate Programs | Baseline Pass | Candidate Pass | Delta | Gate |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    for item in gate["perCatoid"]:
        lines.append(
            f"| {item['catoid'] or '(empty)'} | {item['baselineProgramCount']} | {item['candidateProgramCount']} | "
            f"{item['baselinePassRate']:.4f} | {item['candidatePassRate']:.4f} | {item['deltaPassRate']:+.4f} | "
            f"{'PASS' if item['candidatePassesGate'] else 'FAIL'} |"
        )

    lines.append("")
    lines.append("## Program Changes")
    lines.append("")
    lines.append(f"- Changed programs: {report['programChanges']['count']}")
    lines.append(f"- Improved programs: {report['programChanges']['improvedCount']}")
    lines.append(f"- Regressed programs: {report['programChanges']['regressedCount']}")

    if report["programChanges"]["regressed"]:
        lines.append("")
        lines.append("### Regressions")
        lines.append("")
        lines.append("| Catoid | Degree | URL | Baseline | Candidate | Δ Code Quality |")
        lines.append("|---|---|---|---|---|---:|")
        for item in report["programChanges"]["regressed"][:80]:
            lines.append(
                f"| {item.get('catoid','')} | {item.get('degreeName','')} | {item.get('url','')} | "
                f"{item.get('baselineClassification','')} | {item.get('candidateClassification','')} | "
                f"{item.get('deltaCodeQuality', 0.0):+.4f} |"
            )

    lines.append("")
    lines.append("## Audit Issue Deltas (Top 50)")
    lines.append("")
    lines.append("| Issue | Baseline | Candidate | Delta |")
    lines.append("|---|---:|---:|---:|")
    for item in report["auditIssueDeltas"][:50]:
        lines.append(f"| {item['issue']} | {item['baseline']} | {item['candidate']} | {item['delta']:+d} |")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare baseline and candidate catalog export CSVs.")
    parser.add_argument("--baseline-csv", required=True, help="Path to baseline export CSV.")
    parser.add_argument("--candidate-csv", required=True, help="Path to candidate export CSV.")
    parser.add_argument("--out-report-md", required=True, help="Path to output markdown report.")
    parser.add_argument("--out-report-json", required=True, help="Path to output JSON report.")
    parser.add_argument(
        "--gate-pass-rate",
        type=float,
        default=0.99,
        help="Required minimum program pass rate for gate checks (default: 0.99).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    baseline_csv = Path(args.baseline_csv)
    candidate_csv = Path(args.candidate_csv)
    out_md = Path(args.out_report_md)
    out_json = Path(args.out_report_json)

    baseline = ExportSnapshot(baseline_csv)
    candidate = ExportSnapshot(candidate_csv)
    report = compare_snapshots(baseline, candidate, gate_rate=args.gate_pass_rate)

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_json.parent.mkdir(parents=True, exist_ok=True)

    write_markdown(report, out_md)
    out_json.write_text(json.dumps(report, indent=2), encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
