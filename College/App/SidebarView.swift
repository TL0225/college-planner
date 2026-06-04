// SidebarView.swift
// Feature: App
// Purpose: App module — SidebarView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct SidebarView: View {
    @Binding var activePage: AppPage
    /// When the leading column is shown, ``SafeSidebarToggleView`` sits in this column’s branded header row (alongside portal chrome), not only in ``AppToolbarCoordinator`` — when collapsed to detail‑only it appears only in the window toolbar instead.
    var showLeadingMainSidebarToggle: Bool = false
    var onMainSidebarToggleIntent: (() -> Void)? = nil

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var profileShell: ProfileShellSnapshot = ProfileReadBridge.shellSnapshot()

    @State private var hoveredFooterActionID: String?
    @State private var webShortcuts: [WebShortcut] = WebShortcutStore.loadAllSync()
    @State private var lmsPortalURL: URL = LMSPortalConfiguration.resolvedPortalURL()

    private let sidebarSelectionTint = DesignSystem.Colors.sidebarSelection

    private struct FooterAction: Identifiable {
        enum Kind {
            case settings
            case profile
        }

        let id: String
        let kind: Kind
        let icon: String
        let helpText: String
    }

    private var footerActions: [FooterAction] {
        var actions: [FooterAction] = []

        actions.append(
            FooterAction(
                id: "settings",
                kind: .settings,
                icon: "gearshape.fill",
                helpText: String(localized: "app.page.settings")
            )
        )

        actions.append(
            FooterAction(
                id: "profile",
                kind: .profile,
                icon: "person.crop.circle",
                helpText: AppPage.profile.displayTitle
            )
        )

        return actions
    }

    private var sidebarPortalTitle: String {
        if let college = profileShell.collegeName, !college.isEmpty {
            return college
        }
        return String(localized: "sidebar.default_portal_title")
    }

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 740
            let topChromeInset = max(32, proxy.safeAreaInsets.top + 6)
            sidebarPane(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    navigationContent(compactHeight: compactHeight, topChromeInset: topChromeInset, showLeadingMainSidebarToggle: showLeadingMainSidebarToggle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, 16)

                    footerContent(compactHeight: compactHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: [.leading])
        .onAppear { refreshProfileShell() }
        .onChange(of: collegePersistence.profileRevision) { _, _ in refreshProfileShell() }
    }

    private func refreshProfileShell() {
        profileShell = ProfileReadBridge.shellSnapshot(collegePersistence: collegePersistence)
    }

    private func navigationContent(compactHeight: Bool, topChromeInset: CGFloat, showLeadingMainSidebarToggle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if showLeadingMainSidebarToggle {
                    SafeSidebarToggleView(onToggleIntent: onMainSidebarToggleIntent)
                }

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
                        .font(.system(size: 20))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(sidebarPortalTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(localized: "sidebar.workspace"))
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, max(10, topChromeInset - 28))
            .padding(.bottom, 20)
            .padding(.horizontal, -10)
            .padding(.horizontal, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    SidebarLink(icon: "square.grid.2x2", title: AppPage.degree.displayTitle, page: .degree, activePage: $activePage, activeTint: sidebarSelectionTint)
                    SidebarLink(icon: "graduationcap", title: AppPage.academics.displayTitle, page: .academics, activePage: $activePage, activeTint: sidebarSelectionTint)
                    SidebarLink(icon: "calendar", title: AppPage.calendar.displayTitle, page: .calendar, activePage: $activePage, activeTint: sidebarSelectionTint)
                    SidebarLink(icon: "briefcase", title: AppPage.career.displayTitle, page: .career, activePage: $activePage, activeTint: sidebarSelectionTint)
                    SidebarLink(icon: "sparkles", title: AppPage.assistant.displayTitle, page: .assistant, activePage: $activePage, activeTint: sidebarSelectionTint)
                    SidebarLink(icon: "folder", title: AppPage.documents.displayTitle, page: .documents, activePage: $activePage, activeTint: sidebarSelectionTint)

                    if !compactHeight {
                        Text("---- LMS ----")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(1.1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }

                    SidebarLink(
                        icon: "star",
                        iconURL: faviconURL(for: lmsPortalURL),
                        title: LMSPortalConfiguration.sidebarDisplayTitle,
                        page: .brightspace,
                        activePage: $activePage,
                        activeTint: sidebarSelectionTint
                    )

                    if !webShortcuts.isEmpty {
                        Text(String(localized: "sidebar.shortcuts_heading", defaultValue: "---- SHORTCUTS ----"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(1.1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compactHeight ? 3 : 6)

                        ForEach(webShortcuts) { sc in
                            SidebarLink(
                                icon: "link.circle",
                                iconURL: faviconURL(for: sc.resolvedURL),
                                title: sc.title,
                                page: .webShortcut(id: sc.id),
                                activePage: $activePage,
                                activeTint: sidebarSelectionTint
                            )
                            .contextMenu {
                                Button(
                                    String(localized: "shortcuts.sidebar.remove", defaultValue: "Remove Shortcut"),
                                    role: .destructive
                                ) {
                                    removeWebShortcut(id: sc.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, compactHeight ? 10 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { webShortcuts = WebShortcutStore.loadAllSync() }
            .onReceive(NotificationCenter.default.publisher(for: .webShortcutsDidChange)) { _ in
                webShortcuts = WebShortcutStore.loadAllSync()
                lmsPortalURL = LMSPortalConfiguration.resolvedPortalURL()
                if case .webShortcut(let sid) = activePage, WebShortcutStore.shortcutSync(id: sid) == nil {
                    activePage = .degree
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func faviconURL(for siteURL: URL?) -> URL? {
        guard let host = siteURL?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/favicon.ico"
        return components.url
    }

    private func removeWebShortcut(id: UUID) {
        var next = webShortcuts
        next.removeAll { $0.id == id }
        webShortcuts = next
        WebShortcutStore.saveAll(next)
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        if case .webShortcut(let sid) = activePage, sid == id {
            activePage = .degree
        }
    }

    @ViewBuilder
    private func sidebarPane<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }

    private func footerContent(compactHeight: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(footerActions.enumerated()), id: \.element.id) { index, action in
                    footerActionCell(action)
                        .frame(maxWidth: .infinity, minHeight: compactHeight ? 30 : 34)
                        .overlay(alignment: .trailing) {
                            if index < footerActions.count - 1 {
                                RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                                    .fill(Color.primary.opacity(0.22))
                                    .frame(width: 1, height: 16)
                                    .offset(x: 0.5)
                            }
                        }
                }
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, compactHeight ? 8 : 12)
        }
    }

    @ViewBuilder
    private func footerActionCell(_ action: FooterAction) -> some View {
        switch action.kind {
        case .settings:
            SettingsLink {
                footerActionIcon(symbol: action.icon, isHovered: hoveredFooterActionID == action.id)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.footer.settings")
            .help(action.helpText)
            .onHover { hovering in
                hoveredFooterActionID = hovering ? action.id : nil
            }

        case .profile:
            Button {
                activePage = .profile
            } label: {
                footerActionIcon(symbol: action.icon, isHovered: hoveredFooterActionID == action.id)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.footer.profile")
            .help(action.helpText)
            .onHover { hovering in
                hoveredFooterActionID = hovering ? action.id : nil
            }
        }
    }

    private func footerActionIcon(symbol: String, isHovered: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(isHovered ? DesignSystem.Colors.sidebarHoverFill : Color.clear)
    }
}

struct SidebarLink: View {
    let icon: String
    let iconURL: URL?
    let title: String
    let page: AppPage
    @Binding var activePage: AppPage
    let activeTint: Color

    init(
        icon: String,
        iconURL: URL? = nil,
        title: String,
        page: AppPage,
        activePage: Binding<AppPage>,
        activeTint: Color
    ) {
        self.icon = icon
        self.iconURL = iconURL
        self.title = title
        self.page = page
        self._activePage = activePage
        self.activeTint = activeTint
    }
    
    var isActive: Bool {
        activePage == page
    }

    private var accessibilityID: String {
        switch page {
        case .degree: return "sidebar.link.degree"
        case .academics: return "sidebar.link.academics"
        case .calendar: return "sidebar.link.calendar"
        case .career: return "sidebar.link.career"
        case .assistant: return "sidebar.link.assistant"
        case .documents: return "sidebar.link.documents"
        case .brightspace: return "sidebar.link.brightspace"
        case .profile: return "sidebar.link.profile"
        case .settings: return "sidebar.link.settings"
        case .webShortcut: return "sidebar.link.webShortcut"
        #if DEBUG
        case .debug: return "sidebar.link.debug"
        #endif
        }
    }
    
    var body: some View {
        Button(action: {
            activePage = page
        }) {
            HStack(spacing: 12) {
                SidebarLinkIcon(
                    systemIcon: icon,
                    iconURL: iconURL,
                    isActive: isActive,
                    activeTint: activeTint
                )
                .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 15, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? activeTint : .primary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(isActive ? DesignSystem.Colors.sidebarSelectionFill : Color.clear)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(activeTint.opacity(0.25), lineWidth: 0.8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct SidebarLinkIcon: View {
    let systemIcon: String
    let iconURL: URL?
    let isActive: Bool
    let activeTint: Color

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    default:
                        fallbackSymbol
                    }
                }
            } else {
                fallbackSymbol
            }
        }
    }

    private var fallbackSymbol: some View {
        Image(systemName: (isActive && systemIcon != "calendar") ? "\(systemIcon).fill" : systemIcon)
            .font(.system(size: 18))
            .foregroundStyle(isActive ? activeTint : .primary)
    }
}
