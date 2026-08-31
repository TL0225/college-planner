# College Windows Widget Provider

This folder is a **scaffold** for a separate WinUI 3 widget provider package that reads
`Widgets/feeds.json` from the College data directory and registers with the Windows 11 Widgets board (Win+W).

## Why a separate package?

Microsoft requires widget providers to be:

- A packaged WinUI 3 app with package identity (MSIX)
- Registered as an `IWidgetProvider` COM server
- Distributed through the Microsoft Store or sideloaded with a trusted certificate

The main College Tauri app exports feed JSON to:

```
{CollegeData}/Widgets/feeds.json
```

Use this file as the data source for widget templates.

## Feed format

```json
{
  "version": 1,
  "updatedAt": "2026-08-30T19:00:00Z",
  "feeds": [
    {
      "id": "college-daily-agenda",
      "title": "College Daily Agenda",
      "template": "AdaptiveCard.v1",
      "data": { }
    }
  ]
}
```

## Next steps to ship widgets

1. Create a WinUI 3 class library project (`Windows.Widgets.Provider`)
2. Implement `Microsoft.Windows.Widgets.Providers.IWidgetProvider`
3. Read `%LOCALAPPDATA%\College\Widgets\feeds.json` (or path from College settings)
4. Map each feed to an Adaptive Card template
5. Package as MSIX with the same publisher certificate as College (optional)
6. Register the provider package name pattern: `*college*widget*` — College detects this and sets `provider_registered: true`

## References

- [Widget providers overview](https://learn.microsoft.com/en-us/windows/apps/develop/widgets/widget-providers)
- [Adaptive Cards](https://adaptivecards.io/)
