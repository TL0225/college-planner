// AcademicCalendarPreviewSheet.swift
// Feature: Calendar
// Purpose: Preview and confirm academic calendar imports.

import SwiftUI

struct AcademicCalendarPreviewSheet: View {
    let events: [AcademicCalendarParsedEvent]
    let changes: [AcademicCalendarSyncChange]
    let isRefreshDiff: Bool
    let onConfirm: ([AcademicCalendarParsedEvent]) -> Void
    let onCancel: () -> Void

    @State private var includedIDs: Set<String> = []

    private var lowConfidence: [AcademicCalendarParsedEvent] {
        events.filter(\.isLowConfidence)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRefreshDiff ? "Review Calendar Changes" : "Review Import")
                .font(DesignSystem.Fonts.title3(weight: .semibold))

            if !lowConfidence.isEmpty {
                Text("Review these \(lowConfidence.count) low-confidence event(s)")
                    .font(DesignSystem.Fonts.caption1(weight: .semibold))
                    .foregroundStyle(.orange)
            }

            if isRefreshDiff, !changes.isEmpty {
                ForEach(changes) { change in
                    HStack {
                        Text(change.kind.rawValue.capitalized)
                            .font(DesignSystem.Fonts.caption1(weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(change.title)
                            .font(DesignSystem.Fonts.body())
                        if let detail = change.detail {
                            Text(detail)
                                .font(DesignSystem.Fonts.caption1())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            List {
                ForEach(events) { event in
                    Toggle(isOn: binding(for: event)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(DesignSystem.Fonts.body(weight: event.isLowConfidence ? .semibold : .regular))
                            Text(dateLabel(for: event))
                                .font(DesignSystem.Fonts.caption1())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 360)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Import \(includedIDs.count) Events") {
                    let selected = events.filter { includedIDs.contains($0.id) }
                    onConfirm(selected)
                }
                .buttonStyle(.borderedProminent)
                .disabled(includedIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .onAppear {
            includedIDs = Set(events.map(\.id))
        }
    }

    private func binding(for event: AcademicCalendarParsedEvent) -> Binding<Bool> {
        Binding(
            get: { includedIDs.contains(event.id) },
            set: { isOn in
                if isOn { includedIDs.insert(event.id) } else { includedIDs.remove(event.id) }
            }
        )
    }

    private func dateLabel(for event: AcademicCalendarParsedEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            return formatter.string(from: event.startDate)
        }
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }
}

#Preview {
    AcademicCalendarPreviewSheet(
        events: [
            AcademicCalendarParsedEvent(
                id: "1", title: "Classes Begin", startDate: .now, endDate: .now, allDay: true,
                status: .confirmed, term: "Fall", year: 2025, level: .all, confidence: 0.4,
                scopeKey: "fall|2025|all|", identityKey: "k1", identitySignature: "s1",
                providerEventId: nil, notes: nil, isLowConfidence: true
            )
        ],
        changes: [],
        isRefreshDiff: false,
        onConfirm: { _ in },
        onCancel: {}
    )
}
