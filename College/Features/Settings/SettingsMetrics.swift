// SettingsMetrics.swift
// Feature: Settings
// Purpose: Settings module — SettingsMetrics.
// Data: CollegePersistence / repositories when applicable.

import CoreGraphics

enum SettingsMetrics {
    /// Fixed sidebar width (macOS System Settings style — not user-resizable).
    static let sidebarWidth: CGFloat = 220
    static let sidebarColumnMinWidth: CGFloat = sidebarWidth
    static let sidebarColumnMaxWidth: CGFloat = sidebarWidth
    static let detailMaxWidth: CGFloat = 720
    static let detailMinWidth: CGFloat = 440
    static let minWindowWidth: CGFloat = 820
    /// Preferred width for the standalone Settings window (sidebar + detail).
    static let preferredWindowWidth: CGFloat = 920
    static let minWindowHeight: CGFloat = 520
}
