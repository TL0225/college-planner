# Core Data Migration Guide

## Overview
Your College app has been converted from using in-memory structs to a relational database using Core Data. This provides:
- **Persistent storage**: Data survives app restarts
- **Relational data**: Semesters automatically track their courses
- **Automatic updates**: Changes to courses update semester totals automatically
- **Scalability**: Can handle large amounts of data efficiently

## What Changed

### 1. Data Model (Core Data Schema)
**File**: `CollegeDataModel.xcdatamodeld/CollegeDataModel.xcdatamodel/contents`

Two entities were created:

#### SemesterEntity
- `id`: UUID (unique identifier)
- `name`: String (e.g., "Fall 2025")
- `year`: Int16 (2025, 2026, etc.)
- `season`: String ("Fall", "Winter", "Spring", "Summer")
- `seasonOrder`: Int16 (for sorting: Fall=0, Winter=1, Spring=2, Summer=3)
- `isPlanned`: Boolean (true for planned, false for completed)
- **Relationship**: `courses` (one-to-many with CourseEntity)

#### CourseEntity
- `id`: UUID (unique identifier)
- `code`: String (e.g., "CS 1110")
- `name`: String (course name)
- `credits`: Int16 (credit hours)
- `status`: String ("Planned", "In Progress", "Completed")
- `gradingType`: String ("Letter Grade", "Pass/Fail", "Audit")
- `professor`: String? (optional)
- `isCompleted`: Boolean (auto-set based on status)
- `grade`: String? (optional, for completed courses)
- `syllabusFileName`: String? (optional, for uploaded files)
- **Relationship**: `semester` (many-to-one with SemesterEntity)

### 2. Core Data Manager
**File**: `CoreDataManager.swift`

This is the central controller for all database operations:

#### Key Methods:
```swift
// Semester Operations
func fetchSemesters() // Loads all semesters from database
func addSemester(name: String, year: Int, season: String) -> SemesterEntity
func deleteSemester(_ semester: SemesterEntity)
func updateSemester(_ semester: SemesterEntity)

// Course Operations
func addCourse(to semester: SemesterEntity, code: String, name: String, ...) -> CourseEntity
func deleteCourse(_ course: CourseEntity)
func updateCourse(_ course: CourseEntity)
```

The manager is a singleton (`CoreDataManager.shared`) and is injected as an `@EnvironmentObject` throughout the app.

### 3. View Updates

#### CollegeApp.swift
- Removed `import SwiftData`
- Added `@StateObject private var coreDataManager = CoreDataManager.shared`
- Injects `coreDataManager` as environment object

#### DegreeView.swift
- Changed from `@StateObject SemesterManager` to `@EnvironmentObject CoreDataManager`
- Changed `selectedSemesterName: String` to `selectedSemester: SemesterEntity?`
- All semester/course data now comes from Core Data entities

#### AddSemesterView.swift
- Uses `@EnvironmentObject CoreDataManager`
- Create button calls `coreDataManager.addSemester(...)`
- Data automatically persists to database

#### AddCourseView.swift
- Changed from `var semesterName: String` to `@ObservedObject var semester: SemesterEntity`
- Create button calls `coreDataManager.addCourse(...)`
- Validates required fields before saving
- Automatically links course to the selected semester

#### SemesterCard & CourseCard
- Changed from structs (`Course`, `Semester`) to Core Data entities (`CourseEntity`, `SemesterEntity`)
- Use `@ObservedObject` for automatic UI updates when data changes
- Safe unwrapping of optional Core Data properties (e.g., `semester.name ?? "Unknown"`)

## How Relationships Work

### One-to-Many (Semester → Courses)
```swift
// A semester can have multiple courses
let semester = coreDataManager.addSemester(name: "Fall 2025", year: 2025, season: "Fall")

// Add courses to the semester
let course1 = coreDataManager.addCourse(to: semester, code: "CS 1110", ...)
let course2 = coreDataManager.addCourse(to: semester, code: "MATH 221", ...)

// Access all courses in a semester
let allCourses = semester.coursesArray // Returns [CourseEntity]
```

### Automatic Updates
When you add/remove/update a course:
1. Core Data automatically updates the semester's `courses` relationship
2. The `@ObservedObject` wrapper detects the change
3. SwiftUI automatically refreshes the UI
4. Computed properties like `totalCredits` and `progress` recalculate

### Cascade Deletion
If you delete a semester, all its courses are automatically deleted (defined in the Core Data model).

## Next Steps

### 1. Add Core Data Files to Xcode
The following files need to be added to your Xcode project:
- `CoreDataManager.swift`
- `CollegeDataModel.xcdatamodeld` folder

**How to add them:**
1. Xcode should now be open (I opened it for you)
2. Right-click on the "College" folder in the Project Navigator
3. Select "Add Files to College..."
4. Navigate to and select:
   - `CoreDataManager.swift`
   - `CollegeDataModel.xcdatamodeld`
5. Make sure "Copy items if needed" is checked
6. Click "Add"

### 2. Build and Test
```bash
cd /Users/timothy/Desktop/College
xcodebuild clean build -scheme College
```

### 3. Verify Data Persistence
1. Run the app
2. Create a semester and add courses
3. Quit the app completely
4. Relaunch the app
5. Your data should still be there!

## Benefits of This Architecture

### 1. **Data Persistence**
- All data is saved to disk automatically
- Survives app restarts and updates

### 2. **Relational Integrity**
- Courses are always linked to their semester
- Deleting a semester removes its courses
- No orphaned data

### 3. **Automatic UI Updates**
- Change a course status → semester progress updates automatically
- Add a course → semester credit count updates automatically
- Delete a course → UI refreshes automatically

### 4. **Performance**
- Core Data is optimized for large datasets
- Lazy loading prevents loading unnecessary data
- Efficient sorting and filtering with predicates

### 5. **Future Extensibility**
You can easily add:
- Search functionality
- Filtering by status/season/year
- GPA calculations
- Degree requirements tracking
- Export to PDF/CSV
- Cloud sync (via CloudKit)
- Undo/Redo functionality

## Common Operations

### Create a Semester
```swift
coreDataManager.addSemester(name: "Spring 2026", year: 2026, season: "Spring")
```

### Create a Course
```swift
coreDataManager.addCourse(
    to: semester,
    code: "CS 2110",
    name: "Object-Oriented Programming",
    credits: 4,
    status: "Planned",
    gradingType: "Letter Grade",
    professor: "Dr. Smith"
)
```

### Update a Course
```swift
course.status = "Completed"
course.grade = "A"
coreDataManager.updateCourse(course)
```

### Delete a Course
```swift
coreDataManager.deleteCourse(course)
```

### Delete a Semester (and all its courses)
```swift
coreDataManager.deleteSemester(semester)
```

### Query Semesters
```swift
// All semesters (sorted by year and season)
let allSemesters = coreDataManager.semesters

// Filter semesters
let plannedSemesters = coreDataManager.semesters.filter { $0.isPlanned }
let completedSemesters = coreDataManager.semesters.filter { !$0.isPlanned }
```

## Troubleshooting

### "Cannot find type 'SemesterEntity'"
The Core Data model file needs to be added to Xcode. Follow step 1 in "Next Steps".

### Data not persisting
Make sure `coreDataManager.save()` is being called. It's automatically called in all CRUD operations.

### UI not updating
Ensure you're using `@ObservedObject` for Core Data entities and `@EnvironmentObject` for CoreDataManager.

### Migration from old data
The old `mockSemesters` data is still in Models.swift but is no longer used. You can:
1. Manually recreate important data through the UI
2. Or write a migration script to import it into Core Data

## Files Modified

- ✅ `CollegeApp.swift` - Added CoreDataManager
- ✅ `DegreeView.swift` - Uses Core Data entities
- ✅ `AddSemesterView.swift` - Saves to Core Data
- ✅ `AddCourseView.swift` - Saves to Core Data
- ✅ `CoreDataManager.swift` - NEW: Database controller
- ✅ `CollegeDataModel.xcdatamodeld` - NEW: Data schema

## Files to Keep (Unchanged)

- `Models.swift` - Keep for `AppPage` enum and any other utilities
- All other view files work as before
