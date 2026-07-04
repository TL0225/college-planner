// DocumentsWidget.swift
// Feature: Overview
// Purpose: Overview module — DocumentsWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  DocumentsWidget.swift
//  College
//
//  Shows the 3 most recently opened vault documents.
//

import SwiftUI

struct DocumentsWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var dataRefreshToken = 0

    private var recentDocuments: [OverviewDocumentSummary] {
        _ = dataRefreshToken
        return OverviewReadBridge.recentDocuments(limit: 3, collegePersistence: collegePersistence)
    }

    var body: some View {
        OverviewCard {
            OverviewWidgetHeader("Recent Documents", systemImage: "doc.fill", accentColor: WidgetCategory.productivity.accentColor)

            Color.clear.frame(height: 16)

            if recentDocuments.isEmpty {
                OverviewWidgetEmptyState(
                    title: "No documents yet",
                    message: "Recently opened Vault files will appear here.",
                    systemImage: "doc.text",
                    accentColor: .indigo
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentDocuments) { doc in
                        documentRow(doc)
                    }
                }
            }
        }
        .background {
            OverviewQueryHost { dataRefreshToken += 1 }
        }
    }

    // MARK: - Row

    private func documentRow(_ doc: OverviewDocumentSummary) -> some View {
        let (iconName, iconColor) = documentIconInfo(doc)
        let dateLabel = relativeDocumentDate(doc)

        return OverviewWidgetRowSurface(accentColor: iconColor) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.displayName)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(dateLabel)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func documentIconInfo(_ doc: OverviewDocumentSummary) -> (String, Color) {
        let name = (doc.fileName ?? doc.displayName).lowercased()
        if      name.hasSuffix(".pdf")              { return ("doc.fill", .red) }
        else if name.hasSuffix(".docx") || name.hasSuffix(".doc") { return ("doc.text.fill", .blue) }
        else if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") { return ("tablecells.fill", .green) }
        else if name.hasSuffix(".pptx") || name.hasSuffix(".ppt") { return ("rectangle.on.rectangle.fill", .orange) }
        else { return ("doc.fill", .indigo) }
    }

    private func relativeDocumentDate(_ doc: OverviewDocumentSummary) -> String {
        let date = doc.lastOpenedAt ?? doc.addedAt ?? Date.distantPast
        let ago  = Date().timeIntervalSince(date)
        if ago < 3600    { return "Opened \(Int(ago / 60)) min ago" }
        if ago < 86400   { return "Opened today" }
        if ago < 172800  { return "Yesterday" }
        let days = Int(ago / 86400)
        if days < 7 { return "\(days) days ago" }
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "documents",
            displayName:   "Recent Documents",
            description:   "Quick access to the 3 most recently opened vault documents.",
            category:      .productivity,
            iconName:      "doc.fill",
            accentColor:   Color(hex: "6366F1"),
            defaultHeight: 190,
            minHeight:     150,
            makePreview: { DocumentsWidgetPreview() }
        )
    }
}

// MARK: - Preview

private struct DocumentsWidgetPreview: View {
    private let docs: [(String, String, Color, Color)] = [
        ("doc.fill",                    "Syllabus_CSE312.pdf",    Color(hex: "EF4444"), Color(hex: "FEF2F2")),
        ("doc.text.fill",               "Lab_Report_Draft.docx",  Color(hex: "3B82F6"), Color(hex: "EFF6FF")),
        ("rectangle.on.rectangle.fill", "Lecture_Slides.pptx",    Color(hex: "F97316"), Color(hex: "FFF7ED")),
    ]
    var body: some View {
        OverviewCard {
            Text("Recent Documents")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold, design: .serif))
                .foregroundStyle(DesignSystem.Colors.textMain).padding(.bottom, 12)
            VStack(spacing: 7) {
                ForEach(docs, id: \.1) { icon, name, color, bg in
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(DesignSystem.Fonts.main(size: 12)).foregroundStyle(color)
                            .frame(width: 32, height: 32).background(bg)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(name).font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textMain).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(hex: "F9FAFB").opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
}
