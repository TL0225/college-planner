// ResumeEntryDragItem.swift
// Feature: Resume
// Purpose: Drag payload for reordering entries within a resume section.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ResumeEntryDragItem: Codable, Hashable, Sendable {
    let section: ResumeSectionKind
    let entryID: UUID
}

extension UTType {
    static let resumeEntry = UTType(exportedAs: "Timothy.College.resume-entry", conformingTo: .data)
}

extension ResumeEntryDragItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .resumeEntry)
    }
}
