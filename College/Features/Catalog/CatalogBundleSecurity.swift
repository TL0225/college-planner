// CatalogBundleSecurity.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleSecurityError.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

enum CatalogBundleSecurityError: LocalizedError {
    case hashMismatch
    case signatureInvalid
    case malformedPublicKey
    case unsupportedVersion(String)
    case payloadTooLarge(Int)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .hashMismatch: return "Catalog bundle file is corrupted (checksum mismatch)."
        case .signatureInvalid: return "Catalog bundle signature is invalid or the file was tampered with."
        case .malformedPublicKey: return "Catalog bundle contains an invalid signer public key."
        case .unsupportedVersion(let v): return "Unsupported catalog bundle version: \(v)."
        case .payloadTooLarge(let bytes): return "Catalog bundle is too large (\(bytes) bytes)."
        case .validationFailed(let reason): return "Catalog bundle failed validation: \(reason)"
        }
    }
}

enum CatalogBundleSecurity {
    private static let maxEnvelopeBytes = 50 * 1024 * 1024

    static func sign(bundle: CatalogBundle) throws -> CatalogBundleEnvelope {
        let payloadJSON = try canonicalPayloadJSON(bundle)
        let payloadData = Data(payloadJSON.utf8)
        let payloadHash = sha256Hex(payloadData)

        let privateKey = CatalogSigningKeyManager.shared.privateKey
        let signature = try privateKey.signature(for: payloadData)
        let publicKey = privateKey.publicKey

        return CatalogBundleEnvelope(
            signatureVersion: CatalogBundleEnvelope.signatureVersion,
            algorithm: CatalogBundleEnvelope.algorithm,
            payloadHash: payloadHash,
            signature: CatalogBundleBase64URL.encode(signature),
            signerPublicKey: CatalogBundleBase64URL.encode(publicKey.rawRepresentation),
            signerFingerprint: CatalogSigningKeyManager.fingerprint(for: publicKey),
            payloadJSON: payloadJSON
        )
    }

    static func verify(envelope: CatalogBundleEnvelope) throws -> (bundle: CatalogBundle, fingerprint: String) {
        guard envelope.signatureVersion == CatalogBundleEnvelope.signatureVersion else {
            throw CatalogBundleSecurityError.unsupportedVersion(envelope.signatureVersion)
        }
        guard envelope.algorithm == CatalogBundleEnvelope.algorithm else {
            throw CatalogBundleSecurityError.unsupportedVersion(envelope.algorithm)
        }

        let payloadData = Data(envelope.payloadJSON.utf8)
        let computedHash = sha256Hex(payloadData)
        guard computedHash == envelope.payloadHash else {
            throw CatalogBundleSecurityError.hashMismatch
        }

        guard let publicKeyData = CatalogBundleBase64URL.decode(envelope.signerPublicKey),
              publicKeyData.count == 32 else {
            throw CatalogBundleSecurityError.malformedPublicKey
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard let signatureData = CatalogBundleBase64URL.decode(envelope.signature) else {
            throw CatalogBundleSecurityError.signatureInvalid
        }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw CatalogBundleSecurityError.signatureInvalid
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(CatalogBundle.self, from: payloadData)
        return (bundle, envelope.signerFingerprint)
    }

    static func verifyFile(at url: URL) throws -> (bundle: CatalogBundle, envelope: CatalogBundleEnvelope, fingerprint: String) {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maxEnvelopeBytes else {
            throw CatalogBundleSecurityError.payloadTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(CatalogBundleEnvelope.self, from: data)
        let (bundle, fingerprint) = try verify(envelope: envelope)
        return (bundle, envelope, fingerprint)
    }

    static func encodeEnvelope(_ envelope: CatalogBundleEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    private static func canonicalPayloadJSON(_ bundle: CatalogBundle) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CatalogBundleSecurityError.validationFailed("Failed to encode payload as UTF-8")
        }
        return string
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Validation

enum CatalogBundleValidationResult {
    case valid
    case invalid(reason: String)
}

enum CatalogBundleValidator {
    private static let maxCourses = 50_000
    private static let maxPrograms = 5_000
    private static let maxRequirementSections = 100_000
    private static let maxStringLength = 10_000
    private static let maxCredits = 30.0
    private static let maxTotalCreditsRequired = 300

    private static let knownDegreeLevels: Set<String> = [
        "Undergraduate", "Graduate", "PhD", "Associate", "Certificate", "Doctoral",
        "undergraduate", "graduate", "phd", "associate", "certificate", "doctoral",
    ]

    static func validate(_ bundle: CatalogBundle) -> CatalogBundleValidationResult {
        guard bundle.bundleVersion == CatalogBundle.currentVersion else {
            return .invalid(reason: "Unsupported bundle version \(bundle.bundleVersion)")
        }
        let school = bundle.schoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !school.isEmpty else {
            return .invalid(reason: "Missing school name")
        }
        guard bundle.courses.count <= maxCourses else {
            return .invalid(reason: "Too many courses (\(bundle.courses.count))")
        }
        guard bundle.programs.count <= maxPrograms else {
            return .invalid(reason: "Too many programs (\(bundle.programs.count))")
        }
        guard bundle.requirementSections.count <= maxRequirementSections else {
            return .invalid(reason: "Too many requirement sections")
        }

        for course in bundle.courses {
            if let err = validateCourse(course) { return .invalid(reason: err) }
        }
        for program in bundle.programs {
            if let err = validateString(program.name, field: "program name") { return .invalid(reason: err) }
            if !knownDegreeLevels.contains(program.degreeLevel),
               !program.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Permissive: allow unknown levels but reject empty
            }
        }
        for section in bundle.requirementSections {
            if let err = validateString(section.major, field: "major") { return .invalid(reason: err) }
            if section.creditsRequired < 0 || section.creditsRequired > maxTotalCreditsRequired {
                return .invalid(reason: "Invalid creditsRequired on requirement section")
            }
        }
        return .valid
    }

    private static func validateCourse(_ course: CatalogCourse) -> String? {
        let code = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return "Empty course code" }
        guard code.count <= 64 else { return "Course code too long" }
        if code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Course code contains control characters"
        }
        let credits = Double(course.credits)
        if credits < 0 || credits > maxCredits {
            return "Invalid credits for \(code)"
        }
        if let err = validateString(course.title, field: "title") { return err }
        if let desc = course.description, let err = validateString(desc, field: "description") { return err }
        return nil
    }

    private static func validateString(_ value: String, field: String) -> String? {
        guard value.count <= maxStringLength else {
            return "\(field) exceeds maximum length"
        }
        if value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) {
            return "\(field) contains invalid control characters"
        }
        return nil
    }
}
