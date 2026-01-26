# End-to-end: What the current scraper does (plain English)

This document explains what the app’s **current catalog scraper** is doing from start to finish, in non-technical terms.

It is based on the code in the app (primarily `UniversalCatalogScraper` and `ModernCampusEngine`) and describes the real order of operations.

---

## What problem it’s solving

College catalogs (especially Modern Campus / Acalog catalogs) spread information across different pages:

- A **sidebar navigation** with links like “Majors”, “Minors”, “Programs”, “Departments”, “Courses”, etc.
- A **program page** (e.g., “Business Administration BS”) that contains requirements and sometimes ownership info.
- A **courses index** page (often called “Course Descriptions” or just “Courses”) that lists *every course* and links to a detailed course preview.

The scraper is trying to produce, for every program it finds:

- Program name (e.g., “Accounting”)
- Program type (Major / Minor / Certificate / Master’s / Doctorate / etc.)
- Program URL (where that program lives)
- Department + College/School relationship (who “owns” the program)
- Program requirements (what courses are required / selectable)
- Course details inside requirements (fill missing title/credits using the course catalog as backup)

---

## Inputs and outputs (what goes in / what comes out)

**Inputs**

- `baseURL` = the catalog website (example: `https://catalogs.buffalo.edu`)
- `catalogID` (also called `catoid`) = which catalog edition to use (example: Undergrad vs Graduate vs Law, etc.)

**Output**

A list of programs (`ScrapedProgram`) where each program may include:

- `name`, `type`, `url`
- `department`, `college`
- `degreeType` (BS/BA/MS/etc when detectable)
- `requirements` (course requirement groups, if the page provides them)

---

## High-level pipeline (big picture)

Here is the scraper’s full “assembly line”, in order:

```
[Start]
  |
  v
(0) Build Course Catalog Cache (backup course database)
  |
  v
(1) Build Department -> College mapping (general)
  |
  v
(1b) UB-only: Build Program URL -> (Department, College) overrides
  |
  v
(2) Discover container pages from the sidebar (Majors/Minors/Programs/etc)
  |
  v
(3) From each container page, extract program links and infer department/college
  |
  v
(4) For each program link, fetch the program page and parse requirements
  |
  v
(5) Fill missing course titles/credits using the Course Catalog Cache
  |
  v
[Return list of programs + requirements]
```

The key design idea is:

- The scraper first builds a “dictionary” of course details (titles/credits) from the catalog’s Courses section.
- Then, when it scrapes program requirements (which often omit titles/credits), it fills in what’s missing.

---

## Step (0): Build the Course Catalog Cache (backup course database)

**Goal:** Create a large lookup table like:

- `"CSE 115" -> (title, credits)`
- `"MTH 141" -> (title, credits)`

So later, if a program requirement line only says `CSE 115`, we can still attach the title and credits.

**Flow (with arrows)**

```
[Index page]
  |
  v
Find the sidebar link that looks like:
  - "Course Descriptions" or
  - "Courses"
  |
  v
Open that content page:
  content.php?catoid=...&navoid=...
  |
  v
If it has multiple pages, visit each page (pagination)
  |
  v
From each page, collect the list of course “stubs” (course codes + preview links)
  |
  v
For every course stub:
  fetch its preview page (equivalent to clicking a course row)
  |
  v
Parse course details (code, title, credits, description)
  |
  v
Store into cache, normalized so keys match requirements
```

**Important details (non-technical explanation)**

- Some catalogs show course details only after you “click” the course row. The scraper does the equivalent by building the right preview URL and loading it directly.
- Course codes can have suffixes (example: `AAP 503SEM`). The cache normalizes these down to `AAP 503` so they match how requirements usually reference courses.

### UB example: what “clicking through Courses” really means

On UB’s ModernCampus catalogs, the scraper does **not** run JavaScript. It does this instead:

```
Start: https://catalogs.buffalo.edu/index.php?catoid=19
  |
  v
Read the sidebar links on the index page
  |
  v
Find the link labeled like:
  - "Course Descriptions" or
  - "Courses"
  |
  v
Open that link (typically):
  https://catalogs.buffalo.edu/content.php?catoid=19&navoid=1038
  |
  v
If there are more pages:
  add filter[cpage]=2,3,4,... and repeat
  |
  v
From each page, extract “course rows” and their IDs
  |
  v
For each course row, build a direct preview URL and fetch it:
  https://catalogs.buffalo.edu/preview_course_nopop.php?catoid=19&coid=XXXXX
  |
  v
Parse the preview HTML to get title/credits/description
```

Why this counts as “clicking”:

- On some UB course listing pages, the course title may appear as a normal link.
- On others, it may look like a link that *doesn’t go anywhere* (example: `href="#"`) and relies on an `onclick` handler to open details.
- The scraper reads the `onclick` text, extracts the important IDs (like `coid` + `catoid`), and directly requests the preview page URL.

So in plain terms:

> It behaves like a user clicking every course row, but it does it by directly loading the hidden “preview page” URL rather than executing the click.

---

## Step (1): Build Department → College mapping (general ownership scaffolding)

**Goal:** Build a mapping like:

- Department A belongs to College X
- Department B belongs to College Y

This supports consistent “ownership” labeling even if some pages are messy.

**In simple terms:** it tries to learn the school’s organizational structure.

(Exact strategy varies per catalog, because different schools label these pages differently.)

---

## Step (1b): UB-only ownership overrides (Program URL → Department + College)

This is a special UB-specific improvement because UB catalogs are inconsistent: some program pages don’t clearly state ownership.

**Goal:** From UB’s “Department/Program” (or “Departments & Programs”) directory pages, build a very direct map:

- Program URL → (Department, College)

**Why this matters:** Once you have this map, ownership is deterministic even when the program page is vague.

**How it works (arrows)**

```
[UB index.php sidebar]
  |
  v
Pick the best "department" directory link:
  - "Departments & Programs" OR
  - "Department/Program" OR similar
  |
  v
Open that directory page
  |
  v
Walk the page top-to-bottom:
  - when we see a College/School header, remember it
  - when we see a Department header, remember it
  |
  v
For each program link under that header:
  preview_program.php?...  -->  store mapping
          |
          v
  Program URL  -> (Department, College)
```

**UB directory page patterns supported**

- “Grad-style” pages that use:
  - `h3` = College/School
  - `h4` = Department
  - program links directly underneath

- “Old-style” pages that link to intermediate “entity” pages:
  - The directory page links to a department entity page
  - The entity page then lists programs

So the scraper handles both:

```
(grad-style)
College (h3)
  -> Department (h4)
       -> preview_program links

(old-style)
College (h2/h3)
  -> preview_entity link
       -> (fetch entity page)
            -> preview_program links
```

### UB example: how it finds program ↔ department/college relationships

This is where UB differs from many schools: UB provides a directory page that already contains the “truth” about ownership because programs are listed *under* a college/department heading.

For example, in the UB Graduate catalog:

```
Start: https://catalogs.buffalo.edu/index.php?catoid=19
  |
  v
Read sidebar links and choose the best match containing "department"
  |
  v
Often ends up at something like:
  https://catalogs.buffalo.edu/content.php?catoid=19&navoid=1040   (label: "Department/Program")
  |
  v
Scan the page top-to-bottom:
  - when we hit <h3> … treat as College/School
  - when we hit <h4> … treat as Department
  |
  v
When we see a program link:
  preview_program.php?catoid=19&poid=....&returnto=1040
  |
  v
Store an override:
  Program URL  -> (Department, College)
```

Two very important “specifics”:

1) Yes — it is explicitly scanning for `preview_program.php` links.
2) It canonicalizes and normalizes program URLs so they match later:
   - Removes noisy query items like `returnto=...` so the same program isn’t treated as multiple different URLs.
   - Normalizes the host to the current base host (important because UB can appear under different but equivalent hosts).

---

## Step (2): Discover “container pages” in the sidebar

A “container page” is just a page that lists many programs.

Examples of container pages a catalog might have:

- Majors
- Minors
- Programs
- Degrees
- Certificates

**What the scraper does:**

- It opens the catalog index (`index.php?catoid=...`).
- It reads the sidebar links.
- It picks the links that look like they contain lists of programs.

**Arrow view**

```
index.php?catoid=...
  |
  v
Read sidebar links
  |
  v
Choose likely “program listing” pages
  |
  v
Return list of pages to scan
```

If it fails to identify any “best” container pages, it falls back to scanning many sidebar pages that look relevant.

### UB example: yes, it starts with the sidebar

For UB (and most ModernCampus catalogs), the index page sidebar is the “table of contents.” The scraper always begins by reading it.

In practical terms it is looking for links that usually resolve to:

- `content.php?catoid=...&navoid=...` (listing pages)

Those listing pages are the “containers” it will scan for programs.

---

## Step (3): Scrape each container page to find programs and tentative ownership

For every container page discovered in Step (2), the scraper:

1) Downloads the page
2) Focuses on the *main content area* (to avoid accidentally scraping links from the sidebar)
3) Walks through the HTML in reading order
4) Extracts every program link (`preview_program.php?...`)

While doing that, it tries to infer a program’s organization (college/department) based on nearby headings.

**Arrow view**

```
[Container page]
  |
  v
Scan headings + links in order
  |
  +--> If heading looks like a College/School: set current college
  |
  +--> If heading looks like a Department: set current department
  |
  v
When a program link appears:
  create program record using current college/department context

### UB example: what it extracts from a container page

On a UB container page, program links usually look like:

- `preview_program.php?catoid=19&poid=7375&returnto=1040`

The scraper:

1) Finds those `preview_program.php` links.
2) Forces `catoid` to match the catalog it’s currently scraping (so links can’t “accidentally” point to the wrong UB catalog).
3) Removes `returnto` and other noise so it has one stable program URL.
4) Uses headings near the link to guess college/department, then overrides that guess with UB’s directory-derived mapping when available.
```

**If ownership is still missing**

If the scraper still can’t confidently assign department/college at this point, it will:

- Try UB overrides (Step 1b map), and if that doesn’t exist or match,
- As a last resort, open the program page and attempt to read department/college from the program’s own text.

---

## Step (4): For each program, open the program page and scrape requirements

Once the scraper has a set of programs and URLs, it tries to scrape requirements from each program page.

It does this in small batches (to be respectful and not overload the server).

**Arrow view**

```
[Program URL]
  |
  v
Download program HTML
  |
  v
Find the requirements area (Course Requirements / Major Requirements / etc.)
  |
  v
Split requirements into categories using headings
  |
  v
Extract courses from lists (required courses, select-from lists)
  |
  v
Return DegreeRequirement groups
```

### What counts as “the requirements section”

Program pages contain a lot of content: descriptions, outcomes, admissions, etc.

The scraper looks for headings that mean “requirements begin here,” including common phrases like:

- “Requirements”
- “Course Requirements”
- “Program Requirements”
- “Curriculum”
- “Required Core (… credits)”
- “Additional Requirements (… credits)”

It also stops if it reaches sections that are typically *not* requirements (like “Learning Outcomes”).

### Extracting courses from requirement text

Within a requirements section, the scraper tries to identify course codes like:

- `CSE 115`
- `MTH 141`

It intentionally avoids many false positives (random words that look like courses).

When it finds a course reference, it also tries to capture:

- Title (if present)
- Credits (if present)

Often, program pages list only the course codes and omit titles/credits — that is why the cache in Step (0) exists.

### UB example: program requirements pages are `preview_program.php`

For UB, the program “detail page” is typically the `preview_program.php?...` URL itself.

So the requirements scraping step is literally:

```
Program URL (preview_program.php)
  |
  v
Download HTML
  |
  v
Find the requirements section by reading headings like
  "Required Core (12 credits)" and similar
  |
  v
Extract course codes listed in that section
```

And then immediately after that, it tries to fill in missing course info from the course cache.

---

## Step (5): Fill missing course titles/credits using the Course Catalog Cache

After requirements parsing, each requirement group may contain course entries like:

- `CSE 115` (no title, no credits)

The scraper then “enhances” those using the cache built in Step (0):

**Arrow view**

```
Parsed requirement course: "CSE 115" (missing title/credits)
  |
  v
Look up "CSE 115" in Course Catalog Cache
  |
  +--> If found: fill missing title and/or credits
  |
  +--> If not found: leave as-is
```

This enhancement happens for both:

- Required course lists
- “Select from” course lists

---

## What the scraper tries to “find first” (in plain English)

If you summarize the intent in one sentence:

> It first builds a complete “course dictionary” from the Courses section, then finds all programs via sidebar program lists, then opens each program page to extract requirements, and finally fills missing course details using that course dictionary.

Order matters:

1) Course cache first (so later steps can fill missing details)
2) Program ownership mapping (so programs are grouped correctly)
3) Program discovery from listing pages
4) Requirements parsing from each program page
5) Enhancement (fill-in) using cache

---

## Why “department-to-major relationship” can be tricky (and what the code does about it)

Catalogs don’t always explicitly say:

- “This program belongs to Department X and College Y.”

Instead, they often rely on:

- the program being listed under a department header on a directory page, OR
- the program being listed under a college header with no department, OR
- inconsistent formats across catalogs (undergrad vs grad vs professional schools)

So ownership can come from multiple places, in this priority order:

```
(Highest confidence)
UB ownership overrides from directory pages
  |
  v
Ownership inferred from the listing page hierarchy (headings)
  |
  v
Ownership extracted directly from the program page text
(Lowest confidence)
```

---

## How it avoids being “too aggressive”

The scraper includes practical guardrails:

- It avoids robots-disallowed endpoints (it does not rely on advanced search).
- It fetches requirements in batches (so it doesn’t slam the server).
- It bounds concurrency when crawling the course catalog.

---

## Mental model (one last arrow diagram)

If you want a “one screen” mental model:

```
            +---------------------+
            |  Catalog index.php  |
            |  (sidebar links)    |
            +----------+----------+
                       |
                       v
        +--------------+----------------+
        | Discover listing pages         |
        | (Majors/Minors/Programs/etc)  |
        +--------------+----------------+
                       |
                       v
      +----------------+-------------------+
      | Extract program links + ownership  |
      | (headings + UB overrides)          |
      +----------------+-------------------+
                       |
                       v
      +----------------+-------------------+
      | Fetch each program page            |
      | -> parse requirements categories   |
      | -> parse course codes              |
      +----------------+-------------------+
                       |
                       v
      +----------------+-------------------+
      | Fill missing course details        |
      | using Course Catalog Cache         |
      +----------------+-------------------+
                       |
                       v
                 [Export / UI]

In parallel / earlier:

  +-----------------------------+
  | Course Catalog Cache        |
  | (from Course Descriptions)  |
  +-----------------------------+
```

---

## Where this is implemented (for reference)

- The main pipeline described here is driven by `UniversalCatalogScraper.scrapeAllPrograms(...)`.
- Course cache crawling is done by `ModernCampusEngine.fetchAllCourses(...)` and stored by `UniversalCatalogScraper.buildCourseCatalogCache(...)`.
- UB ownership overrides are built by `UniversalCatalogScraper.buildProgramOwnershipOverridesFromDepartmentEntities(...)`.
- Requirements are scraped by `UniversalCatalogScraper.scrapeProgramRequirements(...)` and then enhanced by `enhanceRequirementsWithCatalogData(...)`.

---

## UB deep dive: answering “is it scanning/clicking X?” (very specific)

You asked (paraphrasing):

> For Program→Department, is it scanning the whole Department/Program page, storing mappings, then clicking through each program (preview_entity.php), extracting preview_program.php links, then clicking preview_program.php to extract requirements, then clicking the `link-open td_dark preview_td` links to get course descriptions?

Here’s the accurate, current behavior.

### 1) Program → Department/College mapping

**Yes:** it scans the entire directory page and stores mappings.

**Sometimes:** it also follows `preview_entity.php` pages (only if the directory uses the older “entity page” structure).

**Flow (UB ownership overrides):**

```
UB index page:
  index.php?catoid=...
    |
    v
Read sidebar links
    |
    v
Choose best directory link containing “department”
  (examples: “Departments & Programs” or “Department/Program”)
    |
    v
Open directory content page:
  content.php?catoid=...&navoid=...
    |
    v
Scan the whole page from top to bottom
    |
    +--> When a College/School header appears (often h3): remember “current college”
    |
    +--> When a Department header appears (often h4): remember “current department”
    |
    v
When a program link appears:
  preview_program.php?catoid=...&poid=...&returnto=...
    |
    v
Store mapping:
  canonicalProgramURL -> (department, college)
```

**What about `preview_entity.php`?**

- **Only some UB catalogs/pages** use entity pages.
- In those cases, the directory page contains links like:

  - `preview_entity.php?catoid=...&ent_oid=...`

  and the scraper will:

  - open each entity page
  - extract `preview_program.php?...` links from it
  - store those programs as belonging to that entity/department and college

So the “entity page clicking” is **conditional**, not always.

### 2) Program pages and requirements (preview_program.php)

**Yes:** after programs are discovered, it fetches each program page (the `preview_program.php?...` page) to extract requirements.

**What it extracts from preview_program pages:**

- Requirement section headings (e.g., “Required Core (12 credits)”, “Program Requirements”)
- Course codes found in requirement lists/text (e.g., `CSE 115`)
- Any titles/credits that happen to be written inline next to the code

**Important:** the requirements scraper is primarily a “read the page text and lists” parser. It does not depend on interactive clicking.

### 3) Course details (titles/credits/descriptions)

**No:** it does *not* click every course link inside each program page to get descriptions.

Instead, course details are sourced earlier from the catalog’s “Course Descriptions / Courses” section.

**What it actually does:**

```
Course cache build (happens BEFORE program requirements scraping)
  |
  v
Find “Course Descriptions” / “Courses” in the sidebar
  |
  v
Open content.php?catoid=...&navoid=...
  |
  v
Collect all courses across pagination
  |
  v
Fetch each course preview page:
  preview_course_nopop.php?catoid=...&coid=...
  |
  v
Parse description/title/credits and store in a cache keyed by code (e.g., “CSE 115”)
```

Then, when a program requirement contains `CSE 115` but no title/credits:

```
Requirement course “CSE 115” (missing fields)
  |
  v
Look up “CSE 115” in the course cache
  |
  v
Fill missing title/credits from the cache
```

### 4) About those `link-open td_dark preview_td` course rows

Your description sounds like the **Courses listing UI** (where each row looks clickable).

- In some catalogs, those rows are clickable via JavaScript.
- The scraper does **not** literally click the DOM element.
- It instead extracts the underlying IDs and requests the corresponding `preview_course_nopop.php?...` page directly.

So the short answer is:

- **It does “click through” courses, but only in the Courses section crawl**, not by drilling down from each program page.
- **It does not** click every course row/link inside each program page to gather descriptions; it relies on the pre-built course cache.

---

## Quick “Yes / No” checklist (UB)

- Does it look at the sidebar? **Yes** (index sidebar is the starting point for both program discovery and course-cache discovery).
- Does it scan the entire Department/Program directory page? **Yes** (to build program→ownership overrides).
- Does it fetch `preview_entity.php` pages? **Sometimes** (only if the directory uses entity pages).
- Does it scan for `preview_program.php` links? **Yes** (both on container pages and directory/entity pages).
- Does it open each `preview_program.php` to parse requirements? **Yes** (batched/concurrent).
- Does it click course rows inside each program page to get descriptions? **No** (course descriptions come from the Courses/Course Descriptions crawl).
