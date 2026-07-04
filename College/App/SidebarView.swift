// SidebarView.swift
// Feature: App
// Purpose: App module — SidebarView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

enum SidebarColumnLayout {
    static let iconOnlyThreshold: CGFloat = 112
    /// Fallback width before the hosting window lays out its traffic-light cluster.
    static let collapsedMinWidth: CGFloat = 72
    /// Fixed shell sidebar width — icon-only rail; not user-resizable.
    static let fixedWidth: CGFloat = collapsedMinWidth
    static let expandedMinWidth: CGFloat = 200
    static let idealWidth: CGFloat = 220
    static let maxWidth: CGFloat = 300

    /// Width that gives the system traffic-light cluster equal leading and trailing inset
    /// within the sidebar column (`leadingInset == trailingInset` when column width is this value).
    @MainActor
    static func trafficLightCenteredWidth(in window: NSWindow) -> CGFloat {
        guard let contentView = window.contentView else { return collapsedMinWidth }

        let sidebarLeadingX: CGFloat = {
            guard let splitView = contentView.firstSubview(ofType: NSSplitView.self),
                  let leadingColumn = splitView.subviews.first else { return 0 }
            return leadingColumn.convert(CGPoint.zero, to: contentView).x
        }()

        let roles: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var minX: CGFloat?
        var maxX: CGFloat?

        for role in roles {
            guard let button = window.standardWindowButton(role), !button.isHidden else { continue }
            let frameInContent = button.convert(button.bounds, to: contentView)
            minX = min(minX ?? frameInContent.minX, frameInContent.minX)
            maxX = max(maxX ?? frameInContent.maxX, frameInContent.maxX)
        }

        guard let minX, let maxX, maxX > minX else { return collapsedMinWidth }

        let clusterMinX = minX - sidebarLeadingX
        let clusterMaxX = maxX - sidebarLeadingX
        guard clusterMaxX > clusterMinX else { return collapsedMinWidth }
        return (clusterMinX + clusterMaxX).rounded(.toNearestOrAwayFromZero)
    }
}

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Binding var activePage: AppPage
    var columnWidth: CGFloat = SidebarColumnLayout.fixedWidth

    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var profileShell: ProfileShellSnapshot = ProfileReadBridge.shellSnapshot()

    @State private var hoveredSidebarPage: AppPage?
    @State private var hoveredFooterSettings = false
    @State private var hoveredGroupID: UUID?
    @State private var webShortcuts: [WebShortcut] = WebShortcutStore.loadAllSync()
    @State private var webGroups: [WebShortcutGroup] = WebShortcutStore.loadGroupsSync()
    @State private var expandedGroupIDs: Set<UUID> = WebShortcutStore.loadExpandedGroupIDsSync()
    @State private var shortcutsContentHeight: CGFloat = 0
    @State private var lmsPortalURL: URL? = LMSPortalConfiguration.resolvedPortalURL()

    // Layout metrics are measured via a background reader rather than wrapping the
    // whole sidebar in a GeometryReader. A root GeometryReader latches to a zero
    // size while the split-view column animates back in, which collapsed all rows
    // and left the revealed sidebar showing only its (system-drawn) background.
    @State private var measuredHeight: CGFloat = 800
    @State private var measuredTopInset: CGFloat = 32

    private var isIconOnly: Bool {
        columnWidth < SidebarColumnLayout.iconOnlyThreshold
    }

    private var hasAnyShortcuts: Bool {
        !webShortcuts.isEmpty || webGroups.contains { !$0.shortcuts.isEmpty } || !webGroups.isEmpty
    }

    private let sidebarSelectionTint = DesignSystem.Colors.sidebarSelection

    private var sidebarPortalTitle: String {
        if let college = profileShell.collegeName, !college.isEmpty {
            return college
        }
        return String(localized: "sidebar.default_portal_title")
    }

    var body: some View {
        let compactHeight = measuredHeight < 740
        let isIconOnly = self.isIconOnly
        let topChromeInset = max(32, measuredTopInset + 6)
        sidebarPane(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 0) {
                navigationContent(
                    compactHeight: compactHeight,
                    isIconOnly: isIconOnly,
                    topChromeInset: topChromeInset
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if !isIconOnly && hasAnyShortcuts {
                    shortcutsBottomSection(
                        compactHeight: compactHeight,
                        maxHeight: max(120, measuredHeight * 0.5)
                    )
                }

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                    .padding(.horizontal, isIconOnly ? 8 : 16)

                footerContent(compactHeight: compactHeight, isIconOnly: isIconOnly)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarMetricsReader)
        .padding(.horizontal, isIconOnly ? 0 : 10)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: [.leading])
        .onAppear { refreshProfileShell() }
        .onChange(of: collegePersistence.profileRevision) { _, _ in refreshProfileShell() }
    }

    /// Transparent geometry probe that feeds layout metrics into state. Crucially it
    /// ignores transient zero sizes (reported while the column animates) so the
    /// sidebar content keeps its last good layout instead of collapsing to nothing.
    private var sidebarMetricsReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    updateMetrics(size: proxy.size, topInset: proxy.safeAreaInsets.top)
                }
                .onChange(of: proxy.size) { _, newValue in
                    updateMetrics(size: newValue, topInset: proxy.safeAreaInsets.top)
                }
                .onChange(of: proxy.safeAreaInsets.top) { _, newTop in
                    updateMetrics(size: proxy.size, topInset: newTop)
                }
        }
    }

    private func updateMetrics(size: CGSize, topInset: CGFloat) {
        if size.height > 1 { measuredHeight = size.height }
        measuredTopInset = topInset
    }

    private func refreshProfileShell() {
        profileShell = ProfileReadBridge.shellSnapshot(collegePersistence: collegePersistence)
    }

    private var primarySidebarPages: [(icon: String, title: String, page: AppPage)] {
        [
            ("square.grid.2x2", AppPage.degree.displayTitle, .degree),
            ("graduationcap", AppPage.academics.displayTitle, .academics),
            ("arrow.left.arrow.right.circle", AppPage.transferDatabase.displayTitle, .transferDatabase),
            ("calendar", AppPage.calendar.displayTitle, .calendar),
            ("briefcase", AppPage.career.displayTitle, .career),
            ("sparkles", AppPage.assistant.displayTitle, .assistant),
            ("folder", AppPage.documents.displayTitle, .documents),
        ]
    }

    private func navigationContent(
        compactHeight: Bool,
        isIconOnly: Bool,
        topChromeInset: CGFloat
    ) -> some View {
        VStack(alignment: isIconOnly ? .center : .leading, spacing: 0) {
            sidebarHeader(isIconOnly: isIconOnly, topChromeInset: topChromeInset)

            if isIconOnly {
                iconOnlyNavigationList(compactHeight: compactHeight)
            } else {
                expandedNavigationList(compactHeight: compactHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { reloadShortcutState() }
        .onReceive(NotificationCenter.default.publisher(for: .webShortcutsDidChange)) { _ in
            reloadShortcutState()
            lmsPortalURL = LMSPortalConfiguration.resolvedPortalURL()
            if case .webShortcut(let sid) = activePage, WebShortcutStore.shortcutSync(id: sid) == nil {
                activePage = .degree
            }
        }
    }

    private func reloadShortcutState() {
        webShortcuts = WebShortcutStore.loadAllSync()
        webGroups = WebShortcutStore.loadGroupsSync()
        // Drop expansion state for groups that no longer exist.
        let liveIDs = Set(webGroups.map(\.id))
        let pruned = expandedGroupIDs.intersection(liveIDs)
        if pruned != expandedGroupIDs {
            expandedGroupIDs = pruned
            WebShortcutStore.saveExpandedGroupIDs(pruned)
        }
    }

    @ViewBuilder
    private func sidebarHeader(isIconOnly: Bool, topChromeInset: CGFloat) -> some View {
        Group {
            if isIconOnly {
                workspaceMark
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    workspaceMark
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sidebarPortalTitle)
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(String(localized: "sidebar.workspace"))
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, max(10, topChromeInset - 28))
        .padding(.bottom, isIconOnly ? 12 : 20)
        .padding(.horizontal, isIconOnly ? 8 : 16)
        .help(isIconOnly ? sidebarPortalTitle : "")
    }

    private var workspaceMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                )

            Image(systemName: "graduationcap.fill")
                .foregroundStyle(sidebarSelectionTint)
                .symbolRenderingMode(.hierarchical)
                .font(DesignSystem.Fonts.main(size: 20))
        }
    }

    private func expandedNavigationList(compactHeight: Bool) -> some View {
        // No `selection:` binding: the system sidebar highlight desaturates to gray when
        // the window is inactive. We draw our own accent-tinted row background instead so
        // the active item stays colored regardless of window focus.
        List {
            Section {
                ForEach(primarySidebarPages, id: \.page) { entry in
                    sidebarListRow(
                        icon: entry.icon,
                        title: entry.title,
                        page: entry.page
                    )
                }
            }

            if LMSPortalConfiguration.isLMSTabEnabled() {
                Section(compactHeight ? "" : String(localized: "sidebar.lms_section", defaultValue: "LMS")) {
                    sidebarListRow(
                        icon: "star",
                        siteURL: lmsPortalURL,
                        title: LMSPortalConfiguration.sidebarDisplayTitle,
                        page: .lms
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, compactHeight ? 34 : 40)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func iconOnlyNavigationList(compactHeight: Bool) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(primarySidebarPages, id: \.page) { entry in
                    iconOnlySidebarButton(
                        icon: entry.icon,
                        title: entry.title,
                        page: entry.page
                    )
                }

                if LMSPortalConfiguration.isLMSTabEnabled() {
                    iconOnlySidebarButton(
                        icon: "star",
                        siteURL: lmsPortalURL,
                        title: LMSPortalConfiguration.sidebarDisplayTitle,
                        page: .lms
                    )
                }

                ForEach(iconOnlyShortcuts) { shortcut in
                    iconOnlySidebarButton(
                        icon: shortcut.iconSystemName ?? "link.circle",
                        siteURL: shortcut.iconSystemName == nil ? shortcut.resolvedURL : nil,
                        title: shortcut.title,
                        page: .webShortcut(id: shortcut.id)
                    )
                    .contextMenu {
                        Button(
                            String(localized: "shortcuts.sidebar.remove", defaultValue: "Remove Shortcut"),
                            role: .destructive
                        ) {
                            removeWebShortcut(id: shortcut.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func iconOnlySidebarButton(
        icon: String,
        siteURL: URL? = nil,
        title: String,
        page: AppPage
    ) -> some View {
        let isSelected = activePage == page
        let isHovered = hoveredSidebarPage == page
        Button {
            activePage = page
        } label: {
            SidebarLinkIcon(
                systemIcon: icon,
                siteURL: siteURL,
                isActive: isSelected,
                isHovered: isHovered,
                activeTint: sidebarSelectionTint
            )
            .frame(width: 36, height: 36)
            .background(
                sidebarRowBackground(isSelected: isSelected, isHovered: isHovered),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "sidebar.navigate_hint", defaultValue: "Navigate to \(title)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(sidebarAccessibilityID(for: page))
        .collegeInteractiveSurface(.row, hoverScaleEnabled: false)
        .onHover { hovering in
            hoveredSidebarPage = hovering ? page : nil
        }
    }

    @ViewBuilder
    private func sidebarListRow(
        icon: String,
        siteURL: URL? = nil,
        title: String,
        page: AppPage
    ) -> some View {
        let isSelected = activePage == page
        let isHovered = hoveredSidebarPage == page
        Button {
            activePage = page
        } label: {
            Label {
                LocalizedText(english: title)
                    .lineLimit(1)
            } icon: {
                SidebarLinkIcon(
                    systemIcon: icon,
                    siteURL: siteURL,
                    isActive: isSelected,
                    isHovered: isHovered,
                    activeTint: sidebarSelectionTint
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "sidebar.navigate_hint", defaultValue: "Navigate to \(title)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(sidebarAccessibilityID(for: page))
        .collegeInteractiveSurface(.row, hoverScaleEnabled: false)
        .onHover { hovering in
            hoveredSidebarPage = hovering ? page : nil
        }
    }

    private func sidebarAccessibilityID(for page: AppPage) -> String {
        switch page {
        case .degree: return "sidebar.link.degree"
        case .academics: return "sidebar.link.academics"
        case .transferDatabase: return "sidebar.link.transferDatabase"
        case .calendar: return "sidebar.link.calendar"
        case .career: return "sidebar.link.career"
        case .assistant: return "sidebar.link.assistant"
        case .documents: return "sidebar.link.documents"
        case .lms: return "sidebar.link.lms"
        case .profile: return "sidebar.link.profile"
        case .settings: return "sidebar.link.settings"
        case .webShortcut: return "sidebar.link.webShortcut"
        #if DEBUG
        case .debug: return "sidebar.link.debug"
        #endif
        }
    }

    private func removeWebShortcut(id: UUID) {
        WebShortcutStore.removeShortcutEverywhere(id: id)
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        reloadShortcutState()
        if case .webShortcut(let sid) = activePage, sid == id {
            activePage = .degree
        }
    }

    private var iconOnlyShortcuts: [WebShortcut] {
        webShortcuts + webGroups.flatMap { $0.shortcuts }
    }

    // MARK: - Bottom-anchored shortcuts section

    /// Renders ungrouped shortcuts and collapsible groups, bottom-aligned just above the
    /// footer divider. The list grows upward as items are added and scrolls once it reaches
    /// roughly the middle of the sidebar.
    @ViewBuilder
    private func shortcutsBottomSection(compactHeight: Bool, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compactHeight {
                Text(String(localized: "sidebar.shortcuts_heading", defaultValue: "Shortcuts"))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // Drop a shortcut onto the heading to move it out of any group.
                    .dropDestination(for: String.self) { ids, _ in
                        return handleShortcutDrop(ids, toGroup: nil, atIndex: nil)
                    }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(webShortcuts.enumerated()), id: \.element.id) { index, shortcut in
                        shortcutRow(
                            shortcut: shortcut,
                            leadingInset: 0,
                            dropGroupID: nil,
                            dropIndex: index
                        )
                    }

                    ForEach(webGroups) { group in
                        shortcutGroupView(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ShortcutsContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: min(shortcutsContentHeight, maxHeight))
            .onPreferenceChange(ShortcutsContentHeightKey.self) { shortcutsContentHeight = $0 }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func shortcutGroupView(_ group: WebShortcutGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        shortcutGroupHeaderRow(group, isExpanded: isExpanded)

        if isExpanded {
            ForEach(Array(group.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                shortcutRow(
                    shortcut: shortcut,
                    leadingInset: 18,
                    dropGroupID: group.id,
                    dropIndex: index
                )
            }
        }
    }

    @ViewBuilder
    private func shortcutGroupHeaderRow(_ group: WebShortcutGroup, isExpanded: Bool) -> some View {
        let isHovered = hoveredGroupID == group.id
        Button {
            toggleGroup(group.id)
        } label: {
            HStack(spacing: 0) {
                Label {
                    LocalizedText(english: group.name)
                        .lineLimit(1)
                } icon: {
                    SidebarLinkIcon(
                        systemIcon: "folder",
                        siteURL: nil,
                        isActive: false,
                        isHovered: isHovered,
                        activeTint: sidebarSelectionTint
                    )
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sidebarRowBackground(isSelected: false, isHovered: isHovered))
        )
        .accessibilityLabel(group.name)
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
        .onHover { hovering in
            hoveredGroupID = hovering ? group.id : nil
        }
        .draggable(group.id.uuidString)
        // Drop a shortcut here to move it into the group, or another group here to reorder.
        .dropDestination(for: String.self) { ids, _ in
            return handleDropOnGroupHeader(ids, group: group)
        }
        .contextMenu {
            Button(
                isExpanded
                    ? String(localized: "shortcuts.sidebar.collapse_group", defaultValue: "Collapse Group")
                    : String(localized: "shortcuts.sidebar.expand_group", defaultValue: "Expand Group")
            ) {
                toggleGroup(group.id)
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(
        shortcut: WebShortcut,
        leadingInset: CGFloat,
        dropGroupID: UUID?,
        dropIndex: Int
    ) -> some View {
        let page = AppPage.webShortcut(id: shortcut.id)
        let isSelected = activePage == page
        let isHovered = hoveredSidebarPage == page
        Button {
            activePage = page
        } label: {
            Label {
                LocalizedText(english: shortcut.title)
                    .lineLimit(1)
            } icon: {
                SidebarLinkIcon(
                    systemIcon: shortcut.iconSystemName ?? "link.circle",
                    siteURL: shortcut.iconSystemName == nil ? shortcut.resolvedURL : nil,
                    isActive: isSelected,
                    isHovered: isHovered,
                    activeTint: sidebarSelectionTint
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8 + leadingInset)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(sidebarRowBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .accessibilityLabel(shortcut.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.link.webShortcut")
        .onHover { hovering in
            hoveredSidebarPage = hovering ? page : nil
        }
        .draggable(shortcut.id.uuidString)
        // Drop another shortcut here to reorder it into this position/collection.
        .dropDestination(for: String.self) { ids, _ in
            return handleShortcutDrop(ids, toGroup: dropGroupID, atIndex: dropIndex)
        }
        .contextMenu {
            Button(
                String(localized: "shortcuts.sidebar.remove", defaultValue: "Remove Shortcut"),
                role: .destructive
            ) {
                removeWebShortcut(id: shortcut.id)
            }
        }
    }

    // MARK: - Drag & drop

    /// Moves a dragged shortcut into `groupID` (nil = ungrouped) at `index`. Ignores group drags.
    private func handleShortcutDrop(_ ids: [String], toGroup groupID: UUID?, atIndex index: Int?) -> Bool {
        guard let raw = ids.first, let uuid = UUID(uuidString: raw) else { return false }
        guard WebShortcutStore.allShortcutsSync().contains(where: { $0.id == uuid }) else { return false }
        let moved = WebShortcutStore.moveShortcut(id: uuid, toGroup: groupID, atIndex: index)
        if moved { reloadShortcutState() }
        return moved
    }

    /// Handles a drop on a group header: a shortcut moves into the group; a group reorders.
    private func handleDropOnGroupHeader(_ ids: [String], group: WebShortcutGroup) -> Bool {
        guard let raw = ids.first, let uuid = UUID(uuidString: raw), uuid != group.id else { return false }
        if webGroups.contains(where: { $0.id == uuid }) {
            guard let targetIndex = webGroups.firstIndex(where: { $0.id == group.id }) else { return false }
            WebShortcutStore.moveGroup(id: uuid, toIndex: targetIndex)
            reloadShortcutState()
            return true
        }
        let moved = WebShortcutStore.moveShortcut(id: uuid, toGroup: group.id, atIndex: nil)
        if moved { reloadShortcutState() }
        return moved
    }

    private func toggleGroup(_ id: UUID) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
        WebShortcutStore.saveExpandedGroupIDs(expandedGroupIDs)
    }

    @ViewBuilder
    private func sidebarPane<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }

    private func footerContent(compactHeight: Bool, isIconOnly: Bool) -> some View {
        VStack(spacing: 4) {
            footerSettingsRow(isIconOnly: isIconOnly, compactHeight: compactHeight)
            footerProfileRow(isIconOnly: isIconOnly, compactHeight: compactHeight)
        }
        .padding(.horizontal, isIconOnly ? 8 : 4)
        .padding(.vertical, compactHeight ? 8 : 12)
    }

    @ViewBuilder
    private func footerSettingsRow(isIconOnly: Bool, compactHeight: Bool) -> some View {
        let title = AppPage.settings.displayTitle
        if isIconOnly {
            SettingsLink {
                SidebarLinkIcon(
                    systemIcon: "gearshape",
                    siteURL: nil,
                    isActive: false,
                    isHovered: hoveredFooterSettings,
                    activeTint: sidebarSelectionTint
                )
                .frame(width: 36, height: 36)
                .background(
                    sidebarRowBackground(isSelected: false, isHovered: hoveredFooterSettings),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("sidebar.link.settings")
            .onHover { hoveredFooterSettings = $0 }
        } else {
            SettingsLink {
                sidebarFooterLabel(
                    icon: "gearshape",
                    title: title,
                    isSelected: false,
                    isHovered: hoveredFooterSettings
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: compactHeight ? 34 : 40, alignment: .leading)
            .background(
                sidebarRowBackground(isSelected: false, isHovered: hoveredFooterSettings),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("sidebar.link.settings")
            .onHover { hoveredFooterSettings = $0 }
        }
    }

    @ViewBuilder
    private func footerProfileRow(isIconOnly: Bool, compactHeight: Bool) -> some View {
        let isSelected = activePage == .profile
        let isHovered = hoveredSidebarPage == .profile
        let title = AppPage.profile.displayTitle

        if isIconOnly {
            iconOnlySidebarButton(
                icon: "person.crop.circle",
                title: title,
                page: .profile
            )
        } else {
            Button {
                activePage = .profile
            } label: {
                sidebarFooterLabel(
                    icon: "person.crop.circle",
                    title: title,
                    isSelected: isSelected,
                    isHovered: isHovered
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: compactHeight ? 34 : 40, alignment: .leading)
            .background(
                sidebarRowBackground(isSelected: isSelected, isHovered: isHovered),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(title)
            .accessibilityLabel(title)
            .accessibilityIdentifier("sidebar.link.profile")
            .onHover { hovering in
                hoveredSidebarPage = hovering ? .profile : nil
            }
        }
    }

    @ViewBuilder
    private func sidebarFooterLabel(
        icon: String,
        title: String,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        Label {
            LocalizedText(english: title)
                .lineLimit(1)
        } icon: {
            SidebarLinkIcon(
                systemIcon: icon,
                siteURL: nil,
                isActive: isSelected,
                isHovered: isHovered,
                activeTint: sidebarSelectionTint
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func sidebarRowBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return DesignSystem.Colors.sidebarSelectionFill
        }
        if isHovered {
            return DesignSystem.Colors.sidebarHoverFill
        }
        return .clear
    }
}

private struct ShortcutsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SidebarLinkIcon: View {
    let systemIcon: String
    let siteURL: URL?
    let isActive: Bool
    let isHovered: Bool
    let activeTint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false
    @State private var favicon: NSImage?

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .scaleEffect(hoverScale)
            } else {
                fallbackSymbol
            }
        }
        .animation(motionReduced ? nil : .easeOut(duration: 0.15), value: isHovered)
        .animation(motionReduced ? nil : .easeOut(duration: 0.2), value: isActive)
        .task(id: siteURL) {
            guard let siteURL else {
                favicon = nil
                return
            }
            if let cached = FaviconStore.shared.cachedIcon(for: siteURL) {
                favicon = cached
                return
            }
            favicon = await FaviconStore.shared.icon(for: siteURL)
        }
    }

    private var hoverScale: CGFloat {
        guard !motionReduced, isHovered else { return 1 }
        return 1.08
    }

    private var fallbackSymbol: some View {
        decoratedSymbol
            .font(DesignSystem.Fonts.main(size: 18))
            .foregroundStyle(isActive ? activeTint : .primary)
            .scaleEffect(hoverScale)
    }

    @ViewBuilder
    private var decoratedSymbol: some View {
        let image = Image(systemName: resolvedSymbolName)
        if motionReduced {
            image
        } else {
            // Keep a single, stable image view so selecting an icon plays exactly one
            // bounce. The continuous effects are toggled via `isActive:` (no view-identity
            // swap), which previously caused a second bounce to fire.
            image
                .symbolEffect(
                    .pulse.byLayer,
                    options: .repeating.speed(0.35),
                    isActive: systemIcon == "sparkles" && isActive
                )
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers,
                    isActive: systemIcon == "calendar" && isActive
                )
                .symbolEffect(.bounce, options: .nonRepeating, value: isActive)
        }
    }

    private static let iconsWithoutFillVariant: Set<String> = [
        "calendar",
        "sparkles",
        "star",
        "link.circle",
        "person.crop.circle",
        "gearshape",
    ]

    private var resolvedSymbolName: String {
        if isActive,
           !Self.iconsWithoutFillVariant.contains(systemIcon),
           !systemIcon.hasSuffix(".fill") {
            return "\(systemIcon).fill"
        }
        return systemIcon
    }
}
