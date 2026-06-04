// AppCommandPalette.swift
// Feature: Core
// Purpose: Core module — AppCommandPalette.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Phase 7: global command palette (⌘K / ⌘N) — routes to NL parser + write pipeline.
struct AppCommandPalette: View {
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var isParsing = false
    @State private var errorMessage: String?

    var body: some View {
        if isPresented {
            VStack(spacing: 12) {
                TextField("Add event or command…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await submit() } }

                if isParsing {
                    ProgressView("Parsing…")
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                HStack {
                    Button("Cancel") { isPresented = false }
                    Spacer()
                    Button("Create Event") { Task { await submit() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                }
            }
            .padding(16)
            .frame(width: 420)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }

    @MainActor
    private func submit() async {
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }

        do {
            let intent = try await NaturalLanguageEventParser.parse(query)
            let start = intent.start ?? Date()
            let end = intent.end ?? start.addingTimeInterval(3600)
            let input = CalendarEventWriteInput(
                title: intent.title,
                startDate: start,
                endDate: end,
                allDay: intent.allDay
            )
            _ = try await CalendarEventWritePipeline.shared.create(input: input)
            isPresented = false
            query = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
