// LaunchSplashWindowPolicy.swift
// Feature: App
// Purpose: Launch splash layout metrics only — window chrome stays standard AppKit.
// Data: CollegePersistence / repositories when applicable.

import CoreGraphics

enum LaunchSplashWindowMetrics {
    static let cardWidth: CGFloat = 400
    static let cardHeight: CGFloat = 298
    static let shadowPadding: CGFloat = 32

    static var windowSize: CGSize {
        CGSize(
            width: cardWidth + shadowPadding * 2,
            height: cardHeight + shadowPadding * 2
        )
    }
}
