# Course Catalog System - Implementation Guide

## 🎉 System Overview

Your College Planner app now includes a comprehensive, **local-first, zero-cost** course catalog system that automatically imports university data. This document explains how everything works.

---

## 🏗️ Architecture

### **Core Components**

1. **Core Data Model** (`CollegeDataModel.xcdatamodeld`)
   - `UniversityEntity` - University information
   - `CourseCatalogEntity` - Course catalog (read-only reference data)
   - `DegreeRequirementEntity` - Graduation requirements per major
   - `CourseEntity` - Student's planned/completed courses (links to catalog)

2. **Data Services**
   - `GitHubDataService` - Fetches school profiles from GitHub (manual only)
   - `WebScraperService` - Scrapes university websites using WKWebView
   - `PrerequisiteValidator` - Validates course prerequisites
   - `GraduationValidator` - Checks graduation readiness

3. **User Interface**
   - `UniversitySearchView` - Search and download school catalogs
   - `CourseSearchView` - Search catalog when adding courses
   - `ErrorReportView` - Report incorrect policies to community

---

## 🚀 User Experience Flow

### **Step 1: University Setup**
```
User opens app → UniversitySearchView appears
User types "Rutgers" → Autocomplete shows results
User clicks school → Downloads catalog (5-10 seconds)
Result: 1,000+ courses stored locally in Core Data
```

### **Step 2: Adding Courses**
```
User clicks "Add Course" → CourseSearchView opens
User types "CS 101" → Shows catalog results with:
  ✓ Full course description
  ✓ Prerequisite requirements
  ✓ Credits and department info
User clicks "+ Add" → Course added to semester
```

### **Step 3: Prerequisite Checking**
```
As user plans courses, system checks:
  - Are prerequisites met?
  - What grade is required?
  - AND/OR logic (CS 101 OR CS 102)
  
Blocked courses show red warning
Available courses show green checkmark
```

### **Step 4: Graduation Validation**
```
System continuously tracks:
  - Credits completed vs required
  - Major requirements satisfaction
  - Policy violations (transfer limits, etc.)
  - Overall graduation progress %
  
Red card appears if policy violated
```

### **Step 5: Community Corrections**
```
If student finds error:
  1. Clicks "Report Error"
  2. Fills correction form
  3. Fixes locally (instant)
  4. Optionally submits to GitHub
  5. Other students get fixed data
```

---

## 🔧 Technical Implementation

### **GitHub Data Structure**

Your GitHub repo should have this structure:

```
university-data/
├── manifests/
│   └── schools.json          # List of all schools
├── profiles/
│   ├── rutgers_nb.json       # Rutgers course data
│   ├── stanford.json         # Stanford course data
│   └── ...
└── recipes/
    ├── acalog_scraper.json   # Scraper for Acalog sites
    └── banner_scraper.json   # Scraper for Banner sites
```

### **Sample `schools.json`**

```json
[
  {
    "id": "rutgers_nb",
    "name": "Rutgers University - New Brunswick",
    "short_name": "Rutgers",
    "profile_url": "https://raw.githubusercontent.com/your-org/university-data/main/profiles/rutgers_nb.json",
    "catalog_format": "acalog",
    "last_updated": "2025-12-15T00:00:00Z",
    "courses_count": 1247,
    "verified": true
  }
]
```

### **Sample `rutgers_nb.json`**

```json
{
  "school_id": "rutgers_nb",
  "school_name": "Rutgers University - New Brunswick",
  "catalog_url": "https://catalog.rutgers.edu",
  "version": "2025-2026",
  "last_updated": "2025-12-15T00:00:00Z",
  "courses": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "course_code": "CS 101",
      "title": "Introduction to Computer Science",
      "description": "Fundamentals of programming...",
      "credits": 3,
      "department": "Computer Science",
      "prerequisites": {
        "type": "or",
        "rules": [
          {
            "type": "course",
            "course": {
              "course_code": "MATH 110",
              "min_grade": "C"
            }
          },
          {
            "type": "course",
            "course": {
              "course_code": "MATH 115"
            }
          }
        ]
      },
      "typically_offered": ["Fall", "Spring"]
    }
  ],
  "degree_requirements": [
    {
      "id": "650e8400-e29b-41d4-a716-446655440001",
      "degree_type": "Bachelor of Science",
      "major": "Computer Science",
      "category": "Core Requirements",
      "required_courses": ["CS 101", "CS 102", "CS 201"],
      "credits_required": 36,
      "description": "All CS majors must complete core courses"
    }
  ],
  "policies": {
    "transfer_credit_limit": 60,
    "minor_transfer_limit": 6,
    "max_credits_per_semester": 18,
    "min_credits_full_time": 12,
    "grade_for_credit": "D"
  }
}
```

---

## 🔨 Setup Instructions

### **1. Create GitHub Repository**

```bash
# Create new public repo
gh repo create your-org/university-data --public

# Clone it
git clone https://github.com/your-org/university-data.git
cd university-data

# Create structure
mkdir -p manifests profiles recipes
touch manifests/schools.json
```

### **2. Update GitHub URLs in Code**

In `GitHubDataService.swift`, update:
```swift
private let repoOwner = "your-org"  // Change this
private let repoName = "university-data"
```

### **3. Scrape Your First University**

```swift
// In a test or setup script:
let scraper = WebScraperService()
let courses = try await scraper.scrapeAcalog(url: "https://catalog.rutgers.edu")

// Convert to JSON and save to profiles/rutgers_nb.json
```

### **4. Test the Flow**

1. Run the app
2. `UniversitySearchView` should appear
3. Click "Load University List" (fetches from GitHub)
4. Search for your school
5. Click to download
6. Verify courses are in Core Data

---

## 📊 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ USER CLICKS "Rutgers"                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ GitHubDataService.downloadSchoolProfile("rutgers_nb")       │
│ → Fetches rutgers_nb.json from GitHub                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Parse JSON → Create Core Data Entities                      │
│ • UniversityEntity (Rutgers)                                │
│ • 1,247 CourseCatalogEntity objects                         │
│ • 15 DegreeRequirementEntity objects                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ CoreDataManager.saveContext()                               │
│ → All data saved locally, works offline forever             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testing Checklist

- [ ] Load schools list from GitHub
- [ ] Search and download a university
- [ ] Verify courses appear in Core Data
- [ ] Search for a course in CourseSearchView
- [ ] Add course and check it links to catalog
- [ ] Verify prerequisite validation works
- [ ] Check graduation progress calculator
- [ ] Test error reporting submission
- [ ] Confirm everything works offline after download

---

## 🚨 Important Notes

### **Legal & Ethical**
- Respect university `robots.txt` files
- Add delays between scraping requests (5+ seconds)
- Only scrape when user explicitly requests
- Include attribution: "Course data © University Name"

### **Performance**
- Cache schools.json for 7 days
- Only download when user clicks school
- Store everything in Core Data for instant access
- No background syncing or tracking

### **Data Quality**
- Start with 5-10 manually verified schools
- Add confidence scores to parsed data
- Allow users to fix errors locally
- Community corrections improve data over time

---

## 🎯 Next Steps

1. **Populate Initial Schools**
   - Manually scrape 10-20 popular universities
   - Verify data accuracy
   - Upload to GitHub

2. **Test with Real Users**
   - Beta test with students from different schools
   - Collect feedback on data accuracy
   - Fix common parsing errors

3. **Build Scraper Library**
   - Create recipes for common catalog formats
   - Document scraping patterns
   - Open source for community contributions

4. **Add Advanced Features**
   - Course recommendation engine
   - Schedule optimizer
   - Degree path planner

---

## 🤝 Contributing

To add a new university:
1. Fork the `university-data` repo
2. Scrape the university's catalog
3. Create `profiles/school_id.json`
4. Update `manifests/schools.json`
5. Submit Pull Request

---

## 📝 Example Usage

```swift
// Search for courses
let results = coreDataManager.searchCatalogCourses(query: "Computer Science")

// Check prerequisites
if let cs201 = coreDataManager.getCatalogCourse(code: "CS 201") {
    let status = coreDataManager.checkPrerequisites(for: cs201, plan: myPlan)
    if status.met {
        print("✅ Ready to take CS 201")
    } else {
        print("❌ Missing: \(status.missingCourses.joined(separator: ", "))")
    }
}

// Check graduation status
if let status = coreDataManager.getGraduationStatus(for: myPlan) {
    print("Progress: \(status.overallProgress * 100)%")
    print("Violations: \(status.violations.count)")
}
```

---

## 💡 Key Benefits

✅ **Free** - No API costs, no servers  
✅ **Private** - All data local, no tracking  
✅ **Offline** - Works without internet after download  
✅ **Universal** - Works with any university  
✅ **Community-Driven** - Users fix errors for everyone  
✅ **Smart** - AI-quality parsing with local tools  

---

**Built with ❤️ for students who deserve better planning tools.**
