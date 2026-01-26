//
//  CollegeApp.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI

@main
struct CollegeApp: App {
    @StateObject private var coreDataManager = CoreDataManager.shared
    @StateObject private var modalCoordinator = ModalCoordinator()
    @StateObject private var appNotifications = AppNotificationCenter.shared
    @StateObject private var locationPermissionService = LocationPermissionService()
    @StateObject private var calendarManager = CalendarIntegrationManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Initialize production logger immediately on app launch.
        // Also capture stdout/stderr so print() + runtime warnings are preserved.
        AppLogger.shared.redirectConsoleOutput()

        let logger = DebugLogger.shared
        logger.app("🚀 App init")
        logger.app("Date: \(Date())")
        logger.app("Locale: \(Locale.current.identifier)")
        logger.app("TimeZone: \(TimeZone.current.identifier)")
        logger.app("ProcessInfo: \(ProcessInfo.processInfo.processName)")
        logger.app("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coreDataManager)
                .environmentObject(modalCoordinator)
                .environmentObject(appNotifications)
                .environmentObject(calendarManager)
                .environmentObject(locationPermissionService)
                .onAppear {
                    DebugLogger.shared.lifecycle("WindowGroup ContentView appeared")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                DebugLogger.shared.lifecycle("scenePhase -> active")
            case .inactive:
                DebugLogger.shared.lifecycle("scenePhase -> inactive")
            case .background:
                DebugLogger.shared.lifecycle("scenePhase -> background")
            @unknown default:
                DebugLogger.shared.lifecycle("scenePhase -> unknown")
            }
        }
    }
}
