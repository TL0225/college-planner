## Plan: Trace CFPreferences 4MB Write

## Findings

In SwiftUI, the system tries to be helpful by remembering where the user left their windows and how wide they dragged their split views. To do this, it generates a "key" based on the Type Name of your view.

Because you are using SwiftUI 6 with complex modifiers (padding, backgrounds, etc.), your view's internal name looks like a massive, nested Russian Nesting Doll:

SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Timothy.College.MainDashboardView...>>>

Every time you change a small detail in your code or add a new modifier, SwiftUI thinks its a "new" type of window and creates a brand new key that is thousands of characters long. Over time, these thousands of keys have piled up into a 5MB wall of text.

Find the exact UserDefaults key being written when the sidebar toggle fires, then migrate that payload to disk and add guardrails to prevent large writes.

## How to Fix It (The "Surgical" Approach)

You need to tell SwiftUI to stop using those massive auto-generated names and use a short, specific one instead.

**Steps**
1. Fix the window frame bloat. In your App struct (where you define your WindowGroup), add a specific autosave name. This forces SwiftUI to use one short string instead of the massive generic type name.

	WindowGroup {
		 ContentView()
	}
	.windowFrameAutosaveName("MainAppWindow")

2. Fix the split view bloat. Use Option A: wrap the split view in AppKit and set a stable, short `autosaveName` (or disable autosave). If you keep a custom NSSplitView, make sure `autosaveName` is a short string.
3. Clean the "gunk" out of your system. The old 5MB of junk keys are still sitting in preferences. Clear them by running:

	defaults delete Timothy.College

	Note: this resets app settings (tokens, window positions), but clears the 5.7MB of generic type names instantly.
4. Validate in sandboxed Release: clear legacy defaults for the bundle domain, toggle the sidebar, and confirm no CFPreferences error.
5. Add a regression guard: before any large write, measure encoded size and either cap/truncate or skip with a log, in the same feature owning the data.

## Additional Findings And Fixes (Adapt To Codebase)

1. The "Repeating String" Bug (From your prefs dump)
I noticed something strange in your file: user_google_client_id is huge not because of a type name, but because the same ID is repeated over and over with \n (newlines).

The problem: you likely have logic in your onboarding or login flow that looks like settings.clientID += newID.

The fix: ensure you are assigning (=), not appending (+=), when updating your Google or Spotify credentials. This is a silent bloat that would eventually trigger the 4MB bug again even after the structural fix.

2. Tahoe sidebar button anchor
In the Tahoe design (macOS 26), the sidebar toggle button can drift if it is not explicitly tied to the window's toolbar behavior.

The fix: ensure your NavigationSplitView uses .navigationSplitViewStyle(.sidebar) or .balanced.

Toolbar placement: do not just use .navigationBarLeading. In the Tahoe spec, use the specific .navigation or .sidebar placement to tell macOS: "This button belongs to the sidebar logic, not the general window toolbar."

	.toolbar {
		ToolbarItem(placement: .navigation) {
			Button(action: toggleSidebar) {
				Image(systemName: "sidebar.left")
			}
		}
	}

3. Core Data "mirroring" audit
Since you are using Core Data, verify you are not accidentally using UserDefaults as a middleman.

The problem: sometimes developers fetch a setting from Core Data, then save it to a @State or @AppStorage variable for the UI. If that UI variable is part of a complex type, it triggers the runaway keys again.

The fix: bind your UI directly to your Core Data FetchRequest or Query. If you need a Settings view, use the @Observable pattern (Swift 6) to keep the data in memory without touching UserDefaults at all.

**Relevant files**
- /Users/timothy/Desktop/College/College/App/ContentView.swift — sidebar toggle and diagnostic logging hook
- /Users/timothy/Desktop/College/College/App/AppToolbarCoordinator.swift — toolbar toggle wiring
- /Users/timothy/Desktop/College/College/Calendar/CalendarIntegrationManager.swift — calendar persistence keys
- /Users/timothy/Desktop/College/College/Calendar/CalendarSyncMapDiskPersistence.swift — disk persistence for large maps
- /Users/timothy/Desktop/College/College/Intelligence/AIAssistantView.swift — assistant persistence triggers
- /Users/timothy/Desktop/College/College/Catalog/Vector/CatalogVectorStore.swift — vector index persistence
- /Users/timothy/Desktop/College/College/Services/FSWatchdogService.swift — bookmark persistence
- /Users/timothy/Desktop/College/College/Services/CloudIntegrationService.swift — import cache persistence

**Verification**
1. Run sandboxed Release and toggle sidebar; confirm the CFPreferences error does not appear.
2. Confirm the offending key is gone or under size in the app defaults domain.
3. Confirm the owning feature still persists and restores its data from disk.

**Decisions**
- Prioritize fixing the single largest key identified by instrumentation; avoid refactors outside that feature.
- Keep UserDefaults for small settings only; move collections/blobs to disk.

**Further Considerations**
1. If multiple keys are near the limit, consolidate into a feature-scoped disk cache directory with explicit cleanup.
2. If SwiftUI state restoration is writing large values, disable or constrain scene storage for that state.
