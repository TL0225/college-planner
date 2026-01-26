//
//  ContentView.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var pillCoordinator = PillCoordinator()

    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @State private var activePage: AppPage = .degree
    @State private var navigationPillFrameInRoot: CGRect = .zero

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }

    var body: some View {
        ZStack {
            Group {
                switch activePage {
                case .degree:
                    DegreeView()
                case .calendar:
                    CalendarView()
                case .whatIf:
                    WhatIfView()
                case .flowChart:
                    FlowchartView()
                case .resources:
                    ResourcesView()
                case .profile:
                    ProfileView()
                case .settings:
                    SettingsView()
                case .debug:
                    IntelligenceDebugView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.bgMain)
            .preferredColorScheme(appAppearance.preferredColorScheme)

            HoverNavigationPill(activePage: $activePage)
                .zIndex(50)

            AppNotificationHost()
                .environmentObject(appNotifications)
                .zIndex(500)

            // Global overlays
            switch modalCoordinator.activeModal {
            case .addExperience:
                AddExperienceView(
                    isPresented: Binding(
                        get: { 
                            if case .addExperience = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { modalCoordinator.activeModal = nil } }
                    ),
                    experience: nil
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
                
            case .editExperience(let experience):
                AddExperienceView(
                    isPresented: Binding(
                        get: { 
                            if case .editExperience = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { modalCoordinator.activeModal = nil } }
                    ),
                    experience: experience
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .addAchievement:
                AddAchievementOverlay(
                    isPresented: Binding(
                        get: { 
                            if case .addAchievement = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { modalCoordinator.activeModal = nil } }
                    ),
                    achievement: nil
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
                
            case .editAchievement(let achievement):
                AddAchievementOverlay(
                    isPresented: Binding(
                        get: { 
                            if case .editAchievement = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { modalCoordinator.activeModal = nil } }
                    ),
                    achievement: achievement
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .editCourse(let selection):
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.60))
                        .ignoresSafeArea()
                        .onTapGesture {
                            modalCoordinator.activeModal = nil
                        }

                    EditCourseDetailsView(
                        courseCode: selection.courseCode,
                        defaultCourseName: selection.defaultCourseName,
                        defaultCreditsText: selection.defaultCreditsText,
                        onClose: { modalCoordinator.activeModal = nil }
                    )
                    .environmentObject(coreDataManager)
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .addGenEdCourse:
                GenEdAddCourseModal(
                    isPresented: Binding(
                        get: {
                            if case .addGenEdCourse = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { modalCoordinator.activeModal = nil }
                        }
                    )
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .addCatalogCourseGlobal(let tagAsGenEd):
                GenEdAddCourseModal(
                    isPresented: Binding(
                        get: {
                            if case .addCatalogCourseGlobal = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { modalCoordinator.activeModal = nil }
                        }
                    ),
                    targetSemesterID: nil,
                    tagAsGenEd: tagAsGenEd
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .addCatalogCourse(let semesterObjectID):
                GenEdAddCourseModal(
                    isPresented: Binding(
                        get: {
                            if case .addCatalogCourse = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { modalCoordinator.activeModal = nil }
                        }
                    ),
                    targetSemesterID: semesterObjectID,
                    tagAsGenEd: false
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .addCalendarItem:
                if activePage == .calendar {
                    EmptyView()
                } else {
                    AddCalendarItemOverlay(
                        isPresented: Binding(
                            get: {
                                if case .addCalendarItem = modalCoordinator.activeModal { return true }
                                return false
                            },
                            set: { isPresented in
                                if !isPresented { modalCoordinator.activeModal = nil }
                            }
                        ),
                        semester: {
                            guard case .addCalendarItem(let semesterID, _, _, _) = modalCoordinator.activeModal else { return nil }
                            guard let semesterID else { return nil }
                            return coreDataManager.semesters.first(where: { $0.id == semesterID })
                        }(),
                        initialTitle: {
                            guard case .addCalendarItem(_, let title, _, _) = modalCoordinator.activeModal else { return nil }
                            return title
                        }(),
                        initialStartDateTime: {
                            guard case .addCalendarItem(_, _, let start, _) = modalCoordinator.activeModal else { return nil }
                            return start
                        }(),
                        initialEndDateTime: {
                            guard case .addCalendarItem(_, _, _, let end) = modalCoordinator.activeModal else { return nil }
                            return end
                        }(),
                        eventToEdit: nil,
                        presentationStyle: .fullScreenOverlay
                    )
                    .environmentObject(coreDataManager)
                    .transition(.opacity)
                    .zIndex(200)
                }

            case .editCalendarItem(let objectID):
                if activePage == .calendar {
                    EmptyView()
                } else {
                    let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity
                    AddCalendarItemOverlay(
                        isPresented: Binding(
                            get: {
                                if case .editCalendarItem = modalCoordinator.activeModal { return true }
                                return false
                            },
                            set: { isPresented in
                                if !isPresented { modalCoordinator.activeModal = nil }
                            }
                        ),
                        semester: event?.semester,
                        initialStartDateTime: event?.startDate,
                        initialEndDateTime: event?.endDate,
                        eventToEdit: event
                    )
                    .environmentObject(coreDataManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(200)
                }

            case .editTask(let objectID):
                let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity
                AddTaskOverlay(
                    isPresented: Binding(
                        get: {
                            if case .editTask = modalCoordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { modalCoordinator.activeModal = nil }
                        }
                    ),
                    semester: task?.semester,
                    taskToEdit: task
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .none:
                EmptyView()
            }
        }
        .environmentObject(pillCoordinator)
        .coordinateSpace(name: "ContentRoot")
        .onPreferenceChange(NavigationPillFramePreferenceKey.self) { frame in
            navigationPillFrameInRoot = frame
        }
        .animation(.easeInOut(duration: 0.2), value: modalCoordinator.activeModal)
        .onAppear {
            DebugLogger.shared.nav("Root ContentView appeared; initial page=\(activePage.rawValue)")
        }
        .onChange(of: activePage) { _, newPage in
            DebugLogger.shared.nav("Navigate: activePage -> \(newPage.rawValue)")
        }
    }
}

private struct NavigationPillFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct HoverNavigationPill: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Binding var activePage: AppPage
    @Namespace private var selectionNamespace

    @State private var isHoveringPill: Bool = false
    @State private var keepVisible: Bool = false
    @State private var pendingHideWorkItem: DispatchWorkItem? = nil

    @State private var addEventPreferredHeight: CGFloat = 340

    private var shouldShowPill: Bool {
        keepVisible || pillCoordinator.hasSelection || pillCoordinator.isAddEventPresented
    }

    private func updateKeepVisible() {
        pendingHideWorkItem?.cancel()

        // Always keep visible while in a "mode" (selection or add-event).
        if pillCoordinator.hasSelection || pillCoordinator.isAddEventPresented {
            keepVisible = true
            return
        }

        // Immediate show while hovering the pill.
        if isHoveringPill {
            keepVisible = true
            return
        }

        // Debounce hide to avoid flicker when crossing between hotspot and pill.
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.14)) {
                keepVisible = false
            }
        }
        pendingHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack {
                    // Bottom hover hotspot: keeps the "lift from bottom" animation possible without
                    // relying on a near-zero opacity pill to remain hoverable.
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 28)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isHoveringPill = hovering
                            }
                            updateKeepVisible()
                        }

                    pill
                        .offset(y: shouldShowPill ? 0 : 68)
                        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: shouldShowPill)
                        .allowsHitTesting(shouldShowPill)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: NavigationPillFramePreferenceKey.self,
                                        value: proxy.frame(in: .named("ContentRoot"))
                                    )
                            }
                        )
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
        .onAppear { updateKeepVisible() }
        .onChange(of: pillCoordinator.selection) { _, _ in updateKeepVisible() }
        .onChange(of: pillCoordinator.isAddEventPresented) { _, _ in updateKeepVisible() }
    }

    private var pill: some View {
        let isHovered = isHoveringPill || pillCoordinator.isAddEventPresented
        let cornerRadius: CGFloat = pillCoordinator.isAddEventPresented ? 22 : 18
        
        // Enforce Light Mode
        let surfaceFill = Color.white
        let surfaceStroke = Color.black.opacity(0.08)

        return Group {
            if pillCoordinator.isAddEventPresented {
                EmptyView()
            } else if let selection = pillCoordinator.selection {
                SelectionInspectorPill(selection: selection, activePage: $activePage)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    NavigationPillButton(page: .degree, activePage: $activePage, color: DesignSystem.Colors.primary, selectionNamespace: selectionNamespace)
                    NavigationPillButton(page: .calendar, activePage: $activePage, color: DesignSystem.Colors.primary, selectionNamespace: selectionNamespace)

                    NavigationPillButton(page: .whatIf, activePage: $activePage, color: DesignSystem.Colors.secondary, selectionNamespace: selectionNamespace)
                    NavigationPillButton(page: .flowChart, activePage: $activePage, color: DesignSystem.Colors.accent, selectionNamespace: selectionNamespace)
                    NavigationPillButton(page: .resources, activePage: $activePage, color: DesignSystem.Colors.warning, selectionNamespace: selectionNamespace)
                    NavigationPillButton(page: .profile, activePage: $activePage, color: DesignSystem.Colors.info, selectionNamespace: selectionNamespace)
                    NavigationPillButton(page: .settings, activePage: $activePage, color: DesignSystem.Colors.textMain, selectionNamespace: selectionNamespace)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .fixedSize()
                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .padding(.vertical, pillCoordinator.isAddEventPresented ? 0 : 8)
        .padding(.horizontal, pillCoordinator.isAddEventPresented ? 0 : 14)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(surfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (pillCoordinator.isAddEventPresented ? 1 : (isHovered ? 1.02 : 1)))
        .shadow(color: Color.black.opacity(isHovered ? 0.20 : 0.14), radius: isHovered ? 22 : 18, x: 0, y: isHovered ? 10 : 8)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: pillCoordinator.selection != nil)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86), value: pillCoordinator.isAddEventPresented)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHoveringPill = hovering
            }
            updateKeepVisible()
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

private struct AddEventPillButton: View {
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if pillCoordinator.isAddEventPresented {
                pillCoordinator.dismissAddEvent(animated: !reduceMotion)
            } else {
                pillCoordinator.presentAddEvent(prefill: nil, animated: !reduceMotion)
            }
        } label: {
            Circle()
                .fill(DesignSystem.Colors.success)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: DesignSystem.Colors.success.opacity(0.22), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(PillBounceButtonStyle())
        .accessibilityLabel("Add Event")
    }
}

private struct NavigationPillButton: View {
    let page: AppPage
    @Binding var activePage: AppPage
    let color: Color
    let selectionNamespace: Namespace.ID

    private var isActive: Bool {
        activePage == page
    }

    var body: some View {
        Button(action: {
            DebugLogger.shared.ui("NavPill: select page=\(page.rawValue)")
            activePage = page
        }) {
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.surface.opacity(0.14))
                        .matchedGeometryEffect(id: "navpill.selection", in: selectionNamespace)
                }
                Image(systemName: page.icon)
                    .font(DesignSystem.Fonts.main(size: 16))
                    .foregroundColor(isActive ? color : color.opacity(0.85))
                    .frame(width: 26, height: 26)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PillBounceButtonStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isActive)
    }
}

private struct PillBounceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
        .environmentObject(CoreDataManager.shared)
        .environmentObject(ModalCoordinator())
}
