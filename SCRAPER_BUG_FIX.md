# CRITICAL BUG FIX - Department Name Cleanup

## Issue Discovered
The scraper was still returning department names with " department" suffix:
```
Department: Industrial and Systems Engineering department
```

## Root Cause
In `UniversalCatalogScraper.swift` line 450-474, the cleanup logic had a bug:

```swift
// WRONG: This checked 'lower' which was the ORIGINAL string
let lower = dept.lowercased()  // "industrial and systems engineering department page"
dept = dept.replacingOccurrences(of: " department page", with: "")  // Removes " department page"
// BUT then we check lower.hasSuffix(" department") - this is checking the ORIGINAL!
if !lower.hasPrefix("department of") && lower.hasSuffix(" department") { ... }
```

The problem:
1. `lower` was set to the ORIGINAL lowercased string: "industrial and systems engineering **department page**"
2. We removed " department page", so `dept` became "Industrial and Systems Engineering"
3. But then we checked if `lower` (the ORIGINAL) has suffix " department"
4. Since the original had "department page", it doesn't end with " department" (it ends with "page")
5. So the " department" cleanup was SKIPPED!

## Solution
Recalculate the lowercased string AFTER removing " department page":

```swift
// CORRECT: Calculate cleanedLower AFTER removing " department page"
dept = dept.replacingOccurrences(of: " department page", with: "")
let cleanedLower = dept.lowercased()  // Now check the CLEANED string
if !cleanedLower.hasPrefix("department of") && cleanedLower.hasSuffix(" department") { ... }
```

## Testing Required
1. Reset database again:
   ```bash
   ./reset_database.sh
   ```

2. Re-scrape UB catalog

3. Check console logs - should now show:
   ```
   Department: Industrial and Systems Engineering  (not "...department")
   Department: Economics  (not "Economics department")
   ```

4. Verify dropdown shows clean names without "department" suffix

## Files Changed
- `UniversalCatalogScraper.swift` line 451-472: Fixed variable reference bug in cleanup logic
