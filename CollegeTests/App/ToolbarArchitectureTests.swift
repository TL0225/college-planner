// ToolbarArchitectureTests.swift
// Feature: App / Toolbar
// Purpose: Architecture enforcement for toolbar refactor (ADR 001–007).

import XCTest
import CollegeAcademics
import CollegeCalendar
@testable import College

@MainActor
final class ToolbarArchitectureTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // App
        .deletingLastPathComponent() // CollegeTests
        .deletingLastPathComponent() // repo root

    private var toolbarSwiftFiles: [URL] {
        let toolbarDir = repoRoot.appendingPathComponent("College/App/Toolbar")
        let mainToolbar = repoRoot.appendingPathComponent("College/App/MainWindowToolbar.swift")
        var files = (try? FileManager.default.subpathsOfDirectory(atPath: toolbarDir.path))?
            .filter { $0.hasSuffix(".swift") }
            .map { toolbarDir.appendingPathComponent($0) } ?? []
        files.append(mainToolbar)
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Forbidden symbols

    func testForbiddenSymbols() throws {
        let forbidden = [
            "NSToolbarDelegate",
            "AppToolbarCoordinator",
            "ToolbarGlassButtonState",
            "struct ToolbarGlassButton",
            "GlassToolbarCircleButton",
            "StaticToolbarGlassButton",
            "glassToolbarEnvironment",
            "ToolbarDensity",
            "TahoeGlassStyle",
        ]
        var violations: [String] = []

        for file in toolbarSwiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            if source.contains("import AppKit") {
                violations.append("\(relative): import AppKit")
            }
            for symbol in forbidden where source.contains(symbol) {
                violations.append("\(relative): \(symbol)")
            }
            if source.contains("NSToolbar") {
                violations.append("\(relative): NSToolbar")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Forbidden toolbar symbols:\n" + violations.joined(separator: "\n")
        )
    }

    // MARK: - Cross-tab store

    func testCrossTabToolbarStateConformance() {
        let store: any CrossTabToolbarState = AppToolbarStore()
        XCTAssertTrue(store is AppToolbarStore)
    }

    func testNoSiblingToolbarObservableStores() throws {
        let toolbarDir = repoRoot.appendingPathComponent("College/App/Toolbar")
        let allowedSceneStates: Set<String> = [
            "AcademicsSceneState.swift",
            "CareerSceneState.swift",
            "WebPortalSceneState.swift",
            "TransferSceneState.swift",
        ]
        let forbiddenNames: Set<String> = [
            "CalendarToolbarState.swift",
            "AcademicsToolbarState.swift",
            "CareerToolbarState.swift",
            "WebPortalToolbarState.swift",
        ]

        let legacyToolbarStates = try FileManager.default.subpathsOfDirectory(atPath: toolbarDir.path)
            .filter { $0.hasSuffix("ToolbarState.swift") && $0 != "CrossTabToolbarState.swift" }

        for file in legacyToolbarStates {
            XCTAssertFalse(
                forbiddenNames.contains(file),
                "Legacy *ToolbarState must not return: \(file)"
            )
        }
        XCTAssertTrue(
            legacyToolbarStates.isEmpty,
            "Use *SceneState instead of *ToolbarState: \(legacyToolbarStates.sorted())"
        )

        let sceneStates = try FileManager.default.subpathsOfDirectory(atPath: toolbarDir.path)
            .filter { $0.hasSuffix("SceneState.swift") }
        let unexpected = Set(sceneStates).subtracting(allowedSceneStates)
        XCTAssertTrue(
            unexpected.isEmpty,
            "Unexpected *SceneState in App/Toolbar: \(unexpected.sorted())"
        )
    }

    func testToolbarProviderRegistryExists() throws {
        let registry = repoRoot.appendingPathComponent("College/App/Toolbar/ToolbarProviderRegistry.swift")
        let providing = repoRoot.appendingPathComponent("College/App/Toolbar/ToolbarProviding.swift")
        let registrySource = try String(contentsOf: registry, encoding: .utf8)
        let providingSource = try String(contentsOf: providing, encoding: .utf8)

        XCTAssertTrue(registrySource.contains("enum ToolbarProviderRegistry"))
        XCTAssertTrue(providingSource.contains("protocol ToolbarProviding"))
        XCTAssertTrue(providingSource.contains("struct ToolbarProviderContext"))

        for provider in [
            "CalendarToolbarProvider",
            "AcademicsToolbarProvider",
            "CareerToolbarProvider",
            "TransferToolbarProvider",
            "WebToolbarProvider",
        ] {
            XCTAssertTrue(
                providingSource.contains("enum \(provider): ToolbarProviding"),
                "Missing provider \(provider)"
            )
            XCTAssertTrue(
                registrySource.contains("\(provider).toolbarContent"),
                "Registry must delegate to \(provider)"
            )
        }
    }

    func testToolbarProviderMetadataMatchesRegistry() {
        for page in AppPageToolbarMetadata.allPages {
            let entry = AppPageToolbarMetadata.entry(for: page)
            if entry.hasDedicatedToolbarChrome {
                XCTAssertNotEqual(entry.toolbarProviderTypeName, "None", "Expected provider for \(page)")
                XCTAssertNotEqual(entry.toolbarContentTypeName, "None", "Expected content for \(page)")
            } else {
                XCTAssertEqual(entry.toolbarProviderTypeName, "None", "Expected no provider for \(page)")
                XCTAssertEqual(entry.toolbarContentTypeName, "None", "Expected no dedicated content for \(page)")
            }
        }
    }

    func testToolbarProviderRegistryIsExhaustive() throws {
        let registry = repoRoot.appendingPathComponent("College/App/Toolbar/ToolbarProviderRegistry.swift")
        let source = try String(contentsOf: registry, encoding: .utf8)
        XCTAssertFalse(source.contains("default:"), "Registry must not use default — list every AppPage case explicitly")
        XCTAssertTrue(source.contains("case .degree, .documents"))
        XCTAssertTrue(source.contains(".lms:"))
    }

    func testShellToolbarSearchWiring() throws {
        let contentView = repoRoot.appendingPathComponent("College/App/ContentView.swift")
        let mainToolbar = repoRoot.appendingPathComponent("College/App/MainWindowToolbar.swift")
        let searchModifier = repoRoot.appendingPathComponent("College/App/ShellToolbarSearchModifier.swift")
        let contentSource = try String(contentsOf: contentView, encoding: .utf8)
        let mainToolbarSource = try String(contentsOf: mainToolbar, encoding: .utf8)
        let searchModifierSource = try String(contentsOf: searchModifier, encoding: .utf8)

        XCTAssertTrue(contentSource.contains("ShellToolbarSearchModifier"))
        XCTAssertTrue(contentSource.contains("toolbarSearchText"))
        XCTAssertTrue(contentSource.contains("documentsSearchText: $toolbarSearchText"))
        XCTAssertTrue(contentSource.contains("DocumentsView("))
        XCTAssertTrue(contentSource.contains("searchText: $toolbarSearchText"))
        XCTAssertTrue(contentSource.contains("isShellSearchFocused"))
        XCTAssertFalse(mainToolbarSource.contains("DocumentsToolbarSearchField"))
        XCTAssertTrue(searchModifierSource.contains(".searchable("))
        XCTAssertTrue(searchModifierSource.contains("placement: .toolbar"))
    }

    func testFeatureMainViewsDoNotAttachWindowToolbar() throws {
        let featuresDir = repoRoot.appendingPathComponent("College/Features")
        // SettingsView hosts the standalone Settings *scene* (separate window) and owns its own
        // SwiftUI toolbar — it is explicitly out of scope for the main-window toolbar (ADR 001).
        let allowedToolbarFiles: Set<String> = [
            "CareerApplicationFormSheet.swift",
            "CareerApplicationProfileView.swift",
            // Sheet-only Done toolbar on parse-review NavigationStack, not main-window chrome.
            "ResumeProfileView.swift",
            "SettingsView.swift",
        ]
        let subpaths = try FileManager.default.subpathsOfDirectory(atPath: featuresDir.path)
        let viewFiles = subpaths.filter { $0.hasSuffix("View.swift") || $0.hasSuffix("FullView.swift") }

        var violations: [String] = []
        for relative in viewFiles {
            let fileName = (relative as NSString).lastPathComponent
            if allowedToolbarFiles.contains(fileName) { continue }
            let url = featuresDir.appendingPathComponent(relative)
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains(".toolbar {") || source.contains(".toolbar{") {
                // Inspector-host column chrome is not the main window toolbar (ADR 001).
                if source.contains(".inspector(") { continue }
                violations.append(relative)
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Main feature views must not attach .toolbar — use ContentView → MainWindowToolbar:\n"
                + violations.joined(separator: "\n")
        )
    }

    func testAppContainerCompositionRoot() {
        let container = AppContainer(telemetry: NoOpToolbarTelemetry())
        XCTAssertTrue(container.toolbarStore is AppToolbarStore)
        XCTAssertNotNil(container.toolbarDispatcher)
        XCTAssertNotNil(container.calendarScene)
        XCTAssertNotNil(container.academicsScene)
        XCTAssertNotNil(container.assistantScene)
        XCTAssertNotNil(container.careerScene)
        XCTAssertNotNil(container.webPortalScene)
        XCTAssertNotNil(container.modalCoordinator)
        XCTAssertNotNil(container.academicMetricsStore)
        XCTAssertNotNil(container.auditSnapshotStore)
        XCTAssertNotNil(container.launchPreloadCoordinator)
        XCTAssertNotNil(container.transferScene)
        XCTAssertNotNil(container.transferCoordinator)
        XCTAssertIdentical(container.appActivity, AppActivityCoordinator.shared)
        XCTAssertIdentical(container.persistence, CollegePersistence.shared)
        XCTAssertIdentical(container.appDataStore, AppDataStore.shared)
        XCTAssertIdentical(container.appNotifications, AppNotificationCenter.shared)
        XCTAssertIdentical(container.securityManager, SecurityManager.shared)
        XCTAssertNotNil(container.locationPermissionService)
        XCTAssertNotNil(container.calendarManager)
        XCTAssertNotNil(container.lmsCoordinator)
    }

    func testCalendarShellPortsSurviveAfterWireShell() {
        let container = AppContainer(telemetry: NoOpToolbarTelemetry())
        CalendarPersistencePortBootstrap.wireShell(container: container)
        XCTAssertNotNil(CalendarToolbarAccess.dispatcher)
        XCTAssertTrue(CalendarToolbarAccess.dispatcher === container.calendarShellPorts.toolbarDispatcher)
    }

    func testAppContainerWindowScopedInstancesAreDistinct() {
        let first = AppContainer(telemetry: NoOpToolbarTelemetry())
        let second = AppContainer(telemetry: NoOpToolbarTelemetry())

        XCTAssert(first !== second)
        XCTAssert(first.toolbarStore !== second.toolbarStore)
        XCTAssert(first.toolbarDispatcher !== second.toolbarDispatcher)
        XCTAssert(first.calendarScene !== second.calendarScene)
        XCTAssert(first.academicsScene !== second.academicsScene)
        XCTAssert(first.careerScene !== second.careerScene)
        XCTAssert(first.webPortalScene !== second.webPortalScene)
        XCTAssert(first.modalCoordinator !== second.modalCoordinator)
        XCTAssert(first.academicMetricsStore !== second.academicMetricsStore)
        XCTAssert(first.auditSnapshotStore !== second.auditSnapshotStore)
        XCTAssert(first.launchPreloadCoordinator !== second.launchPreloadCoordinator)
        XCTAssert(first.locationPermissionService !== second.locationPermissionService)
        XCTAssert(first.calendarManager !== second.calendarManager)
        XCTAssert(first.lmsCoordinator !== second.lmsCoordinator)
    }

    func testAppContainerAcceptsInjectedDependencies() {
        let modal = ModalCoordinator()
        let metrics = AcademicMetricsStore()
        let container = AppContainer(
            telemetry: NoOpToolbarTelemetry(),
            modalCoordinator: modal,
            academicMetricsStore: metrics
        )
        XCTAssertIdentical(container.modalCoordinator, modal)
        XCTAssertIdentical(container.academicMetricsStore, metrics)
    }

    func testWebToolbarDispatchRouting() {
        var actions: [WebToolbarAction] = []
        let dispatcher = ToolbarDispatcher(telemetry: NoOpToolbarTelemetry())
        _ = dispatcher.register(owner: .webPortal(nil)) { action in
            guard case .web(let webAction) = action else { return }
            actions.append(webAction)
        }

        dispatcher.dispatch(.web(.back))
        dispatcher.dispatch(.web(.reload))
        XCTAssertEqual(actions, [.back, .reload])
    }

    // MARK: - Dispatcher lifecycle

    func testDispatcherLifecycle() {
        var called = false
        let dispatcher = ToolbarDispatcher(telemetry: NoOpToolbarTelemetry())
        let token = dispatcher.register(owner: .calendar) { _ in called = true }
        dispatcher.dispatch(.calendar(.previous))
        XCTAssertTrue(called)

        called = false
        token.invalidate()
        dispatcher.dispatch(.calendar(.previous))
        XCTAssertFalse(called)
    }

    func testDispatcherConcurrency() {
        var calendarCalled = false
        var academicsCalled = false
        let dispatcher = ToolbarDispatcher(telemetry: NoOpToolbarTelemetry())
        let calendarToken = dispatcher.register(owner: .calendar) { _ in calendarCalled = true }
        dispatcher.register(owner: .academics) { _ in academicsCalled = true }

        dispatcher.dispatch(.academics(.addCourse))
        XCTAssertTrue(academicsCalled)
        XCTAssertFalse(calendarCalled)

        calendarToken.invalidate()
        dispatcher.dispatch(.calendar(.next))
        XCTAssertFalse(calendarCalled)
    }

    func testDispatcherReplacement() {
        var first = 0
        var second = 0
        let dispatcher = ToolbarDispatcher(telemetry: NoOpToolbarTelemetry())
        _ = dispatcher.register(owner: .career) { _ in first += 1 }
        _ = dispatcher.register(owner: .career) { _ in second += 1 }

        dispatcher.dispatch(.career(.addApplication))
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }

    /// Ship-gate substitute for 10× tab-cycle handler churn (Instruments leak pass companion).
    func testDispatcherTabCycleStress() {
        let dispatcher = ToolbarDispatcher(telemetry: NoOpToolbarTelemetry())
        let owners: [ToolbarHandlerOwner] = [.calendar, .academics, .career, .webPortal(nil)]
        let actions: [ToolbarAction] = [
            .calendar(.previous),
            .academics(.statsSidebarToggle),
            .career(.addApplication),
            .web(.reload),
        ]

        for cycle in 0..<10 {
            var tokens: [ToolbarHandlerToken] = []
            var callCounts = Array(repeating: 0, count: owners.count)

            for (index, owner) in owners.enumerated() {
                let token = dispatcher.register(owner: owner) { _ in
                    callCounts[index] += 1
                }
                tokens.append(token)
            }

            for (index, action) in actions.enumerated() {
                dispatcher.dispatch(action)
                XCTAssertEqual(callCounts[index], 1, "Cycle \(cycle) action \(index)")
            }

            for token in tokens {
                token.invalidate()
            }

            for action in actions {
                dispatcher.dispatch(action)
            }

            XCTAssertTrue(callCounts.allSatisfy { $0 == 1 }, "Cycle \(cycle) handlers must not fire after invalidate")
            #if DEBUG
            XCTAssertEqual(dispatcher.activeHandlerCount, 0, "Cycle \(cycle) must leave no registered handlers")
            #endif
        }
    }

    func testTelemetrySinkInjection() {
        let telemetry = MockToolbarTelemetry()
        let dispatcher = ToolbarDispatcher(telemetry: telemetry)
        dispatcher.register(owner: .calendar) { _ in }

        dispatcher.dispatch(.calendar(.sidebarToggle))
        XCTAssertEqual(telemetry.events.count, 1)
        XCTAssertEqual(telemetry.events.first?.0, .calendar(.sidebarToggle))
        XCTAssertEqual(telemetry.events.first?.1, .calendar)
    }

    // MARK: - Metadata registry

    func testAppPageToolbarMetadataCoverage() {
        for page in AppPageToolbarMetadata.allPages {
            let entry = AppPageToolbarMetadata.entry(for: page)
            XCTAssertFalse(entry.toolbarContentTypeName.isEmpty)
        }

        XCTAssertEqual(
            AppPageToolbarMetadata.entry(for: .calendar).toolbarContentTypeName,
            "CalendarToolbarContent"
        )
        XCTAssertEqual(
            AppPageToolbarMetadata.entry(for: .academics).toolbarContentTypeName,
            "AcademicsToolbarContent"
        )
        XCTAssertEqual(
            AppPageToolbarMetadata.entry(for: .career).toolbarContentTypeName,
            "CareerToolbarContent"
        )
        XCTAssertEqual(
            AppPageToolbarMetadata.entry(for: .transferDatabase).toolbarContentTypeName,
            "TransferToolbarContent"
        )
    }
}
