#!/bin/bash
# Complete test script for department artifacts fix

echo "======================================"
echo "  Department Artifacts Fix - Testing"
echo "======================================"
echo ""

# Step 1: Reset
echo "Step 1: Resetting database..."
./reset_database.sh
echo ""

# Step 2: Build
echo "Step 2: Building latest version..."
xcodebuild -project College.xcodeproj -scheme College -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -2
echo ""

# Step 3: Instructions
echo "Step 3: Manual Testing Required"
echo "--------------------------------"
echo ""
echo "1. Launch the College app"
echo ""
echo "2. Search for and select: 'University at Buffalo'"
echo ""
echo "3. Wait for catalog download (should show 362 programs)"
echo ""
echo "4. Check console logs for clean department names:"
echo "   ✅ GOOD: 'Department: Industrial and Systems Engineering'"
echo "   ❌ BAD:  'Department: Industrial and Systems Engineering department'"
echo ""
echo "5. In the app, select 'College of Arts and Sciences'"
echo ""
echo "6. Check department dropdown:"
echo "   ✅ Should show: 'Economics', 'English', 'Physics'"
echo "   ❌ Should NOT show: 'Economics department', 'English department'"
echo ""
echo "7. Select a department (e.g., 'Economics')"
echo ""
echo "8. Verify majors appear in the major dropdown"
echo ""
echo "9. Check that '(Other)' section either:"
echo "   - Doesn't exist, OR"
echo "   - Only contains: 'Honors College', 'Recreation Instruction', etc."
echo ""
echo "======================================"
echo "Expected Results:"
echo "======================================"
echo "✅ 66 departments with clean names"
echo "✅ All grouped under correct colleges"
echo "✅ No 'department' or 'department page' suffixes"
echo "✅ Majors appear when selecting departments"
echo "✅ No duplicate departments"
echo ""
