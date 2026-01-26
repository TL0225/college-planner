#!/usr/bin/env python3
"""Resolve 'AUDIT' issues in a UB scraped catalog export.

Input: a CSV export produced by the app (CoreDataManager.exportScrapedCatalogCSVFromCoreData)

This script does two practical things:
1) Fills missing course fields (title/credits/description) in CATALOG rows using other
   rows in the same export as a lookup (course-code keyed).
2) Improves ownership/department labeling when the export only has generic placeholders
   (e.g. 'Department/Program', 'Academic Programs', 'Professional Programs') by
   building a programURL -> (dept, college) map from UB directory pages.

It also produces a short markdown report summarizing remaining issues.

Note: Programs flagged as "no requirements found" cannot be fully repaired from a CSV
alone (that requires re-running the Swift scraper + persisting). Here we optionally
probe the program pages to see whether requirements appear to exist.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import html
import os
import re
import time
import urllib.parse
from collections import Counter, defaultdict
from typing import Dict, Iterable, List, Optional, Set, Tuple

import verify_ub_catalogs as v


COURSE_CODE_RE = re.compile(r"^\s*([A-Z]{2,6})\s*([0-9]{2,4}[A-Z]{0,6})\b")

GENERIC_DEPARTMENTS = {
    "department/program",
    "departments & programs",
    "departments and programs",
    "academic programs",
    "professional programs",
}


def normalize_course_code(raw: str) -> str:
    s = (raw or "").replace("\u00a0", " ").strip()
    m = COURSE_CODE_RE.match(s)
    if not m:
        return s
    return f"{m.group(1)} {m.group(2)}".strip()


def canonicalize_program_url(raw: str) -> str:
    url = (raw or "").strip()
    if not url:
        return url
    parts = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    q = [(k, v) for (k, v) in q if k.lower() != "returnto"]
    q = sorted(q, key=lambda kv: (kv[0].lower(), kv[1]))
    query = urllib.parse.urlencode(q)
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, query, ""))


def base_course_code(code: str) -> Optional[str]:
    """Convert 'AAP 101SEM' -> 'AAP 101'."""
    if not code:
        return None
    s = html.unescape(code).replace("\u00a0", " ")
    s = re.sub(r"\s+", " ", s).strip()
    m = re.match(r"^\s*([A-Z]{2,6})\s*([0-9]{2,4})", s)
    if not m:
        return None
    return f"{m.group(1)} {m.group(2)}"


@dataclasses.dataclass
class CourseInfo:
    title: str = ""
    credits: str = ""
    description: str = ""
    has_credits_marker: bool = False


def parse_code_and_title(line: str) -> Tuple[Optional[str], Optional[str]]:
    """Parse strings like 'AAP 101SEM - Introduction to Arts Management'."""
    if not line:
        return None, None
    s = html.unescape(line).replace("\u00a0", " ")
    s = re.sub(r"\s+", " ", s).strip()
    # Split on first dash-like separator.
    parts = re.split(r"\s*[-\u2013\u2014]\s*", s, maxsplit=1)
    if not parts:
        return None, None
    code = normalize_course_code(parts[0])
    title = parts[1].strip() if len(parts) > 1 else ""
    if not code or not COURSE_CODE_RE.match(code):
        return None, None
    return code, title


LISTING_ENTRY_RE = re.compile(
    r'href="(?P<href>[^\"]*preview_course(?:_nopop)?\.php\?[^\"]*coid=(?P<coid>[0-9]+)[^\"]*)"[^>]*title="(?P<title>[^"]+)"',
    re.IGNORECASE,
)


def extract_course_code_to_preview_url(listing_html: str, page_url: str, catoid: int, targets: Set[str]) -> Dict[str, str]:
    """From a course descriptions listing page, map courseCode -> preview_course_nopop url.

    We rely on the anchor's title attribute which includes 'CODE - Title opens a new window'.
    """
    out: Dict[str, str] = {}
    base_candidates: Dict[str, str] = {}
    for m in LISTING_ENTRY_RE.finditer(listing_html):
        title_attr = m.group("title")
        # Strip the boilerplate suffix.
        title_attr = re.sub(r"\s+opens a new window\s*$", "", html.unescape(title_attr), flags=re.IGNORECASE)
        listing_code, _ = parse_code_and_title(title_attr)
        if not listing_code:
            continue
        coid = m.group("coid")
        preview_url = f"{v.BASE_URL}/preview_course_nopop.php?catoid={catoid}&coid={coid}"

        # Prefer exact matches.
        if listing_code in targets:
            out[listing_code] = preview_url
            continue

        # Fallback: export may omit suffixes (e.g., LAW 501 vs LAW 501LEC).
        base = base_course_code(listing_code)
        if base and base in targets and base not in out:
            # Multiple suffix variants may exist (LEC/SEM/TUT/etc). For credits/description
            # these are typically equivalent, so keep the first seen deterministically.
            base_candidates.setdefault(base, preview_url)

    for base, url in base_candidates.items():
        if base not in out:
            out[base] = url
    return out


def parse_course_preview_html(preview_html: str) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str]]:
    """Return (code, title, credits, description) from a preview_course_nopop page."""

    # Title line
    m = re.search(r"<h1\s+id=['\"]course_preview_title['\"][^>]*>(.*?)</h1>", preview_html, flags=re.IGNORECASE | re.DOTALL)
    title_line = ""
    if m:
        title_line = re.sub(r"<[^>]+>", " ", m.group(1))
        title_line = re.sub(r"\s+", " ", html.unescape(title_line).replace("\u00a0", " ")).strip()

    code, parsed_title = parse_code_and_title(title_line)

    # Credits marker
    credits = None
    mc = re.search(r"Credits:\s*([^<\n\r]+)", preview_html, flags=re.IGNORECASE)
    if mc:
        credits = re.sub(r"\s+", " ", html.unescape(mc.group(1)).replace("\u00a0", " ")).strip()

    # Description: text after <hr> and before the credits section.
    desc = None
    hr = re.search(r"</h1>\s*<hr[^>]*>", preview_html, flags=re.IGNORECASE)
    if hr:
        rest = preview_html[hr.end() :]
        # Heuristic: cut at the first occurrence of a credits marker (in HTML), but be forgiving
        # about formatting (sometimes no <br><br>, sometimes wrapped in <strong>, etc).
        cut = re.search(r"Credits\s*:\s*", rest, flags=re.IGNORECASE)
        chunk_html = rest[: cut.start()] if cut else rest
        chunk = re.sub(r"<[^>]+>", " ", chunk_html)
        chunk = re.sub(r"\s+", " ", html.unescape(chunk).replace("\u00a0", " ")).strip()
        if chunk:
            desc = chunk

    return code, parsed_title or None, credits, desc


def fetch_missing_course_info(base: str, catoids: List[int], missing_codes: Set[str]) -> Dict[str, CourseInfo]:
    """Targeted network repair: fetch only course previews for missing course codes."""

    if not missing_codes:
        return {}

    # Discover preview URLs for missing codes by scanning course listing pages.
    code_to_preview: Dict[str, str] = {}
    for catoid in sorted(set(catoids)):
        if not (missing_codes - set(code_to_preview.keys())):
            break

        try:
            index_url = f"{base}/index.php?catoid={catoid}"
            index_html = v.fetch(index_url)
        except Exception:
            continue

        sp = v.SidebarParser(index_url)
        sp.feed(index_html)
        course_link = v.discover_course_descriptions_link(sp.links)
        if not course_link:
            continue
        navoid = v.parse_navoid(course_link.href)
        if not navoid:
            continue

        first_url = v.make_course_content_url(base, catoid, navoid, None)
        try:
            first_html = v.fetch(first_url)
        except Exception:
            continue

        try:
            max_page = v.discover_course_pages(first_html)
        except Exception:
            max_page = 1

        for page in range(1, max_page + 1):
            if not (missing_codes - set(code_to_preview.keys())):
                break
            url = v.make_course_content_url(base, catoid, navoid, page)
            try:
                listing_html = first_html if page == 1 else v.fetch(url)
            except Exception:
                continue
            found = extract_course_code_to_preview_url(listing_html, url, catoid, missing_codes)
            code_to_preview.update(found)
            time.sleep(0.02)

    # Fetch previews and parse.
    out: Dict[str, CourseInfo] = {}
    for target_code, purl in code_to_preview.items():
        try:
            ph = v.fetch(purl)
        except Exception:
            continue
        _parsed_code, title, credits, desc = parse_course_preview_html(ph)
        has_credits_marker = bool(re.search(r"Credits\s*:\s*", ph, flags=re.IGNORECASE))
        info = CourseInfo(
            title=title or "",
            credits=credits or "",
            description=desc or "",
            has_credits_marker=has_credits_marker,
        )
        out[target_code] = info
        time.sleep(0.02)

    return out


def build_course_lookup(rows: Iterable[Dict[str, str]]) -> Dict[str, CourseInfo]:
    """Build best-effort course lookup from existing CATALOG rows."""

    by_code: Dict[str, CourseInfo] = {}

    def better(existing: str, candidate: str) -> str:
        if existing and existing.strip():
            return existing
        return candidate

    def better_desc(existing: str, candidate: str) -> str:
        e = (existing or "").strip()
        c = (candidate or "").strip()
        if len(c) > len(e):
            return candidate
        return existing

    for r in rows:
        if (r.get("Section") or "").strip().upper() != "CATALOG":
            continue
        code = normalize_course_code(r.get("Course Code", ""))
        if not code or not COURSE_CODE_RE.match(code):
            continue
        title = (r.get("Course Title") or "").strip()
        credits = (r.get("Credits") or "").strip()
        desc = (r.get("Course Description") or "").strip()

        cur = by_code.get(code, CourseInfo())
        cur.title = better(cur.title, title)
        cur.credits = better(cur.credits, credits)
        cur.description = better_desc(cur.description, desc)
        by_code[code] = cur

        # Also store under the base code (e.g. AAP 101SEM -> AAP 101) so AUDIT rows
        # that carry section suffixes can be filled from CATALOG rows.
        base = base_course_code(code)
        if base and base != code:
            cur2 = by_code.get(base, CourseInfo())
            cur2.title = better(cur2.title, title)
            cur2.credits = better(cur2.credits, credits)
            cur2.description = better_desc(cur2.description, desc)
            by_code[base] = cur2

    return by_code


def build_program_owner_map(catoids: List[int]) -> Dict[str, v.ProgramOwner]:
    """Build programURL -> owner map for a set of UB catoids."""

    owners: Dict[str, v.ProgramOwner] = {}
    for c in sorted(set(catoids)):
        try:
            own = v.scan_ownership(v.BASE_URL, c)
        except Exception:
            continue
        for k, val in own.direct_programs.items():
            owners[canonicalize_program_url(k)] = val
        for k, val in own.entity_programs.items():
            owners[canonicalize_program_url(k)] = val
        time.sleep(0.05)
    return owners


def should_replace_department(existing: str) -> bool:
    s = (existing or "").strip()
    if not s:
        return True
    return s.lower().strip() in GENERIC_DEPARTMENTS


def probe_program_page(url: str) -> Dict[str, int]:
    """Lightweight probe: do requirements *appear* to exist on this program page?"""

    try:
        html = v.fetch(url)
    except Exception:
        return {"fetched": 0, "has_markers": 0, "has_acalog_courses": 0, "course_code_hits": 0}

    lower = re.sub(r"\s+", " ", html.lower())
    has_markers = int(any(m in lower for m in v.REQ_START_MARKERS))
    has_acalog_courses = int("acalog-course" in html)
    course_code_hits = len(set(m.group(0) for m in v.COURSE_CODE_RE.finditer(html)))
    return {
        "fetched": 1,
        "has_markers": has_markers,
        "has_acalog_courses": has_acalog_courses,
        "course_code_hits": course_code_hits,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_path", required=True, help="Input export CSV")
    ap.add_argument("--out", dest="out_path", required=True, help="Output resolved CSV")
    ap.add_argument("--report", dest="report_path", required=True, help="Output markdown report")
    ap.add_argument(
        "--probe-missing-requirements",
        action="store_true",
        help="Fetch program pages for AUDIT rows that say requirements are missing and summarize signals.",
    )
    args = ap.parse_args()

    with open(args.in_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        if not fieldnames:
            raise SystemExit("CSV has no header")
        rows = list(reader)

    # Summarize AUDIT rows.
    audit_rows = [r for r in rows if (r.get("Section") or "").strip().upper() == "AUDIT"]
    catalog_rows = [r for r in rows if (r.get("Section") or "").strip().upper() == "CATALOG"]

    # Determine which UB catalogs are represented.
    catoids: List[int] = []
    for r in rows:
        c = (r.get("Source Catoid") or "").strip()
        if c.isdigit():
            catoids.append(int(c))
        else:
            # Sometimes this column contains semi-colon lists in AUDIT rows.
            for part in re.split(r"[;,\"]", c):
                part = part.strip()
                if part.isdigit():
                    catoids.append(int(part))

    course_lookup = build_course_lookup(rows)
    program_owners = build_program_owner_map([c for c in catoids if c in v.CATOIDS])

    # Apply repairs.
    filled_credits = 0
    filled_titles = 0
    filled_desc = 0
    filled_departments = 0

    for r in rows:
        code_raw = r.get("Course Code", "")
        code = normalize_course_code(code_raw)
        lookup_key = code if code in course_lookup else (base_course_code(code) or "")
        if lookup_key and lookup_key in course_lookup:
            info = course_lookup[lookup_key]
            if not (r.get("Course Title") or "").strip() and info.title:
                r["Course Title"] = info.title
                filled_titles += 1
            if not (r.get("Credits") or "").strip() and info.credits:
                r["Credits"] = info.credits
                filled_credits += 1
            if not (r.get("Course Description") or "").strip() and info.description:
                r["Course Description"] = info.description
                filled_desc += 1

        # Ownership/department fill using directory-derived map
        program_url = (r.get("Program URL") or "").strip()
        if program_url:
            canonical = canonicalize_program_url(program_url)
            owner = program_owners.get(canonical)
            if owner and should_replace_department(r.get("Department") or ""):
                r["Department"] = owner.department
                filled_departments += 1

    # After intra-export fill, do targeted network repair for remaining missing course fields.
    missing_codes: Set[str] = set()
    for r in catalog_rows:
        code = normalize_course_code(r.get("Course Code", ""))
        if not code or not COURSE_CODE_RE.match(code):
            continue
        if not (r.get("Credits") or "").strip() or not (r.get("Course Description") or "").strip() or not (r.get("Course Title") or "").strip():
            missing_codes.add(code)

    fetched_course_info = fetch_missing_course_info(v.BASE_URL, [c for c in catoids if c in v.CATOIDS], missing_codes)
    fetched_titles = 0
    fetched_credits = 0
    fetched_desc = 0

    if fetched_course_info:
        for r in rows:
            code = normalize_course_code(r.get("Course Code", ""))
            if not code:
                continue
            key = code if code in fetched_course_info else (base_course_code(code) or "")
            if not key or key not in fetched_course_info:
                continue
            info = fetched_course_info[key]
            if not (r.get("Course Title") or "").strip() and info.title:
                r["Course Title"] = info.title
                fetched_titles += 1
            if not (r.get("Credits") or "").strip() and info.credits:
                r["Credits"] = info.credits
                fetched_credits += 1
            if not (r.get("Course Description") or "").strip() and info.description:
                r["Course Description"] = info.description
                fetched_desc += 1

    # Resolve remaining AUDIT rows for missing credits by fetching preview pages.
    unresolved_audit_credit_rows = [
        r
        for r in audit_rows
        if (r.get("Issue") or "").strip() == "Partial course row: missing credits"
        and (r.get("Course Code") or "").strip()
        and not (r.get("Credits") or "").strip()
    ]

    unresolved_audit_codes: Set[str] = set()
    for r in unresolved_audit_credit_rows:
        code = normalize_course_code(r.get("Course Code", ""))
        if code and COURSE_CODE_RE.match(code):
            unresolved_audit_codes.add(code)

    audit_fetch_info = fetch_missing_course_info(v.BASE_URL, [c for c in catoids if c in v.CATOIDS], unresolved_audit_codes)
    audit_filled_credits = 0
    audit_unresolvable_no_marker = 0
    audit_unresolvable_not_found = 0

    for r in unresolved_audit_credit_rows:
        code = normalize_course_code(r.get("Course Code", ""))
        if not code:
            continue
        key = code if code in audit_fetch_info else (base_course_code(code) or "")
        info = audit_fetch_info.get(key) if key else None
        if not info:
            r["Issue"] = "UNRESOLVABLE: Partial course row: missing credits (no preview URL found)"
            audit_unresolvable_not_found += 1
            continue
        if info.credits:
            r["Credits"] = info.credits
            r["Issue"] = "RESOLVED: Partial course row: missing credits"
            audit_filled_credits += 1
            continue
        # Preview fetched but did not expose credits in a parseable way.
        if info.has_credits_marker:
            r["Issue"] = "UNRESOLVABLE: Partial course row: missing credits (preview has credits marker but parse failed)"
        else:
            r["Issue"] = "UNRESOLVABLE: Partial course row: missing credits (preview page has no credits marker)"
            audit_unresolvable_no_marker += 1

    # Mark course-related AUDIT rows as resolved when the corresponding fields are now present.
    resolved_audit_rows = 0
    for r in audit_rows:
        issue = (r.get("Issue") or "").strip()
        if not issue or issue.startswith("RESOLVED:"):
            continue
        if "Partial course" not in issue:
            continue

        code = normalize_course_code(r.get("Course Code", ""))
        if not code or not COURSE_CODE_RE.match(code):
            continue

        key = base_course_code(code) or code

        # Find any CATALOG row with this code (post-fill) to judge resolution.
        # This is conservative: if any catalog row still missing credits, we won't mark resolved.
        related = [x for x in catalog_rows if (base_course_code(normalize_course_code(x.get("Course Code", ""))) or normalize_course_code(x.get("Course Code", ""))) == key]
        if not related:
            continue

        def all_have(field: str) -> bool:
            return all((x.get(field) or "").strip() for x in related)

        needs_credits = "credits" in issue.lower()
        needs_title = "title" in issue.lower()
        needs_desc = "description" in issue.lower()

        ok = True
        if needs_credits and not all_have("Credits"):
            ok = False
        if needs_title and not all_have("Course Title"):
            ok = False
        if needs_desc and not all_have("Course Description"):
            ok = False

        if ok:
            r["Issue"] = f"RESOLVED: {issue}"
            resolved_audit_rows += 1

    # Build remaining-issue counts.
    def is_missing(val: str) -> bool:
        return not (val or "").strip()

    remaining_catalog_missing = {
        "missing_credits": sum(1 for r in catalog_rows if is_missing(r.get("Course Code", "")) is False and is_missing(r.get("Credits", "")) and COURSE_CODE_RE.match(normalize_course_code(r.get("Course Code", "")) or "")),
        "missing_title": sum(1 for r in catalog_rows if is_missing(r.get("Course Code", "")) is False and is_missing(r.get("Course Title", "")) and COURSE_CODE_RE.match(normalize_course_code(r.get("Course Code", "")) or "")),
        "missing_description": sum(1 for r in catalog_rows if is_missing(r.get("Course Code", "")) is False and is_missing(r.get("Course Description", "")) and COURSE_CODE_RE.match(normalize_course_code(r.get("Course Code", "")) or "")),
        "generic_department": sum(1 for r in catalog_rows if (r.get("Department") or "").strip().lower() in GENERIC_DEPARTMENTS),
    }

    audit_issue_counts = Counter((r.get("Issue") or "").strip() for r in audit_rows)
    audit_entity_counts = Counter((r.get("Entity") or "").strip() for r in audit_rows)

    # Optional probe of missing-requirements programs.
    probe_summary: Optional[Dict[str, int]] = None
    probe_examples: List[Tuple[str, str]] = []
    probed_requirements_rows: List[Tuple[Dict[str, str], Dict[str, int]]] = []
    if args.probe_missing_requirements:
        target = [
            r for r in audit_rows
            if (r.get("Entity") or "").strip() == "MajorEntity"
            and (r.get("Issue") or "").strip() == "Program saved to database but no requirements found"
            and (r.get("Program URL") or "").strip()
        ]

        agg = Counter()
        for idx, r in enumerate(target):
            url = (r.get("Program URL") or "").strip()
            stats = probe_program_page(url)
            agg.update(stats)
            probed_requirements_rows.append((r, stats))
            if idx < 10:
                degree = (r.get("Degree Name") or "").strip()
                probe_examples.append((degree, url))
            time.sleep(0.02)
        probe_summary = dict(agg)

        # Annotate the AUDIT rows in-place with probe evidence to make them actionable.
        for (row, stats) in probed_requirements_rows:
            if not stats.get("fetched"):
                continue
            markers = stats.get("has_markers", 0)
            acalog = stats.get("has_acalog_courses", 0)
            hits = stats.get("course_code_hits", 0)
            row["Issue"] = f"Program saved to database but no requirements found (PROBE: markers={markers}, acalog={acalog}, codes={hits})"

    # Write output CSV.
    os.makedirs(os.path.dirname(args.out_path) or ".", exist_ok=True)
    with open(args.out_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    # Write report.
    os.makedirs(os.path.dirname(args.report_path) or ".", exist_ok=True)
    with open(args.report_path, "w", encoding="utf-8") as f:
        f.write("# UB Export Audit Resolution\n\n")
        f.write(f"Input: {os.path.basename(args.in_path)}\n\n")

        f.write("## Fixes Applied\n\n")
        f.write(f"- Filled missing course titles: {filled_titles}\n")
        f.write(f"- Filled missing course credits: {filled_credits}\n")
        f.write(f"- Filled missing course descriptions: {filled_desc}\n")
        f.write(f"- Replaced generic department labels via directory mapping: {filled_departments}\n\n")

        f.write("## Network Repairs (Course Previews)\n\n")
        f.write(f"- Unique course codes needing network repair (post intra-export fill): {len(missing_codes)}\n")
        f.write(f"- Course codes found via listing pages: {len(fetched_course_info)}\n")
        f.write(f"- Rows filled (title): {fetched_titles}\n")
        f.write(f"- Rows filled (credits): {fetched_credits}\n")
        f.write(f"- Rows filled (description): {fetched_desc}\n\n")

        f.write("## AUDIT Fixups (Missing Credits)\n\n")
        f.write(f"- Unresolved AUDIT rows targeted: {len(unresolved_audit_credit_rows)}\n")
        f.write(f"- Unique course codes targeted: {len(unresolved_audit_codes)}\n")
        f.write(f"- Unique codes found via listing pages: {len(audit_fetch_info)}\n")
        f.write(f"- AUDIT rows credits filled: {audit_filled_credits}\n")
        f.write(f"- AUDIT rows unresolvable (no preview URL found): {audit_unresolvable_not_found}\n")
        f.write(f"- AUDIT rows unresolvable (preview has no credits marker): {audit_unresolvable_no_marker}\n\n")

        f.write("## Remaining Gaps (CATALOG rows)\n\n")
        for k, v_ in remaining_catalog_missing.items():
            f.write(f"- {k}: {v_}\n")
        f.write("\n")

        f.write("## AUDIT Rows Summary\n\n")
        f.write(f"- Total AUDIT rows: {len(audit_rows)}\n")
        f.write(f"- Course-related AUDIT rows marked RESOLVED: {resolved_audit_rows}\n")
        if audit_entity_counts:
            f.write("- By entity:\n")
            for ent, cnt in audit_entity_counts.most_common(12):
                f.write(f"  - {ent}: {cnt}\n")
        f.write("\n")

        if audit_issue_counts:
            f.write("- Top issues:\n")
            for issue, cnt in audit_issue_counts.most_common(15):
                if not issue:
                    continue
                f.write(f"  - {issue}: {cnt}\n")
        f.write("\n")

        if probe_summary is not None:
            f.write("## Probe: Programs flagged as missing requirements\n\n")
            f.write("This does NOT re-scrape requirements into structured rows; it only checks whether\n")
            f.write("the program pages appear to contain requirement markers or course list HTML.\n\n")
            f.write(f"- Programs probed: {probe_summary.get('fetched', 0)}\n")
            f.write(f"- Pages with requirement markers: {probe_summary.get('has_markers', 0)}\n")
            f.write(f"- Pages with acalog course list items: {probe_summary.get('has_acalog_courses', 0)}\n")
            f.write(f"- Total unique course-code hits (sum across pages): {probe_summary.get('course_code_hits', 0)}\n\n")
            if probe_examples:
                f.write("Examples (first 10):\n")
                for degree, url in probe_examples:
                    f.write(f"- {degree}: {url}\n")
                f.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
