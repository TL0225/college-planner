// CatalogLayoutFingerprint.swift
// Feature: Catalog
// Purpose: Stable layout signature per catalog version for drift detection (Tier 2).
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

struct CatalogLayoutFingerprint: Codable, Sendable, Equatable {
    let signatureVersion: Int
    let schoolID: String
    let catalogVersionID: String
    let layoutProfileID: String
    let featureSignature: String
    let recordedAt: Date

    private enum CodingKeys: String, CodingKey {
        case signatureVersion
        case schoolID
        case catalogVersionID
        case layoutProfileID
        case featureSignature
        case recordedAt
    }

    init(
        signatureVersion: Int,
        schoolID: String,
        catalogVersionID: String,
        layoutProfileID: String,
        featureSignature: String,
        recordedAt: Date
    ) {
        self.signatureVersion = signatureVersion
        self.schoolID = schoolID
        self.catalogVersionID = catalogVersionID
        self.layoutProfileID = layoutProfileID
        self.featureSignature = featureSignature
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureVersion = try container.decodeIfPresent(Int.self, forKey: .signatureVersion) ?? 1
        schoolID = try container.decode(String.self, forKey: .schoolID)
        catalogVersionID = try container.decode(String.self, forKey: .catalogVersionID)
        layoutProfileID = try container.decode(String.self, forKey: .layoutProfileID)
        featureSignature = try container.decode(String.self, forKey: .featureSignature)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    }

    static func from(
        metrics: CatalogExtractorMetrics,
        domFeatures: CatalogDOMFeatures? = nil
    ) -> CatalogLayoutFingerprint {
        let profile = (metrics.layoutProfileID ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let material: [String]
        if let domFeatures {
            material = [
                profile,
                "dc:\(domFeatures.detailCodeCount)",
                "ct:\(domFeatures.courseblocktitleCount)",
                "div:\(domFeatures.divCourseblockCount)",
                "dl:\(domFeatures.dlCourseblockCount)",
                "sc:\(domFeatures.scCourselistCount)",
                "p:\(metrics.programsFound)",
                "c:\(metrics.coursesFound)"
            ]
        } else {
            material = [
                "v2",
                profile,
                "source:\(metrics.source)",
                "p:\(metrics.programsFound)",
                "c:\(metrics.coursesFound)",
                "r:\(metrics.requirementsFound)",
                "t:\(metrics.requirementTablesFound)"
            ]
        }
        let digest = SHA256.hash(data: Data(material.joined(separator: "|").utf8))
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return CatalogLayoutFingerprint(
            signatureVersion: 2,
            schoolID: metrics.schoolID,
            catalogVersionID: metrics.catalogVersionID,
            layoutProfileID: profile.isEmpty ? "unknown" : profile,
            featureSignature: signature,
            recordedAt: metrics.recordedAt
        )
    }
}

enum CatalogLayoutFingerprintStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogLayoutFingerprints", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(schoolID: String, catalogVersionID: String) -> URL {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let safeVersion = catalogVersionID.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safeSchool)__\(safeVersion).json")
    }

    static func load(schoolID: String, catalogVersionID: String) -> CatalogLayoutFingerprint? {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogLayoutFingerprint.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ fingerprint: CatalogLayoutFingerprint) {
        let url = fileURL(schoolID: fingerprint.schoolID, catalogVersionID: fingerprint.catalogVersionID)
        if let data = try? JSONEncoder().encode(fingerprint) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Most recently recorded fingerprint for a school (any catalog version).
    #if DEBUG
    static func removeAll(forSchoolID schoolID: String) {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let prefix = "\(safeSchool)__"
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return
        }
        for url in files where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    #endif

    static func latest(forSchoolID schoolID: String) -> CatalogLayoutFingerprint? {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let prefix = "\(safeSchool)__"
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        let matches = files
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .compactMap { url -> CatalogLayoutFingerprint? in
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(CatalogLayoutFingerprint.self, from: data) else {
                    return nil
                }
                return decoded
            }
        return matches.max(by: { $0.recordedAt < $1.recordedAt })
    }
}

enum CatalogLayoutDriftDetector {
    struct Result: Sendable, Equatable {
        let detected: Bool
        let message: String
        let previousProfileID: String?
        let currentProfileID: String
    }

    static func evaluate(
        previous: CatalogLayoutFingerprint?,
        current: CatalogLayoutFingerprint
    ) -> Result {
        guard let previous else {
            return Result(
                detected: false,
                message: "",
                previousProfileID: nil,
                currentProfileID: current.layoutProfileID
            )
        }

        if previous.layoutProfileID != current.layoutProfileID {
            return Result(
                detected: true,
                message: "Layout profile changed from \(previous.layoutProfileID) to \(current.layoutProfileID).",
                previousProfileID: previous.layoutProfileID,
                currentProfileID: current.layoutProfileID
            )
        }

        if previous.signatureVersion != current.signatureVersion || previous.featureSignature != current.featureSignature {
            return Result(
                detected: true,
                message: "Catalog layout fingerprint v\(current.signatureVersion) changed for profile \(current.layoutProfileID).",
                previousProfileID: previous.layoutProfileID,
                currentProfileID: current.layoutProfileID
            )
        }

        return Result(
            detected: false,
            message: "",
            previousProfileID: previous.layoutProfileID,
            currentProfileID: current.layoutProfileID
        )
    }
}
