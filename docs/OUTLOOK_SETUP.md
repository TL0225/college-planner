# Outlook / Microsoft calendar setup

The app reads your Azure AD application (client) ID at build time via xcconfig.

1. Copy the example secrets file:
   ```bash
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```
2. Register an app in [Azure Portal](https://portal.azure.com) → App registrations → New registration (macOS/native).
3. Set `MICROSOFT_CLIENT_ID` in `Secrets.xcconfig` to your application (client) ID.
4. Rebuild in Xcode. `Info.plist` receives `$(MICROSOFT_CLIENT_ID)` from `Config.xcconfig`.

`Secrets.xcconfig` is listed in `.gitignore` — do not commit a real client ID.
