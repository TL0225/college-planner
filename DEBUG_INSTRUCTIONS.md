# Debug Log Instructions

Since your Xcode console isn't working, the app now writes all debug information to a file on your Desktop.

## How to View Debug Logs:

1. **Run the app** in Xcode
2. **Try to import a catalog** (select Stony Brook or Rutgers and click their name)
3. **Open the log file** on your Desktop: `CollegeAppDebug.log`
   - You can open it with TextEdit, or view it in Terminal:
     ```bash
     tail -f ~/Desktop/CollegeAppDebug.log
     ```

## What You'll See:

The log will show:
- ✅ Which schools were loaded from GitHub
- 🔍 When you start a scraping attempt
- 📋 The catalog URL and format being used
- 🌐 Whether the URL is valid
- ❌ Any errors that occur (with full details)
- 🎉 Success messages when courses are imported

## Next Steps:

After you try to import a catalog:
1. Open `CollegeAppDebug.log` from your Desktop
2. Copy the contents
3. Share them with me so I can see exactly what's happening!

The log file is created fresh each time you run the app.
