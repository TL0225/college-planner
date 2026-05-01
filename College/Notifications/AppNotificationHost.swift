import SwiftUI

/// All notifications are now delivered exclusively through macOS Notification
/// Center (UNUserNotificationCenter). This host is kept as a no-op placeholder
/// so existing call sites in ContentView compile without changes.
struct AppNotificationHost: View {
    var body: some View { EmptyView() }
}
