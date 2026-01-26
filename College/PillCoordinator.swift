import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
final class PillCoordinator: ObservableObject {
    enum Selection: Equatable {
        case event(uri: URL)
        case task(uri: URL)
    }

    struct AddEventPrefill: Equatable {
        var semesterID: UUID?
        var title: String?
        var start: Date?
        var end: Date?
    }

    @Published var selection: Selection? = nil

    @Published var isAddEventPresented: Bool = false
    @Published var addEventPrefill: AddEventPrefill = .init(semesterID: nil, title: nil, start: nil, end: nil)

    // One-shot escape hatch: some surfaces (e.g. the calendar grid) should be able to
    // update the add-event prefill without that click also being treated as an
    // "outside click" that dismisses the editor.
    @Published var suppressNextOutsideDismiss: Bool = false

    private var suppressOutsideDismissUntil: Date = .distantPast

    var isOutsideDismissSuppressed: Bool {
        Date() < suppressOutsideDismissUntil
    }

    var hasSelection: Bool { selection != nil }

    private func setSelection(_ newSelection: Selection?, animated: Bool) {
        // Keep the pill in a single mode: either inspecting a selection OR adding.
        if isAddEventPresented {
            isAddEventPresented = false
        }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = newSelection
            }
        } else {
            selection = newSelection
        }
    }

    private func setAddEventPresented(_ isPresented: Bool, prefill: AddEventPrefill?, animated: Bool) {
        if isPresented {
            // Keep the pill in a single mode.
            selection = nil
            addEventPrefill = prefill ?? .init(semesterID: nil, title: nil, start: nil, end: nil)
        }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isAddEventPresented = isPresented
            }
        } else {
            isAddEventPresented = isPresented
        }

        if !isPresented {
            addEventPrefill = .init(semesterID: nil, title: nil, start: nil, end: nil)
        }
    }

    func selectEvent(objectID: NSManagedObjectID, animated: Bool = true) {
        setSelection(.event(uri: objectID.uriRepresentation()), animated: animated)
    }

    func selectEvent(objectID: NSManagedObjectID, in context: NSManagedObjectContext, animated: Bool = true) {
        var finalObjectID = objectID
        if objectID.isTemporaryID {
            do {
                let object = try context.existingObject(with: objectID)
                try context.obtainPermanentIDs(for: [object])
                finalObjectID = object.objectID
            } catch {
                // If we can't obtain a permanent ID, fall back to the temporary URI.
                finalObjectID = objectID
            }
        }
        setSelection(.event(uri: finalObjectID.uriRepresentation()), animated: animated)
    }

    func selectTask(objectID: NSManagedObjectID, animated: Bool = true) {
        setSelection(.task(uri: objectID.uriRepresentation()), animated: animated)
    }

    func selectTask(objectID: NSManagedObjectID, in context: NSManagedObjectContext, animated: Bool = true) {
        var finalObjectID = objectID
        if objectID.isTemporaryID {
            do {
                let object = try context.existingObject(with: objectID)
                try context.obtainPermanentIDs(for: [object])
                finalObjectID = object.objectID
            } catch {
                finalObjectID = objectID
            }
        }
        setSelection(.task(uri: finalObjectID.uriRepresentation()), animated: animated)
    }

    func clearSelection(animated: Bool = true) {
        setSelection(nil, animated: animated)
    }

    func presentAddEvent(prefill: AddEventPrefill? = nil, animated: Bool = true) {
        // Add-event panel removed.
        // Keep this as a no-op so existing call sites don't break compilation.
        return
    }

    func suppressOutsideDismissOnce() {
        suppressNextOutsideDismiss = true
    }

    func suppressOutsideDismiss(for seconds: TimeInterval) {
        suppressOutsideDismissUntil = Date().addingTimeInterval(max(0, seconds))
    }

    func dismissAddEvent(animated: Bool = true) {
        setAddEventPresented(false, prefill: nil, animated: animated)
    }
}
