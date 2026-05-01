#if os(macOS)
import Foundation

/// Single entry point for posting catalog import progress to the menu bar controller.
enum CatalogMenuBarProgressNotifier {
    static func postInProgress(fraction: Double, title: String, indeterminate: Bool = false) {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "fraction": fraction,
                "title": title,
                "finished": false,
                "indeterminate": indeterminate,
            ]
        )
    }

    static func postFinished() {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: ["finished": true]
        )
    }
}
#endif
