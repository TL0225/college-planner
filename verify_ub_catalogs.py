#!/usr/bin/env python3
"""Verify UB ModernCampus catalogs at a high level.

This is NOT a full end-to-end app run. It is a network verification that:
- Locates key sidebar pages (Department/Program directory, program listing, course descriptions)
- Builds a directory-derived mapping of program -> (dept, college)
- Compares listing programs vs directory coverage
- Samples program pages for requirements markers
- Samples course preview pages for title/credits/description presence

Designed to produce evidence-based confidence, not a guarantee.
"""

from __future__ import annotations

import dataclasses
import html
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from typing import Dict, List, Optional, Tuple

import certifi

import argparse
import concurrent.futures


BASE_URL = "https://catalogs.buffalo.edu"
CATOIDS = [17, 19, 22, 23, 24]

USER_AGENT = "CollegeAppVerifier/1.0 (macOS; python)"
TIMEOUT = 30


def fetch(url: str) -> str:
    # Some Python environments (especially venvs on macOS) may not have an up-to-date
    # system CA store configured. Use certifi to ensure HTTPS works.
    ctx = ssl.create_default_context(cafile=certifi.where())
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html"})
    with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as resp:
        data = resp.read()
    # Acalog pages are UTF-8.
    return data.decode("utf-8", errors="replace")


def force_catoid(url: str, catoid: int) -> str:
    url = url.strip()
    if not url:
        return url
    parts = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    q = [(k, v) for (k, v) in q if k.lower() != "catoid"]
    q.append(("catoid", str(catoid)))
    query = urllib.parse.urlencode(q)
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))


def canonicalize_program_url(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    q = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    q = [(k, v) for (k, v) in q if k.lower() not in {"returnto"}]
    query = urllib.parse.urlencode(q)
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, query, ""))


def abs_url(base: str, href: str) -> str:
    return urllib.parse.urljoin(base, href)


@dataclasses.dataclass
class SidebarLink:
    label: str
    href: str


class SidebarParser(HTMLParser):
    """Extract sidebar links from Acalog-ish index pages."""

    def __init__(self, base: str):
        super().__init__()
        self.base = base
        self._in_n2_links = False
        self._capture_a = False
        self._a_href: Optional[str] = None
        self._a_text_parts: List[str] = []
        self.links: List[SidebarLink] = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "div" and attrs.get("class") == "n2_links":
            self._in_n2_links = True
        if self._in_n2_links and tag == "a":
            href = attrs.get("href", "")
            if href:
                self._capture_a = True
                self._a_href = abs_url(self.base, href)
                self._a_text_parts = []

    def handle_endtag(self, tag):
        if tag == "div" and self._in_n2_links:
            self._in_n2_links = False
        if tag == "a" and self._capture_a:
            label = html.unescape("".join(self._a_text_parts)).replace("\xa0", " ")
            label = re.sub(r"\s+", " ", label).strip()
            if label and self._a_href:
                self.links.append(SidebarLink(label=label, href=self._a_href))
            self._capture_a = False
            self._a_href = None
            self._a_text_parts = []

    def handle_data(self, data):
        if self._capture_a:
            self._a_text_parts.append(data)


@dataclasses.dataclass
class ProgramOwner:
    department: str
    college: str


@dataclasses.dataclass
class OwnershipScanResult:
    directory_url: Optional[str]
    direct_programs: Dict[str, ProgramOwner]
    entity_pages: List[Tuple[str, str, str]]  # (entity_name, entity_url, college)
    entity_programs: Dict[str, ProgramOwner]


class DirectoryParser(HTMLParser):
    """Walk directory page in document order collecting h2/h3/h4 and preview links."""

    def __init__(self, base: str, fallback_college: Optional[str] = None):
        super().__init__()
        self.base = base
        self.fallback_college = fallback_college
        self._current_tag: Optional[str] = None
        self._text_parts: List[str] = []

        self.current_college: Optional[str] = None
        self.current_dept: Optional[str] = None

        self.direct_programs: Dict[str, ProgramOwner] = {}
        self.entity_pages: List[Tuple[str, str, str]] = []

        self._a_href: Optional[str] = None
        self._a_onclick: Optional[str] = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {"h2", "h3", "h4"}:
            self._current_tag = tag
            self._text_parts = []
        if tag == "a":
            self._a_href = attrs.get("href")
            self._a_onclick = attrs.get("onclick")
            # we'll use link text in handle_endtag
            self._text_parts = []

    def handle_endtag(self, tag):
        if tag in {"h2", "h3"} and self._current_tag == tag:
            text = self._clean_text("".join(self._text_parts))
            if text:
                self.current_college = text
                self.current_dept = None
            self._current_tag = None
            self._text_parts = []
            return

        if tag == "h4" and self._current_tag == "h4":
            text = self._clean_text("".join(self._text_parts))
            if text and len(text) >= 3:
                self.current_dept = text
            self._current_tag = None
            self._text_parts = []
            return

        if tag == "a" and (self._a_href is not None or self._a_onclick is not None):
            link_text = self._clean_text("".join(self._text_parts))
            href = self._a_href or ""
            abs_href = abs_url(self.base, href) if href else ""

            effective_college = self.current_college or self.fallback_college

            # Direct program links
            if "preview_program.php" in href and effective_college:
                college = effective_college
                dept = self.current_dept or college
                program_url = canonicalize_program_url(abs_href)
                self.direct_programs[program_url] = ProgramOwner(department=dept, college=college)

            # Entity links
            if "preview_entity.php" in href and effective_college and link_text:
                college = effective_college
                entity_url = abs_href
                self.entity_pages.append((link_text, entity_url, college))

            self._a_href = None
            self._a_onclick = None
            self._text_parts = []
            return

    def handle_data(self, data):
        if self._current_tag in {"h2", "h3", "h4"}:
            self._text_parts.append(data)
        elif self._a_href is not None or self._a_onclick is not None:
            self._text_parts.append(data)

    @staticmethod
    def _clean_text(s: str) -> str:
        s = html.unescape(s).replace("\xa0", " ")
        s = re.sub(r"\s+", " ", s).strip()
        return s


def score_ownership_directory_label(label: str) -> int:
    """Score sidebar labels that likely represent an org/program directory.

    UB variants across catalogs include:
    - "Departments & Programs" / "Department/Program" (undergrad/grad)
    - "Academic Programs" (law/medical)
    - "Professional Programs" (dental)
    """
    lower = label.lower()

    # Require *some* ownership-ish hint.
    if ("department" not in lower) and ("program" not in lower):
        return 0

    score = 1

    # Strongest signals
    if "departments & programs" in lower or "departments and programs" in lower:
        score += 30
    if "department/program" in lower:
        score += 30
    if "department" in lower and "program" in lower:
        score += 15

    # Catalogs that don’t surface departments still often have a Programs directory.
    if "academic programs" in lower:
        score += 18
    if "professional programs" in lower:
        score += 18

    # Generic
    if lower.strip() == "programs":
        score += 8
    elif "program" in lower:
        score += 5
    if "department" in lower:
        score += 6

    return score


def score_program_listing_label(label: str) -> int:
    lower = label.lower()
    score = 0
    if lower == "majors":
        score += 10
    if "majors" in lower:
        score += 9
    if "minors" in lower:
        score += 7
    if lower == "programs":
        score += 6
    if "program" in lower:
        score += 5
    if "degrees" in lower:
        score += 3
    return score


def extract_catalog_title(html_text: str) -> Optional[str]:
    """Best-effort catalog title extraction used as a fallback ownership label.

    Some UB professional catalogs have flat program lists on the directory page with no
    h2/h3/h4 structure. The app falls back to the catalog title in that case; the verifier
    should mirror that so directory coverage isn't undercounted.
    """

    # Prefer the header ModernCampus uses for the catalog name.
    m = re.search(
        r'<span[^>]*class="[^"]*acalog_catalog_name[^"]*"[^>]*>(.*?)</span>',
        html_text,
        re.IGNORECASE | re.DOTALL,
    )
    if m:
        text = re.sub(r"<[^>]+>", " ", m.group(1))
        text = DirectoryParser._clean_text(text)
        if text:
            return text

    # Fallback: the main content header sometimes contains the catalog title.
    m = re.search(r'<h1[^>]*id="acalog-content"[^>]*>(.*?)</h1>', html_text, re.IGNORECASE | re.DOTALL)
    if m:
        text = re.sub(r"<[^>]+>", " ", m.group(1))
        text = DirectoryParser._clean_text(text)
        if text:
            return text

    return None


def is_program_container_label(label: str) -> bool:
    """Heuristic: labels that likely contain lists of programs."""
    lower = label.lower()
    keywords = [
        "majors",
        "minors",
        "programs",
        "professional programs",
        "graduate programs",
        "undergraduate programs",
        "degrees",
        "certificates",
        "advanced certificates",
        "academic programs",
    ]
    return any(k in lower for k in keywords)


REQ_START_MARKERS = [
    "course requirements",
    "major requirements",
    "requirements",
    "degree requirements",
    "program requirements",
    "curriculum",
    "required core",
    "additional requirements",
    "core requirements",
    "core courses",
    "elective requirements",
    "required courses",
]

COURSE_CODE_RE = re.compile(r"\b([A-Z]{2,4})\s*(\d{3})\b")


def find_best_sidebar_link(links: List[SidebarLink], scorer) -> Optional[SidebarLink]:
    best = None
    best_score = 0
    for l in links:
        s = scorer(l.label)
        if s > best_score:
            best = l
            best_score = s
    return best


def extract_preview_program_links(html_text: str, base: str) -> List[str]:
    # Cheap but effective for Acalog pages.
    hrefs = re.findall(r'href="([^"]*preview_program\.php[^"]*)"', html_text)
    out = []
    for h in hrefs:
        out.append(canonicalize_program_url(abs_url(base, html.unescape(h).replace("&amp;", "&"))))
    return sorted(set(out))


def extract_department_from_program_page(html_text: str) -> Optional[str]:
    """Best-effort UB-style department extraction.

    Mirrors the Swift fallback: look for a preview_entity link whose anchor text contains
    "department" and strip suffixes like "department page".
    """

    # Find anchor tags linking to preview_entity with their inner text.
    for m in re.finditer(
        r'<a[^>]*href="([^"]*preview_entity\.php[^"]*)"[^>]*>(.*?)</a>',
        html_text,
        re.IGNORECASE | re.DOTALL,
    ):
        inner = m.group(2)
        text = re.sub(r"<[^>]+>", " ", inner)
        text = DirectoryParser._clean_text(text)
        if not text:
            continue

        lower = text.lower()
        if lower in {"learn more about the", "program office", "program office:"}:
            continue

        if "department" not in lower:
            continue

        cleaned = re.sub(r"\s+department\s+page\s*$", "", text, flags=re.IGNORECASE)
        cleaned = re.sub(r"\s+page\s*$", "", cleaned, flags=re.IGNORECASE)
        cleaned = DirectoryParser._clean_text(cleaned)
        if cleaned.lower() == "department" or len(cleaned) < 3:
            continue

        # Normalize "X department" -> "X" (unless it starts with "Department of")
        if not cleaned.lower().startswith("department of") and cleaned.lower().endswith(" department"):
            cleaned = re.sub(r"\s+department\s*$", "", cleaned, flags=re.IGNORECASE)
            cleaned = DirectoryParser._clean_text(cleaned)

        if cleaned:
            return cleaned

    return None


def discover_course_pages(first_html: str) -> int:
    """Try to discover the maximum course descriptions page count."""
    # Look for filter[cpage]=N (URL encoded or not)
    candidates = []
    for m in re.finditer(r"filter(?:%5B|\[)cpage(?:%5D|\])=([0-9]+)", first_html, re.IGNORECASE):
        try:
            candidates.append(int(m.group(1)))
        except Exception:
            pass
    return max([1] + candidates)


def make_course_content_url(base: str, catoid: int, navoid: str, cpage: Optional[int]) -> str:
    params = [("catoid", str(catoid)), ("navoid", navoid)]
    if cpage and cpage > 1:
        params.append(("filter[cpage]", str(cpage)))
    return f"{base}/content.php?{urllib.parse.urlencode(params)}"


def discover_course_descriptions_link(links: List[SidebarLink]) -> Optional[SidebarLink]:
    best = None
    best_score = 0
    for l in links:
        lower = l.label.lower()
        score = 0
        if "course descriptions" in lower:
            score += 10
        if "course description" in lower:
            score += 9
        if lower == "courses":
            score += 6
        if "courses" in lower:
            score += 4
        if score > best_score:
            best = l
            best_score = score
    return best


def parse_navoid(url: str) -> Optional[str]:
    try:
        parts = urllib.parse.urlsplit(url)
        q = dict(urllib.parse.parse_qsl(parts.query, keep_blank_values=True))
        return q.get("navoid")
    except Exception:
        return None


def extract_course_stub_preview_urls(html_text: str, base: str, catoid: int) -> List[str]:
    """Extract preview_course_nopop URLs from a course descriptions content page.

    Supports both direct hrefs and onclick-driven rows by synthesizing preview URLs.
    """
    out: List[str] = []

    # Direct hrefs
    hrefs = re.findall(r'href="([^"]*preview_course(?:_nopop)?\.php[^"]*)"', html_text)
    for h in hrefs:
        u = abs_url(base, html.unescape(h).replace("&amp;", "&"))
        # Prefer nopop for consistent parsing
        out.append(u)

    # Onclick-driven rows: look for coid=... and build preview_course_nopop
    # This is a heuristic; the app does something similar.
    coids = re.findall(r"\bcoid\b\s*=?\s*'?([0-9]+)'?", html_text, re.IGNORECASE)
    for coid in coids:
        out.append(f"{BASE_URL}/preview_course_nopop.php?catoid={catoid}&coid={coid}")

    # Some pages use function calls with coid as a bare number argument.
    # Capture common patterns like showCourse(1234) or hideCatalogData(...., 1234)
    bare = re.findall(r"(?:showCourse|hideCatalogData)\s*\([^\)]*?([0-9]{3,7})[^\)]*\)", html_text)
    for coid in bare:
        out.append(f"{BASE_URL}/preview_course_nopop.php?catoid={catoid}&coid={coid}")

    # De-dupe and normalize catoid
    cleaned = []
    for u in out:
        cleaned.append(force_catoid(u, catoid))
    return sorted(set(cleaned))


def check_course_preview(html_text: str) -> Tuple[bool, bool, bool]:
    has_title = "course_preview_title" in html_text
    has_credits = re.search(r"Credits:\s*\d", html_text, re.IGNORECASE) is not None
    # Rough proxy: preview pages usually contain a sizable amount of text beyond the title.
    text_only = re.sub(r"<[^>]+>", " ", html_text)
    text_only = re.sub(r"\s+", " ", text_only).strip()
    has_descriptionish = has_title and len(text_only) > 800
    return has_title, has_credits, has_descriptionish


def scan_ownership(base: str, catoid: int) -> OwnershipScanResult:
    index_url = f"{base}/index.php?catoid={catoid}"
    index_html = fetch(index_url)

    sp = SidebarParser(index_url)
    sp.feed(index_html)

    best_dir = find_best_sidebar_link(sp.links, score_ownership_directory_label)
    if not best_dir:
        return OwnershipScanResult(directory_url=None, direct_programs={}, entity_pages=[], entity_programs={})

    directory_url = force_catoid(best_dir.href, catoid)
    directory_html = fetch(directory_url)

    fallback_college = extract_catalog_title(directory_html)
    dp = DirectoryParser(directory_url, fallback_college=fallback_college)
    dp.feed(directory_html)

    # Follow entity pages (full; these are typically manageable for UB)
    entity_programs: Dict[str, ProgramOwner] = {}
    for (entity_name, entity_url, college) in dp.entity_pages:
        try:
            entity_html = fetch(force_catoid(entity_url, catoid))
        except Exception:
            continue
        for purl in extract_preview_program_links(entity_html, entity_url):
            entity_programs[purl] = ProgramOwner(department=entity_name, college=college)
        time.sleep(0.05)

    return OwnershipScanResult(
        directory_url=directory_url,
        direct_programs=dp.direct_programs,
        entity_pages=dp.entity_pages,
        entity_programs=entity_programs,
    )


def scan_program_listing(base: str, catoid: int) -> Tuple[Optional[str], List[str], List[SidebarLink]]:
    index_url = f"{base}/index.php?catoid={catoid}"
    index_html = fetch(index_url)
    sp = SidebarParser(index_url)
    sp.feed(index_html)

    best = find_best_sidebar_link(sp.links, score_program_listing_label)
    if not best:
        return None, [], sp.links

    listing_url = force_catoid(best.href, catoid)
    listing_html = fetch(listing_url)
    programs = extract_preview_program_links(listing_html, listing_url)
    return listing_url, programs, sp.links


def scan_all_program_containers(base: str, catoid: int) -> Tuple[List[str], Dict[str, List[str]]]:
    """Scan multiple sidebar container pages and return union of programs.

    Returns:
      - all_program_urls (deduped)
      - programs_by_container_url
    """
    index_url = f"{base}/index.php?catoid={catoid}"
    index_html = fetch(index_url)
    sp = SidebarParser(index_url)
    sp.feed(index_html)

    container_links = [l for l in sp.links if is_program_container_label(l.label) and "content.php" in l.href]
    # Always include the best guess if present.
    best = find_best_sidebar_link(sp.links, score_program_listing_label)
    if best and best not in container_links:
        container_links.insert(0, best)

    programs_by_container: Dict[str, List[str]] = {}
    all_programs: List[str] = []
    for link in container_links:
        url = force_catoid(link.href, catoid)
        try:
            html_text = fetch(url)
        except Exception:
            continue
        programs = extract_preview_program_links(html_text, url)
        if programs:
            programs_by_container[url] = programs
            all_programs.extend(programs)
        time.sleep(0.05)

    all_unique = sorted(set(all_programs))
    return all_unique, programs_by_container


def sample_requirements(program_urls: List[str], sample_n: int = 20) -> Dict[str, int]:
    found_section = 0
    found_courses = 0
    total = 0

    for url in program_urls[:sample_n]:
        total += 1
        try:
            html_text = fetch(url)
        except Exception:
            continue

        lower = re.sub(r"\s+", " ", html_text.lower())
        if any(m in lower for m in REQ_START_MARKERS):
            found_section += 1

        # quick proxy: count course-code patterns on the page
        codes = set(m.group(0) for m in COURSE_CODE_RE.finditer(html_text))
        if len(codes) > 0:
            found_courses += 1

        time.sleep(0.05)

    return {
        "sampled": total,
        "pages_with_requirement_markers": found_section,
        "pages_with_any_course_codes": found_courses,
    }


def audit_requirements(program_urls: List[str], max_programs: Optional[int]) -> Dict[str, int]:
    """Audit requirement markers and course-code presence across many/all program pages.

    This is a proxy audit: it does not re-implement the Swift requirement parser.
    """
    urls = program_urls if max_programs is None else program_urls[:max_programs]
    total = 0
    fetched = 0
    pages_with_markers = 0
    pages_with_course_codes = 0
    pages_with_acalog_courses = 0
    failures = 0

    for url in urls:
        total += 1
        try:
            html_text = fetch(url)
            fetched += 1
        except Exception:
            failures += 1
            continue

        lower = re.sub(r"\s+", " ", html_text.lower())
        if any(m in lower for m in REQ_START_MARKERS):
            pages_with_markers += 1

        codes = set(m.group(0) for m in COURSE_CODE_RE.finditer(html_text))
        if len(codes) > 0:
            pages_with_course_codes += 1

        if "acalog-course" in html_text:
            pages_with_acalog_courses += 1

        time.sleep(0.02)

    return {
        "programs_considered": total,
        "program_pages_fetched": fetched,
        "program_page_failures": failures,
        "pages_with_requirement_markers": pages_with_markers,
        "pages_with_any_course_codes": pages_with_course_codes,
        "pages_with_acalog_course_list_items": pages_with_acalog_courses,
    }


def scan_courses_section(base: str, catoid: int, sample_preview_n: int = 10) -> Dict[str, int]:
    index_url = f"{base}/index.php?catoid={catoid}"
    index_html = fetch(index_url)
    sp = SidebarParser(index_url)
    sp.feed(index_html)

    # Find course descriptions link in a forgiving way
    best = None
    best_score = 0
    for l in sp.links:
        lower = l.label.lower()
        score = 0
        if "course descriptions" in lower:
            score += 10
        if "course description" in lower:
            score += 9
        if lower == "courses":
            score += 6
        if "courses" in lower:
            score += 4
        if score > best_score:
            best = l
            best_score = score

    if not best:
        return {"found_course_sidebar_link": 0}

    first_url = force_catoid(best.href, catoid)
    first_html = fetch(first_url)

    # Extract preview_course_nopop links and also onclick coid patterns
    hrefs = re.findall(r'href="([^"]*preview_course_nopop\.php[^"]*)"', first_html)
    onclicks = re.findall(r"coid\s*=\s*'?([0-9]+)'?", first_html)

    preview_urls: List[str] = []
    for h in hrefs:
        preview_urls.append(abs_url(first_url, html.unescape(h).replace("&amp;", "&")))

    # If only onclick exists, synthesize preview urls using discovered coids
    # (This is the same idea as the app’s engine: request preview pages directly.)
    if not preview_urls and onclicks:
        for coid in onclicks:
            preview_urls.append(f"{base}/preview_course_nopop.php?catoid={catoid}&coid={coid}")

    preview_urls = sorted(set(preview_urls))

    sample_has_title = 0
    sample_has_credits = 0
    sample_has_descriptionish = 0

    for url in preview_urls[:sample_preview_n]:
        try:
            html_text = fetch(url)
        except Exception:
            continue

        if "course_preview_title" in html_text:
            sample_has_title += 1
        if re.search(r"Credits:\s*\d", html_text, re.IGNORECASE):
            sample_has_credits += 1
        # heuristic: preview pages usually have an <hr> and then description text
        if "course_preview_title" in html_text and len(re.sub(r"<[^>]+>", "", html_text)) > 2000:
            sample_has_descriptionish += 1

        time.sleep(0.05)

    return {
        "found_course_sidebar_link": 1,
        "course_descriptions_url_found": 1,
        "preview_urls_on_first_page": len(preview_urls),
        "preview_sampled": min(sample_preview_n, len(preview_urls)),
        "preview_samples_with_title": sample_has_title,
        "preview_samples_with_credits": sample_has_credits,
        "preview_samples_with_descriptionish": sample_has_descriptionish,
    }


def audit_courses_full(base: str, catoid: int, max_previews: Optional[int], max_workers: int) -> Dict[str, int]:
    index_url = f"{base}/index.php?catoid={catoid}"
    index_html = fetch(index_url)
    sp = SidebarParser(index_url)
    sp.feed(index_html)

    course_link = discover_course_descriptions_link(sp.links)
    if not course_link:
        return {"found_course_sidebar_link": 0}

    navoid = parse_navoid(course_link.href)
    if not navoid:
        # fall back: if the sidebar link is already content.php, try extracting
        return {"found_course_sidebar_link": 1, "course_descriptions_url_found": 0}

    first_url = make_course_content_url(base, catoid, navoid, None)
    first_html = fetch(first_url)
    max_page = discover_course_pages(first_html)

    # Gather preview URLs across all pages.
    preview_urls: List[str] = []
    preview_urls.extend(extract_course_stub_preview_urls(first_html, first_url, catoid))
    if max_page > 1:
        for page in range(2, max_page + 1):
            url = make_course_content_url(base, catoid, navoid, page)
            try:
                html_text = fetch(url)
            except Exception:
                continue
            preview_urls.extend(extract_course_stub_preview_urls(html_text, url, catoid))
            time.sleep(0.02)

    preview_urls = sorted(set(preview_urls))
    if max_previews is not None:
        preview_urls = preview_urls[:max_previews]

    # Crawl previews with bounded concurrency.
    total = len(preview_urls)
    fetched = 0
    failures = 0
    has_title = 0
    has_credits = 0
    has_desc = 0

    def worker(url: str) -> Tuple[bool, bool, bool, bool]:
        try:
            html_text = fetch(url)
        except Exception:
            return False, False, False, False
        t, c, d = check_course_preview(html_text)
        return True, t, c, d

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
        for ok, t, c, d in ex.map(worker, preview_urls):
            if not ok:
                failures += 1
                continue
            fetched += 1
            if t:
                has_title += 1
            if c:
                has_credits += 1
            if d:
                has_desc += 1

    return {
        "found_course_sidebar_link": 1,
        "course_descriptions_url_found": 1,
        "course_descriptions_pages": max_page,
        "course_preview_urls_discovered": total,
        "course_preview_pages_fetched": fetched,
        "course_preview_page_failures": failures,
        "course_preview_with_title": has_title,
        "course_preview_with_credits": has_credits,
        "course_preview_with_descriptionish": has_desc,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=BASE_URL)
    ap.add_argument("--catoids", default=",".join(map(str, CATOIDS)))
    ap.add_argument("--full", action="store_true", help="Run a heavier audit (all program containers, broad requirements checks, full course preview crawl).")
    ap.add_argument("--max-programs", type=int, default=0, help="Cap number of program pages to audit per catalog (0 = no cap).")
    ap.add_argument("--max-course-previews", type=int, default=0, help="Cap number of course preview pages to audit per catalog (0 = no cap).")
    ap.add_argument("--course-workers", type=int, default=10, help="Concurrency for course preview fetching.")
    args = ap.parse_args()

    base = args.base.rstrip("/")
    catoids = [int(x.strip()) for x in args.catoids.split(",") if x.strip()]
    max_programs = None if args.max_programs == 0 else args.max_programs
    max_course_previews = None if args.max_course_previews == 0 else args.max_course_previews

    report_lines: List[str] = []
    report_lines.append(f"# UB Catalog Verification Report\n")
    report_lines.append(f"Base: {base}")
    report_lines.append(f"Catalogs (catoid): {', '.join(map(str, catoids))}")
    report_lines.append(f"Mode: {'FULL' if args.full else 'SAMPLE'}\n")

    for c in catoids:
        report_lines.append(f"## catoid={c}\n")

        # Ownership directory mapping
        try:
            own = scan_ownership(BASE_URL, c)
        except Exception as e:
            report_lines.append(f"- Ownership scan: FAILED ({e})\n")
            continue

        if not own.directory_url:
            report_lines.append("- Ownership scan: no Department/Program directory link found in sidebar\n")
        else:
            report_lines.append(f"- Ownership directory page: {own.directory_url}")
            report_lines.append(f"- Direct program links found on directory page: {len(own.direct_programs)}")
            report_lines.append(f"- Entity pages linked (preview_entity.php): {len(own.entity_pages)}")
            report_lines.append(f"- Programs found via entity pages (sampled): {len(own.entity_programs)}\n")

        # Program listing coverage
        listing_programs: List[str] = []
        if args.full:
            try:
                all_programs, programs_by_container = scan_all_program_containers(base, c)
                listing_programs = all_programs
                report_lines.append(f"- Program container pages scanned: {len(programs_by_container)}")
                for u, ps in list(programs_by_container.items())[:6]:
                    report_lines.append(f"  - {u} (programs={len(ps)})")
                if len(programs_by_container) > 6:
                    report_lines.append("  - (more omitted)")
                report_lines.append(f"- Unique programs discovered across containers: {len(listing_programs)}")
            except Exception as e:
                report_lines.append(f"- Program container scan: FAILED ({e})\n")
        else:
            try:
                listing_url, listing_programs, _ = scan_program_listing(base, c)
            except Exception as e:
                report_lines.append(f"- Program listing scan: FAILED ({e})\n")
                listing_url, listing_programs = None, []

            if listing_url:
                report_lines.append(f"- Program listing page: {listing_url}")
                report_lines.append(f"- Programs found on listing page: {len(listing_programs)}")
            else:
                report_lines.append("- Program listing page: not found (no majors/programs-like sidebar link discovered)")

        overrides = dict(own.direct_programs)
        overrides.update(own.entity_programs)

        # Build a department -> college lookup from the directory entity list.
        # This mirrors how the app can map an extracted department back to its college.
        dept_to_college: Dict[str, str] = {}
        for (entity_name, _entity_url, college) in own.entity_pages:
            key = entity_name.strip()
            if key and college:
                dept_to_college[key] = college

        if listing_programs:
            covered = sum(1 for p in listing_programs if p in overrides)
            uncovered = [p for p in listing_programs if p not in overrides]
            report_lines.append(f"- Listing programs covered by directory mapping: {covered}/{len(listing_programs)} ({(covered/len(listing_programs)*100.0):.1f}%)")
            if uncovered:
                report_lines.append(f"- Uncovered examples (first 5):")
                for u in uncovered[:5]:
                    report_lines.append(f"  - {u}")

            # Program-page fallback coverage (mirrors the app’s behavior).
            # Only compute in FULL mode to avoid surprising extra network traffic.
            if args.full and uncovered:
                inferred = 0
                still_unmapped: List[str] = []
                for u in uncovered:
                    try:
                        html_text = fetch(u)
                    except Exception:
                        still_unmapped.append(u)
                        continue

                    dept = extract_department_from_program_page(html_text)
                    if dept:
                        inferred += 1
                        # (Optional) we could also infer college here via dept_to_college,
                        # but for coverage we only need to know we got a dept.
                    else:
                        still_unmapped.append(u)
                    time.sleep(0.02)

                covered_with_fallback = covered + inferred
                report_lines.append(
                    f"- Listing programs covered by directory OR program-page fallback: {covered_with_fallback}/{len(listing_programs)} ({(covered_with_fallback/len(listing_programs)*100.0):.1f}%)"
                )
                if still_unmapped:
                    report_lines.append("- Still unmapped after fallback (first 5):")
                    for u in still_unmapped[:5]:
                        report_lines.append(f"  - {u}")

        # Requirements checks
        if listing_programs:
            if args.full:
                req_stats = audit_requirements(listing_programs, max_programs=max_programs)
                report_lines.append("- Requirements audit:")
                report_lines.append(f"  - program pages fetched: {req_stats['program_pages_fetched']}/{req_stats['programs_considered']} (failures={req_stats['program_page_failures']})")
                report_lines.append(f"  - pages with requirement markers: {req_stats['pages_with_requirement_markers']}/{req_stats['program_pages_fetched']}")
                report_lines.append(f"  - pages with any course-code patterns: {req_stats['pages_with_any_course_codes']}/{req_stats['program_pages_fetched']}")
                report_lines.append(f"  - pages with acalog course list items: {req_stats['pages_with_acalog_course_list_items']}/{req_stats['program_pages_fetched']}")
            else:
                req_stats = sample_requirements(listing_programs, sample_n=20)
                report_lines.append("- Requirements sampling (first 20 programs):")
                report_lines.append(f"  - pages with requirement markers: {req_stats['pages_with_requirement_markers']}/{req_stats['sampled']}")
                report_lines.append(f"  - pages with any course-code patterns: {req_stats['pages_with_any_course_codes']}/{req_stats['sampled']}")

        # Courses section checks
        try:
            if args.full:
                course_stats = audit_courses_full(base, c, max_previews=max_course_previews, max_workers=max(1, args.course_workers))
                if course_stats.get("found_course_sidebar_link") != 1:
                    report_lines.append("- Courses section: no Course Descriptions/Courses sidebar link found\n")
                else:
                    report_lines.append("- Courses section audit:")
                    report_lines.append(f"  - course descriptions pages detected: {course_stats.get('course_descriptions_pages', 1)}")
                    report_lines.append(f"  - preview URLs discovered: {course_stats.get('course_preview_urls_discovered', 0)}")
                    report_lines.append(f"  - preview pages fetched: {course_stats.get('course_preview_pages_fetched', 0)} (failures={course_stats.get('course_preview_page_failures', 0)})")
                    report_lines.append(f"  - previews with title marker: {course_stats.get('course_preview_with_title', 0)}")
                    report_lines.append(f"  - previews with credits marker: {course_stats.get('course_preview_with_credits', 0)}")
                    report_lines.append(f"  - previews with description-ish content: {course_stats.get('course_preview_with_descriptionish', 0)}\n")
            else:
                course_stats = scan_courses_section(base, c, sample_preview_n=10)
                if course_stats.get("found_course_sidebar_link") != 1:
                    report_lines.append("- Courses section: no Course Descriptions/Courses sidebar link found\n")
                else:
                    report_lines.append("- Courses section sample:")
                    report_lines.append(f"  - preview URLs discovered on first page: {course_stats.get('preview_urls_on_first_page', 0)}")
                    report_lines.append(f"  - sampled preview pages: {course_stats.get('preview_sampled', 0)}")
                    report_lines.append(f"  - samples with title marker: {course_stats.get('preview_samples_with_title', 0)}")
                    report_lines.append(f"  - samples with credits marker: {course_stats.get('preview_samples_with_credits', 0)}")
                    report_lines.append(f"  - samples with description-ish content: {course_stats.get('preview_samples_with_descriptionish', 0)}\n")
        except Exception as e:
            report_lines.append(f"- Courses section scan: FAILED ({e})\n")

    out_path = "UB_SCRAPE_VERIFICATION_REPORT.md"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines).rstrip() + "\n")

    print(f"Wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
