// CatalogCapabilityUI.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCapabilityUI.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CollegePersistence.CatalogCapability {
    var isCatalogIndexing: Bool {
        !coursesReady || !vectorsReady
    }

    var programPickerBlockedReason: String? {
        if programsReady { return nil }
        return String(
            localized: "catalog.capability.programs_indexing",
            defaultValue: "Program list is still indexing. Watch the menu bar for progress, or wait a moment and try again."
        )
    }

    var courseSearchBlockedReason: String? {
        if coursesReady { return nil }
        if programsReady {
            return String(
                localized: "catalog.capability.courses_indexing",
                defaultValue: "Course catalog is still importing. Check the menu bar for live progress."
            )
        }
        return String(
            localized: "catalog.capability.not_ready",
            defaultValue: "Catalog sync is still running. Finish onboarding or wait for background import."
        )
    }

    var requirementsBlockedReason: String? {
        if requirementsReady { return nil }
        if programsReady {
            return String(
                localized: "catalog.capability.requirements_indexing",
                defaultValue: "Degree requirements are still indexing. You can browse programs; requirement details will fill in shortly."
            )
        }
        return courseSearchBlockedReason
    }

    var assistantCatalogSummary: String? {
        if !programsReady {
            return String(
                localized: "catalog.capability.assistant.programs",
                defaultValue: "Catalog programs are still indexing."
            )
        }
        if !coursesReady {
            return String(
                localized: "catalog.capability.assistant.courses",
                defaultValue: "Catalog courses are still importing."
            )
        }
        if !vectorsReady {
            return String(
                localized: "catalog.capability.assistant.vectors",
                defaultValue: "Catalog search index is still building. Course data is available; semantic search will improve shortly."
            )
        }
        return nil
    }
}
