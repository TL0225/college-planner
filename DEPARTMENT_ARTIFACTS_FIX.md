# Department Artifacts Fix - Complete Solution

## Problem Summary
Department names in the dropdown were showing artifacts like:
- "Economics department"
- "Architecture department page"
- "Environment and Sustainability department"

These artifacts were causing:
1. Duplicate department entries
2. Majors not appearing when selecting departments  
3. Large "(Other)" section with improperly grouped departments

## Root Cause
The UB catalog structure creates the issue in multiple ways:
1. **Directory page** (navoid=861): Has "Economics" with College association
2. **Program pages**: Have "Economics department" or "Economics department page" with major links
3. **Data flow issue**: College associations were lost when cleaning department names

## Complete Solution Implemented

### 1. Enhanced Scraper Cleanup (`UniversalCatalogScraper.swift` lines 448-474)
```swift
// Cleans department names before returning:
- Removes " department page"
- Removes " page"
- Removes " department" suffix (unless it's "Department of X")
- Filters out noise like "learn more about the", "program office"
```

### 2. Smart Deduplication (`CoreDataManager.swift` lines 1066-1163)
```swift
// saveDepartments() now:
- Normalizes all department names to find duplicates
- Merges "Economics" + "Economics department" into one entity
- Prefers entries that have College associations
- Deletes stale artifacts containing "department" or "page"
- Logs all cleanup actions for debugging
```

### 3. Enhanced Normalization (`CoreDataManager.swift` lines 1220-1251)
```swift
// normalizeProgramDepartmentKey() strips:
- " department page", " department", " program", " office", " page" suffixes
- "department of " prefix
- Provides consistent keys for deduplication
```

### 4. Fuzzy Matching (`CoreDataManager.swift` lines 1340-1365)
```swift
// saveMajors() links majors to departments via:
- Exact normalized match first
- Fuzzy substring matching as fallback
- Handles variations like "English Department" → "English" entity
```

### 5. College Association Fix (`AcademicIdentityView.swift` lines 944-955)
**NEWLY ADDED:** Preserves college associations when cleaning department names
```swift
// Before: compared cleaned names against original names (mismatch!)
// After: cleans BOTH sides before comparison to preserve college links
```

### 6. UI-Level Filtering (`AcademicIdentityView.swift` lines 69-92)
**NEWLY ADDED:** Final safeguard to filter out any remaining artifacts
```swift
// Filters out groups with:
- "department page" in group name
- "learn more" in group name  
- Empty department lists
```

## Files Modified
1. ✅ `UniversalCatalogScraper.swift` - Final cleanup before returning (already had this)
2. ✅ `CoreDataManager.swift` - Enhanced normalization and deduplication
3. ✅ `AcademicIdentityView.swift` - Fixed college association preservation + UI filtering

## Testing Instructions

### Step 1: Complete Reset
```bash
cd /Users/timothy/Desktop/College
./reset_database.sh
```

### Step 2: Rebuild and Run
The app has already been rebuilt with all fixes. Just launch it.

### Step 3: Re-scrape UB Catalog
1. Open the College app
2. Search for "University at Buffalo"
3. Select it and wait for automatic catalog download
4. The scraper will:
   - Extract ~362 programs
   - Clean all department names
   - Deduplicate "Economics" + "Economics department"
   - Preserve college associations

### Step 4: Verify Results
Check that:
- ✅ No "department page" or "department" suffixes in dropdown
- ✅ All departments appear under correct Colleges (not "(Other)")
- ✅ Selecting "Economics" shows Economics majors
- ✅ No duplicate departments

## What Should Happen

### Before (With Artifacts):
```
(Other)
├── Economics department
├── Architecture department page
└── ...

College of Arts and Sciences
├── Economics
└── ...
```
**Problem**: "Economics" and "Economics department" are separate entries, majors link to the wrong one

### After (Clean):
```
College of Arts and Sciences
├── Economics (merged, has both College info AND majors)
├── Architecture  
├── English
└── ...

College of Engineering
├── Computer Science
└── ...
```
**Result**: Single "Economics" entry with College association and all majors linked correctly

## If Issues Persist

If you still see artifacts after following the testing instructions:

1. **Check Console Logs**: Look for "[CoreData]" messages showing what's being saved
2. **Verify Scraper Output**: Look for "🌍 UNIVERSAL SCRAPER" logs
3. **Manual Database Inspection**:
   ```bash
   sqlite3 ~/Library/Containers/Timothy.College/Data/Library/Application\ Support/College/CollegeDataModel.sqlite
   SELECT name, school FROM ZDEPARTMENTENTITY;
   .quit
   ```

4. **Try Manual Cleanup**: If artifacts remain in DB, the deduplicate logic should remove them on next scrape

## Technical Notes

- **Normalization**: Strips suffixes/prefixes, lowercases, removes special chars
- **Deduplication**: Groups by normalized key, keeps best entry (has College + clean name)
- **Fuzzy Matching**: Links majors even when department names don't match exactly
- **UI Filtering**: Final safety net to hide any artifacts that slip through

## Expected Behavior

- **Departments from directory** (navoid=861): "Economics" with College
- **Departments from programs**: "Economics department" 
- **After processing**: Single "Economics" entry in database
- **In dropdown**: Shows "Economics" (clean name)
- **Majors**: All link to the single "Economics" entity

The three-layer approach (scraper cleanup → Core Data deduplication → UI filtering) ensures artifacts are eliminated at every stage.
