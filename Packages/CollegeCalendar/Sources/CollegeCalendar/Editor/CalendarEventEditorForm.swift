// CalendarEventEditorForm.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventEditorForm.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Phase 3: extracted editor form sections (grows as overlay is decomposed).
enum CalendarEventEditorForm {
    static func titleField(text: Binding<String>) -> some View {
        TextField("Title", text: text)
            .textFieldStyle(.roundedBorder)
    }
}
