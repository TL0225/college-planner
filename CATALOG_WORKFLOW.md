# Catalog Workflow Documentation

## Overview
The College Planner app uses a **local-first, automatic web scraping** approach for managing university course catalogs. When a user selects a school, the app **automatically scrapes the school's official catalog website** in real-time to extract all courses, prerequisites, and descriptions.

## Complete Workflow

### 1. **User Selects School** (Profile Settings → Academic Identity)
- User clicks "Load schools" button → fetches list from GitHub (`manifests/schools.json`)
- User types school name → autocomplete shows matching universities
- User clicks on a school → **Automatically triggers live web scraping**

### 2. **Automatic Catalog Scraping** (NEW!)
When user selects a school:
```swift
// AcademicIdentityView.swift
private func selectSchool(_ school: SchoolManifest) {
    // 1. Save school name to profile
    profile.collegeName = school.name
    
    // 2. Automatically scrape from the school's actual catalog website
    Task {
        await scrapeAndImportCatalog(school: school)
    }
}
```

**What happens:**
- Connects to school's catalog website (e.g., `https://catalogs.rutgers.edu`)
- Detects catalog system type (Acalog, Banner, Kuali, custom)
- Uses headless browser (WebKit) to render JavaScript
- Executes scraping script to extract all courses
- Parses HTML/DOM for: course codes, titles, descriptions, credits, prerequisites
- Progress shown in UI: "Connecting...", "Scraping courses...", "Found 245 courses", "Importing..."

### 3. **Import into Core Data** (Local Database becomes source of truth)
```swift
// CoreDataManager.swift
func importSchoolCatalog(_ schoolProfile: SchoolProfile) throws {
    // 1. Create/update UniversityEntity
    // 2. Import scraped courses → CourseCatalogEntity
    // 3. Import degree requirements → DegreeRequirementEntity
    // 4. Save all to Core Data
}
```

**Data stored:**
- **UniversityEntity**: School name, catalog URL, last scrape date
- **CourseCatalogEntity**: Course code, title, description, credits, prerequisites (parsed from website)
- **DegreeRequirementEntity**: Degree type, major, category, required courses

### 4. **Major/Minor Pickers Auto-Populate**
After catalog scraping:
- Primary Major dropdown → populated from degree requirements (if available)
- Secondary Major dropdown → same list
- Minor dropdown → same list + "None" option
- Falls back to generic list if degree data not available

### 5. **User Makes Corrections** (All changes saved locally)
User can edit:
- Course descriptions
- Prerequisites
- Credits
- Any catalog data

**Changes stored in Core Data only** - Original website is not modified.

### 6. **Export Corrections** (Manual contribution to community)
User clicks "Export Catalog Modifications" button:
- Exports Core Data → JSON file
- Can be shared with community or submitted to GitHub

## Data Flow Diagram

```
School Manifest (GitHub)
  ├── manifests/schools.json          [User clicks "Load schools"]
  │     Contains: school names + catalog URLs
  │     ↓
  └── User selects school
        ↓
    WebScraperService (Live Scraping)
        ↓
    School's Official Catalog Website
      (e.g., https://catalogs.rutgers.edu)
        ↓
    Parse HTML/JavaScript → Extract courses
        ↓
    CatalogCourse[] (in-memory)
        ↓
    CoreDataManager.importSchoolCatalog()
        ↓
    Core Data (Local Database - SOURCE OF TRUTH)
        ├── UniversityEntity
        ├── CourseCatalogEntity  (scraped from website)
        ├── DegreeRequirementEntity
        └── ProfileEntity (major/minor selections)
        ↓
    User makes local edits
        ↓
    [Optional] Export button → JSON file → Share with community
```

## Web Scraping Details

### Supported Catalog Systems

1. **Acalog/Digarc** (~300 universities)
   - URL pattern: `catalogs.{school}.edu`
   - Detection: HTML contains `data-content-type="course"`
   - Scraping: JavaScript extracts structured course blocks
   - Example: Rutgers, Cornell, Penn State

2. **Banner/Ellucian** (~200 universities)
   - URL pattern: `{school}.edu/bwckctlg`
   - Detection: HTML contains `banner` or `bwckctlg`
   - Scraping: Table-based parsing
   - Example: Many state universities

3. **Custom HTML** (Fallback)
   - Regex pattern matching for course codes
   - Generic parser: looks for "DEPT 123" patterns
   - Less accurate but works for basic catalogs

## Key Design Principles

### 1. **Local-First**
- All data stored in Core Data after initial download
- No background sync or automatic updates
- Works completely offline after catalog download

### 2. **Manual-Only Sync**
- User clicks "Load schools" to fetch university list
- Catalog auto-downloads when school is selected
- No scheduled background operations
- No API keys or tokens required

### 3. **User Control over Corrections**
- All edits saved locally immediately
- Export is **optional** and **manual**
- User decides when/if to share corrections
- Privacy-first: no telemetry, no analytics

### 4. **GitHub as Static Host**
- No GitHub API required for reading
- Uses `raw.githubusercontent.com` direct URLs
- Fallback to `github.com/.../raw/...` if DNS blocked
- Contributions via pull requests (not programmatic)

## File Locations

### GitHub Repository Structure
```
college-planner-data/
├── manifests/
│   └── schools.json           # List of all universities
├── profiles/
│   ├── rutgers_nb.json        # Full catalog for Rutgers
│   └── stony_brook.json       # Full catalog for Stony Brook
└── recipes/
    └── acalog_scraper.json    # (Future: scraper configs)
```

### Core Data Entities
- `ProfileEntity`: User profile (name, major, minor, GPA, school)
- `UniversityEntity`: School info (name, catalog URL, last sync)
- `CourseCatalogEntity`: Course details (code, title, prereqs, credits)
- `DegreeRequirementEntity`: Major requirements (courses, credits, categories)
- `SemesterEntity`: User's plan (semesters + courses)
- `CourseEntity`: Enrolled courses (grade, status, semester)

### Key Source Files
- `GitHubDataService.swift`: Network layer for GitHub fetching
- `CoreDataManager.swift`: Import/export + Core Data operations
- `AcademicIdentityView.swift`: UI for school selection + major/minor
- `CatalogModels.swift`: Codable structs for JSON parsing
- `CollegeDataModel.xcdatamodeld`: Core Data schema

## Example: Complete User Journey

1. **First Time Setup**
   - User opens app → navigates to Profile Settings
   - Clicks "Load schools" → sees "250 schools" loaded
   - Types "Rutgers" → autocomplete shows matches
   - Selects "Rutgers University - New Brunswick"
   - Sees: "Downloading catalog... Importing 245 courses... ✓ Success"

2. **Select Major**
   - Primary Major dropdown now shows: "Computer Science", "Biology", "Psychology", etc.
   - User selects "Computer Science"
   - Saved to `ProfileEntity.major`

3. **User Notices Error**
   - CS 112 has wrong prerequisite (should be CS 111)
   - User navigates to course catalog (future feature)
   - Edits prerequisite field
   - Change saved to `CourseCatalogEntity` in Core Data

4. **Export Corrections**
   - User clicks "Export Catalog Modifications"
   - File exported: `rutgers_nb_export_1735059234.json`
   - Finder opens showing file
   - User uploads to GitHub fork and creates PR

## Privacy & Offline Support

### What Works Offline
- ✅ View all downloaded courses
- ✅ Search catalog
- ✅ Edit course info
- ✅ Plan semesters
- ✅ Track degree progress
- ✅ Export corrections

### What Requires Internet
- ❌ "Load schools" button
- ❌ Downloading new school catalogs
- ❌ Submitting corrections to GitHub

### No Data Collection
- No analytics
- No crash reporting
- No user tracking
- No API tokens stored
- All data stays on device

## Future Enhancements

### Planned Features
1. **Prerequisite Validation**: Warn if adding course without prereqs
2. **Degree Progress Tracker**: Show completion % for selected major
3. **Course Search**: Filter by department, credits, term offered
4. **Conflict Detection**: Check for time conflicts in calendar
5. **Diff Viewer**: Show what changed since last GitHub sync

### NOT Planned (Privacy/Simplicity)
- ❌ Automatic background sync
- ❌ Push notifications
- ❌ Cloud backup
- ❌ Social features
- ❌ AI/ML recommendations
- ❌ User accounts/authentication

## Troubleshooting

### "Couldn't load schools"
- **Cause**: Network error or GitHub unreachable
- **Fix**: Check internet connection, try again
- **Fallback**: Manually type school name (partial catalog)

### "Failed to download catalog"
- **Cause**: School profile not yet added to GitHub
- **Fix**: Request school addition via GitHub issue
- **Workaround**: Manually create courses in app

### Major dropdown empty
- **Cause**: Catalog not downloaded yet
- **Fix**: Select school from autocomplete again
- **Fallback**: Uses generic major list

### Export fails
- **Cause**: No catalog data in Core Data for selected school
- **Fix**: Download catalog first by selecting school

## Technical Notes

### JSON Schema (SchoolProfile)
```json
{
  "school_id": "rutgers_nb",
  "school_name": "Rutgers University - New Brunswick",
  "catalog_url": "https://catalogs.rutgers.edu",
  "version": "1.0.0",
  "last_updated": "2024-12-24T12:00:00Z",
  "courses": [
    {
      "course_code": "CS 111",
      "title": "Intro to Computer Science",
      "description": "...",
      "credits": 4,
      "prerequisites": {
        "type": "course",
        "course": {"course_code": "MATH 135"}
      }
    }
  ],
  "degree_requirements": [
    {
      "degree_type": "Bachelor of Science",
      "major": "Computer Science",
      "category": "Core",
      "required_courses": ["CS 111", "CS 112"],
      "credits_required": 120
    }
  ],
  "policies": {
    "transfer_credit_limit": 90,
    "max_credits_per_semester": 19
  }
}
```

### Prerequisite Rules (Recursive)
```swift
enum PrerequisiteRule {
    case course(CourseRequirement)         // Single course
    case and([PrerequisiteRule])           // All required
    case or([PrerequisiteRule])            // Any one required
}
```

Example:
```json
{
  "type": "and",
  "rules": [
    {"type": "course", "course": {"course_code": "CS 111"}},
    {
      "type": "or",
      "rules": [
        {"type": "course", "course": {"course_code": "MATH 135"}},
        {"type": "course", "course": {"course_code": "MATH 151"}}
      ]
    }
  ]
}
```
Means: CS 111 AND (MATH 135 OR MATH 151)

---

**Last Updated**: December 24, 2024
**Version**: 1.0.0
**App**: College Planner (macOS)
