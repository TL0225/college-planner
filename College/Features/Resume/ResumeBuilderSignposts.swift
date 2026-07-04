// ResumeBuilderSignposts.swift
// Feature: Resume
// Purpose: Instruments signposts for resume builder hot paths.

import Foundation
import os

enum ResumeBuilderSignposts {
    static let log = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)

    // MARK: - Typst compile

    @discardableResult
    static func beginTypstCompile() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ResumeTypstCompile", signpostID: id)
        return id
    }

    static func endTypstCompile(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeTypstCompile", signpostID: signpostID)
    }

    // MARK: - Builder save

    @discardableResult
    static func beginBuilderSave() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ResumeBuilderSave", signpostID: id)
        return id
    }

    static func endBuilderSave(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeBuilderSave", signpostID: signpostID)
    }

    // MARK: - Ingest

    @discardableResult
    static func beginIngestFastPath(documentID: UUID) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "ResumeIngestFastPath",
            signpostID: id,
            "documentID=%{public}s",
            documentID.uuidString
        )
        return id
    }

    static func endIngestFastPath(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeIngestFastPath", signpostID: signpostID)
    }

    @discardableResult
    static func beginIngestFull(documentID: UUID) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "ResumeIngestFull",
            signpostID: id,
            "documentID=%{public}s",
            documentID.uuidString
        )
        return id
    }

    static func endIngestFull(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeIngestFull", signpostID: signpostID)
    }

    // MARK: - ATS scoring

    @discardableResult
    static func beginATSScoreAll() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ResumeATSScoreAll", signpostID: id)
        return id
    }

    static func endATSScoreAll(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeATSScoreAll", signpostID: signpostID)
    }

    // MARK: - Export / adaptation (later phases)

    @discardableResult
    static func beginDOCXExport() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ResumeDOCXExport", signpostID: id)
        return id
    }

    static func endDOCXExport(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumeDOCXExport", signpostID: signpostID)
    }

    @discardableResult
    static func beginPlatformAdapt(platform: String) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: "ResumePlatformAdapt",
            signpostID: id,
            "platform=%{public}s",
            platform
        )
        return id
    }

    static func endPlatformAdapt(_ signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: "ResumePlatformAdapt", signpostID: signpostID)
    }
}
