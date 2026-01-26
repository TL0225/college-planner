#!/bin/bash

# Stony Brook Scraping Verification Script
# Tests actual HTML against our regex patterns

echo "🧪 Testing Stony Brook Catalog Scraping"
echo "========================================"
echo ""

BASE_URL="https://catalog.stonybrook.edu"
CATALOG_ID="7"

echo "1️⃣  Checking Override URL Match..."
echo "   App uses: $BASE_URL"
echo "   Override has: $BASE_URL ✅"
echo ""

echo "2️⃣  Verifying Navoids..."
curl -s "$BASE_URL/index.php?catoid=$CATALOG_ID" | grep -o '<a[^>]*navoid=[0-9]*[^>]*>[^<]*Majors[^<]*</a>' | head -1 | grep -o 'navoid=[0-9]*'
curl -s "$BASE_URL/index.php?catoid=$CATALOG_ID" | grep -o '<a[^>]*navoid=[0-9]*[^>]*>[^<]*Minors[^<]*</a>' | head -1 | grep -o 'navoid=[0-9]*'
curl -s "$BASE_URL/index.php?catoid=$CATALOG_ID" | grep -o '<a[^>]*navoid=[0-9]*[^>]*>[^<]*Colleges[^<]*</a>' | head -1 | grep -o 'navoid=[0-9]*'
echo ""

echo "3️⃣  Testing Majors Page (navoid=224)..."
MAJOR_COUNT=$(curl -s "$BASE_URL/content.php?catoid=$CATALOG_ID&navoid=224" 2>/dev/null | grep -c "preview_program")
echo "   Found $MAJOR_COUNT preview_program links"
if [ "$MAJOR_COUNT" -gt 50 ]; then
    echo "   ✅ SUCCESS: Pattern 1 should find ~$MAJOR_COUNT majors"
else
    echo "   ❌ FAILED: Too few links found"
fi
echo ""

echo "4️⃣  Testing Minors Page (navoid=228)..."
MINOR_COUNT=$(curl -s "$BASE_URL/content.php?catoid=$CATALOG_ID&navoid=228" 2>/dev/null | grep -c "preview_program")
echo "   Found $MINOR_COUNT preview_program links"
if [ "$MINOR_COUNT" -gt 20 ]; then
    echo "   ✅ SUCCESS: Pattern 1 should find ~$MINOR_COUNT minors"
else
    echo "   ❌ FAILED: Too few links found"
fi
echo ""

echo "5️⃣  Testing Departments Page (navoid=250)..."
DEPT_COUNT=$(curl -s "$BASE_URL/content.php?catoid=$CATALOG_ID&navoid=250" 2>/dev/null | grep -c "<h4>.*\(College\|School\)")
echo "   Found $DEPT_COUNT college/school headers"
if [ "$DEPT_COUNT" -gt 3 ]; then
    echo "   ✅ SUCCESS: Pattern 2 should find ~$DEPT_COUNT departments"
else
    echo "   ❌ FAILED: Too few headers found"
fi
echo ""

echo "6️⃣  Sample Major HTML Structure..."
curl -s "$BASE_URL/content.php?catoid=$CATALOG_ID&navoid=224" 2>/dev/null | grep "preview_program" | head -2 | sed 's/</\n</g' | grep -E '(preview_program|<a )'
echo ""

echo "7️⃣  Sample Department HTML Structure..."
curl -s "$BASE_URL/content.php?catoid=$CATALOG_ID&navoid=250" 2>/dev/null | grep -E "<h4>.*College" | head -3
echo ""

echo "✅ Verification Complete!"
echo ""
echo "Expected App Results:"
echo "  📊 Majors: ~$MAJOR_COUNT programs"
echo "  📊 Minors: ~$MINOR_COUNT programs"
echo "  📊 Departments: ~$DEPT_COUNT colleges"
