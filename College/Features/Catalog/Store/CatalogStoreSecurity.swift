// CatalogStoreSecurity.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogStoreEnvelope.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit

struct CatalogStoreEnvelope: Codable, Sendable {
    static let signatureVersion = "1"
    static let algorithm = "Ed25519"

    let signatureVersion: String
    let algorithm: String
    let schoolID: String
    let storeSchemaVersion: String
    let sqliteSHA256: String
    let signerPublicKey: String
    let signerFingerprint: String
    let signature: String
    let createdAt: Date
}

enum CatalogStoreSecurityError: LocalizedError {
    case invalidFormat
    case hashMismatch
    case invalidSignature
    case malformedPublicKey
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid signed catalog store format."
        case .hashMismatch: return "Signed catalog store checksum mismatch."
        case .invalidSignature: return "Signed catalog store signature is invalid."
        case .malformedPublicKey: return "Malformed signer public key."
        case .unsupportedVersion: return "Unsupported signed catalog store version."
        }
    }
}

enum CatalogStoreSecurity {
    private static let magic = Data("COLCATSQL".utf8)

    static func createSignedFile(
        schoolID: String,
        sqliteData: Data,
        storeSchemaVersion: String = "1.0"
    ) throws -> Data {
        let hash = sha256Hex(sqliteData)
        let privateKey = CatalogSigningKeyManager.shared.privateKey
        let payloadToSign = Data("\(schoolID)|\(storeSchemaVersion)|\(hash)".utf8)
        let signature = try privateKey.signature(for: payloadToSign)

        let envelope = CatalogStoreEnvelope(
            signatureVersion: CatalogStoreEnvelope.signatureVersion,
            algorithm: CatalogStoreEnvelope.algorithm,
            schoolID: schoolID,
            storeSchemaVersion: storeSchemaVersion,
            sqliteSHA256: hash,
            signerPublicKey: CatalogBundleBase64URL.encode(privateKey.publicKey.rawRepresentation),
            signerFingerprint: CatalogSigningKeyManager.fingerprint(for: privateKey.publicKey),
            signature: CatalogBundleBase64URL.encode(signature),
            createdAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let envelopeData = try encoder.encode(envelope)

        var out = Data()
        out.append(magic)
        out.append(UInt32(envelopeData.count).littleEndianData)
        out.append(envelopeData)
        out.append(sqliteData)
        return out
    }

    static func verifySignedFile(_ data: Data) throws -> (envelope: CatalogStoreEnvelope, sqliteData: Data) {
        guard data.count > magic.count + 4 else { throw CatalogStoreSecurityError.invalidFormat }
        guard data.prefix(magic.count) == magic else { throw CatalogStoreSecurityError.invalidFormat }

        let lenData = data.subdata(in: magic.count..<(magic.count + 4))
        let envelopeLen = Int(UInt32(littleEndianData: lenData))
        let envelopeStart = magic.count + 4
        let envelopeEnd = envelopeStart + envelopeLen
        guard envelopeEnd <= data.count else { throw CatalogStoreSecurityError.invalidFormat }

        let envelopeData = data.subdata(in: envelopeStart..<envelopeEnd)
        let sqliteData = data.subdata(in: envelopeEnd..<data.count)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(CatalogStoreEnvelope.self, from: envelopeData)

        guard envelope.signatureVersion == CatalogStoreEnvelope.signatureVersion,
              envelope.algorithm == CatalogStoreEnvelope.algorithm else {
            throw CatalogStoreSecurityError.unsupportedVersion
        }

        let computedHash = sha256Hex(sqliteData)
        guard computedHash == envelope.sqliteSHA256 else {
            throw CatalogStoreSecurityError.hashMismatch
        }

        guard let publicKeyData = CatalogBundleBase64URL.decode(envelope.signerPublicKey),
              publicKeyData.count == 32 else {
            throw CatalogStoreSecurityError.malformedPublicKey
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard let signatureData = CatalogBundleBase64URL.decode(envelope.signature) else {
            throw CatalogStoreSecurityError.invalidSignature
        }
        let payloadToSign = Data("\(envelope.schoolID)|\(envelope.storeSchemaVersion)|\(envelope.sqliteSHA256)".utf8)
        guard publicKey.isValidSignature(signatureData, for: payloadToSign) else {
            throw CatalogStoreSecurityError.invalidSignature
        }
        return (envelope, sqliteData)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }

    init(littleEndianData data: Data) {
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dst in
            dst.copyBytes(from: data.prefix(4))
        }
        self = UInt32(littleEndian: value)
    }
}
