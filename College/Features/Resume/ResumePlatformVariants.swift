// ResumePlatformVariants.swift
// Feature: Resume
// Purpose: Persist named platform-adapted canonical profiles on vault resume metadata.

import Foundation
import CollegeCareer

enum ResumePlatformVariants {
    typealias VariantMap = [String: String]

    static func save(
        profile: ResumeCanonicalProfile,
        platform: JobBoardPlatform,
        metadata: inout CareerResumeMetadataV1
    ) {
        var map = decodeMap(from: metadata.platformVariantsJSON)
        guard let json = profile.encodedJSON() else { return }
        map[platform.rawValue] = json
        metadata.platformVariantsJSON = encodeMap(map)
        metadata.platformTarget = platform.rawValue
    }

    static func profile(
        for platform: JobBoardPlatform,
        in metadata: CareerResumeMetadataV1
    ) -> ResumeCanonicalProfile? {
        let map = decodeMap(from: metadata.platformVariantsJSON)
        guard let json = map[platform.rawValue] else { return nil }
        return ResumeCanonicalProfile.decode(from: json)
    }

    static func savedPlatforms(in metadata: CareerResumeMetadataV1) -> [JobBoardPlatform] {
        decodeMap(from: metadata.platformVariantsJSON).keys.compactMap(JobBoardPlatform.init(rawValue:))
    }

    private static func decodeMap(from json: String?) -> VariantMap {
        guard let json,
              let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode(VariantMap.self, from: data)
        else { return [:] }
        return map
    }

    private static func encodeMap(_ map: VariantMap) -> String? {
        guard let data = try? JSONEncoder().encode(map) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
