#!/bin/bash
# Script to completely reset the College app database

echo "🗑️  Resetting College App Database..."

# Kill the app if it's running
echo "1. Closing College app..."
pkill -9 College 2>/dev/null || echo "   App not running"

# Delete the database files
echo "2. Deleting database files..."
rm -f /Users/timothy/Library/Containers/Timothy.College/Data/Library/Application\ Support/College/*.sqlite*
echo "   ✅ Database deleted"

# Delete any cached data
echo "3. Cleaning caches..."
rm -rf /Users/timothy/Library/Containers/Timothy.College/Data/Library/Caches/* 2>/dev/null
echo "   ✅ Caches cleared"

echo ""
echo "✅ Reset complete!"
echo ""
echo "Next steps:"
echo "1. Open the College app"
echo "2. Navigate to university search"
echo "3. Search for 'University at Buffalo'"
echo "4. Wait for the catalog to download and import"
echo "5. Check that departments appear without 'department page' or 'department' suffixes"
echo ""
