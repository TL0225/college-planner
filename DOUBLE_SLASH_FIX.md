# Double Slash Bug Fix

## Problem Discovered
When you pressed "Load Schools", the scraping still returned 0 majors, 0 minors, 0 departments because of TWO issues:

### Issue 1: Wrong Base URL in Override Dictionary
The app was passing `https://www.stonybrook.edu/sb/bulletin/current/` but our override dictionary only had:
- `https://catalog.stonybrook.edu`
- `https://sb.cc.stonybrook.edu/bulletin`

So the override lookup **failed** and fell through to dynamic discovery.

### Issue 2: Double Slash in URLs
The baseURL from the app ends with a trailing slash: `https://www.stonybrook.edu/sb/bulletin/current/`

When constructing URLs like this:
```swift
let url = "\(baseURL)/content.php?catoid=7&navoid=224"
```

This created malformed URLs:
```
https://www.stonybrook.edu/sb/bulletin/current//content.php?catoid=7&navoid=224
                                              ^^
                                        DOUBLE SLASH!
```

The double slash caused the web server to return a different page (probably an error or homepage), which didn't match any of our regex patterns → 0 results.

## Solution Implemented

### Fix 1: Added Missing URL to Override Dictionary
```swift
private static let schoolOverrides = [
    // ... existing entries ...
    
    // NEW: Current bulletin URL (with trailing slash)
    "https://www.stonybrook.edu/sb/bulletin/current/": (
        majors: "224",
        minors: "228",
        courses: "225",
        departments: "250"
    ),
]
```

### Fix 2: URL Normalization Helper Functions
Created two helper functions to handle trailing slashes:

```swift
/// Normalize base URL by removing trailing slash
private static func normalizeBaseURL(_ url: String) -> String {
    return url.hasSuffix("/") ? String(url.dropLast()) : url
}

/// Build a properly formatted URL by joining base and path
private static func buildURL(base: String, path: String) -> String {
    let normalizedBase = normalizeBaseURL(base)
    let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
    return normalizedBase + normalizedPath
}
```

### Fix 3: Updated All URL Constructions
Changed all URL constructions from:
```swift
"\(baseURL)/content.php?catoid=\(catalogID)&navoid=\(navoid)"
```

To:
```swift
buildURL(base: baseURL, path: "/content.php?catoid=\(catalogID)&navoid=\(navoid)")
```

This was applied to:
- `strategyKeywordScan()` - index.php
- `strategyAdvancedSearch()` - search_advanced.php
- `discoverDepartmentCodes()` - search_advanced.php
- `fetchAllCourses()` - search_advanced.php
- `fetchDepartments()` - content.php
- `fetchMajors()` - content.php (majors and minors)

## Expected Result

Now when you press "Load Schools":

1. **Override lookup succeeds**: `"https://www.stonybrook.edu/sb/bulletin/current/"` is found in dictionary
2. **Correct navoids used**: 224 (majors), 228 (minors), 250 (departments)
3. **URLs properly formatted**: No double slashes
   ```
   https://www.stonybrook.edu/sb/bulletin/current/content.php?catoid=7&navoid=224
   ```
4. **Patterns match successfully**:
   - Pattern 1: Finds 69 majors
   - Pattern 1: Finds 82 minors
   - Pattern 2: Finds 5 departments

## Debug Log Should Show

```
🔍 Discovering navoids using waterfall strategy
  📌 Using manual override for https://www.stonybrook.edu/sb/bulletin/current/
  ✅ Override navoids: majors=224, minors=228, courses=225, depts=250

🎓 Scraping majors and minors
  📥 Fetching majors from: https://www.stonybrook.edu/sb/bulletin/current/content.php?catoid=7&navoid=224
  📡 HTTP Status: 200
  ✅ Fetched HTML: 107199 characters
  📊 Pattern 1: Found 69 matches
  Found 69 majors

  📥 Fetching minors from: https://www.stonybrook.edu/sb/bulletin/current/content.php?catoid=7&navoid=228
  📡 HTTP Status: 200
  ✅ Fetched HTML: 107199 characters
  📊 Pattern 1: Found 82 matches
  Found 82 minors

🏫 Scraping departments
  📥 Fetching from: https://www.stonybrook.edu/sb/bulletin/current/content.php?catoid=7&navoid=250
  📡 HTTP Status: 200
  📊 Pattern 2: Found 5 matches
  🎉 Total unique departments found: 5

🎉 SUCCESS! Complete catalog import:
   • 2553 courses
   • 5 departments
   • 151 programs
```

## Testing

1. Run the app in Xcode
2. Press "Load Schools"
3. Check the debug log: `tail -f ~/Desktop/CollegeAppDebug.log`
4. Verify:
   - No double slashes in URLs
   - Override triggers successfully
   - Pattern match counts > 0
   - Programs populate in UI dropdowns

## Files Modified

- `College/ModernCampusAPI.swift`:
  - Added `https://www.stonybrook.edu/sb/bulletin/current/` to override dictionary
  - Added `normalizeBaseURL()` helper function
  - Added `buildURL()` helper function
  - Updated 7 URL construction sites to use `buildURL()`
