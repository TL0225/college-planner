// DegreeTokenRegistry.swift
// Feature: Catalog
// Purpose: Catalog module — Entry.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Single source of truth for US degree abbreviations, full picker labels, and academic levels.
enum DegreeTokenRegistry {
    struct Entry: Equatable {
        let token: String
        let fullLabel: String
        let displayLabel: String
        let degreeLevel: String
        /// When true, token is only valid in suffix/parenthetical position (not phrase/heuristic).
        let suffixPositionOnly: Bool
    }

    private static let entries: [Entry] = [
        // Undergraduate
        Entry(token: "BA", fullLabel: "Bachelor of Arts (BA)", displayLabel: "Bachelor of Arts", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BS", fullLabel: "Bachelor of Science (BS)", displayLabel: "Bachelor of Science", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BFA", fullLabel: "Bachelor of Fine Arts (BFA)", displayLabel: "Bachelor of Fine Arts", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BM", fullLabel: "Bachelor of Music (BM)", displayLabel: "Bachelor of Music", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BARCH", fullLabel: "Bachelor of Architecture (BArch)", displayLabel: "Bachelor of Architecture", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BE", fullLabel: "Bachelor of Engineering (BE)", displayLabel: "Bachelor of Engineering", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BSE", fullLabel: "Bachelor of Science in Engineering (BSE)", displayLabel: "Bachelor of Science in Engineering", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BBA", fullLabel: "Bachelor of Business Administration (BBA)", displayLabel: "Bachelor of Business Administration", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BSN", fullLabel: "Bachelor of Science in Nursing (BSN)", displayLabel: "Bachelor of Science in Nursing", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BSED", fullLabel: "Bachelor of Science in Education (BSEd)", displayLabel: "Bachelor of Science in Education", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "BAS", fullLabel: "Bachelor of Applied Science (BAS)", displayLabel: "Bachelor of Applied Science", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "AA", fullLabel: "Associate of Arts (AA)", displayLabel: "Associate of Arts", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "AS", fullLabel: "Associate of Science (AS)", displayLabel: "Associate of Science", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),
        Entry(token: "AAS", fullLabel: "Associate of Applied Science (AAS)", displayLabel: "Associate of Applied Science", degreeLevel: DegreeConfiguration.undergraduate, suffixPositionOnly: false),

        // Graduate (Masters)
        Entry(token: "MA", fullLabel: "Master of Arts (MA)", displayLabel: "Master of Arts", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MS", fullLabel: "Master of Science (MS)", displayLabel: "Master of Science", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MBA", fullLabel: "Master of Business Administration (MBA)", displayLabel: "Master of Business Administration", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MFA", fullLabel: "Master of Fine Arts (MFA)", displayLabel: "Master of Fine Arts", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MPH", fullLabel: "Master of Public Health (MPH)", displayLabel: "Master of Public Health", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MSW", fullLabel: "Master of Social Work (MSW)", displayLabel: "Master of Social Work", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MED", fullLabel: "Master of Education (MEd)", displayLabel: "Master of Education", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MSED", fullLabel: "Master of Science in Education (MSEd)", displayLabel: "Master of Science in Education", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MSE", fullLabel: "Master of Science in Education (MSE)", displayLabel: "Master of Science in Education", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MST", fullLabel: "Master of Science in Teaching (MST)", displayLabel: "Master of Science in Teaching", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MENG", fullLabel: "Master of Engineering (MEng)", displayLabel: "Master of Engineering", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MARCH", fullLabel: "Master of Architecture (MArch)", displayLabel: "Master of Architecture", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MPA", fullLabel: "Master of Public Administration (MPA)", displayLabel: "Master of Public Administration", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MPP", fullLabel: "Master of Public Policy (MPP)", displayLabel: "Master of Public Policy", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MSN", fullLabel: "Master of Science in Nursing (MSN)", displayLabel: "Master of Science in Nursing", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MHA", fullLabel: "Master of Health Administration (MHA)", displayLabel: "Master of Health Administration", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MLS", fullLabel: "Master of Library Science (MLS)", displayLabel: "Master of Library Science", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MLIS", fullLabel: "Master of Library and Information Science (MLIS)", displayLabel: "Master of Library and Information Science", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MM", fullLabel: "Master of Music (MM)", displayLabel: "Master of Music", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MDIV", fullLabel: "Master of Divinity (MDiv)", displayLabel: "Master of Divinity", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MPS", fullLabel: "Master of Professional Studies (MPS)", displayLabel: "Master of Professional Studies", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),
        Entry(token: "MAT", fullLabel: "Master of Arts in Teaching (MAT)", displayLabel: "Master of Arts in Teaching", degreeLevel: DegreeConfiguration.graduate, suffixPositionOnly: false),

        // Law
        Entry(token: "JD", fullLabel: "Juris Doctor (JD)", displayLabel: "Juris Doctor", degreeLevel: DegreeConfiguration.lawSchool, suffixPositionOnly: false),
        Entry(token: "LLM", fullLabel: "Master of Laws (LLM)", displayLabel: "Master of Laws", degreeLevel: DegreeConfiguration.lawSchool, suffixPositionOnly: false),
        Entry(token: "SJD", fullLabel: "Doctor of Juridical Science (SJD)", displayLabel: "Doctor of Juridical Science", degreeLevel: DegreeConfiguration.lawSchool, suffixPositionOnly: false),
        Entry(token: "MSL", fullLabel: "Master of Studies in Law (MSL)", displayLabel: "Master of Studies in Law", degreeLevel: DegreeConfiguration.lawSchool, suffixPositionOnly: false),

        // Dental
        Entry(token: "DDS", fullLabel: "Doctor of Dental Surgery (DDS)", displayLabel: "Doctor of Dental Surgery", degreeLevel: DegreeConfiguration.dentalSchool, suffixPositionOnly: false),
        Entry(token: "DMD", fullLabel: "Doctor of Dental Medicine (DMD)", displayLabel: "Doctor of Dental Medicine", degreeLevel: DegreeConfiguration.dentalSchool, suffixPositionOnly: false),

        // Medical / Health Professional
        Entry(token: "MD", fullLabel: "Doctor of Medicine (MD)", displayLabel: "Doctor of Medicine", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "DO", fullLabel: "Doctor of Osteopathic Medicine (DO)", displayLabel: "Doctor of Osteopathic Medicine", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: true),
        Entry(token: "PHARMD", fullLabel: "Doctor of Pharmacy (PharmD)", displayLabel: "Doctor of Pharmacy", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "DPT", fullLabel: "Doctor of Physical Therapy (DPT)", displayLabel: "Doctor of Physical Therapy", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "DNP", fullLabel: "Doctor of Nursing Practice (DNP)", displayLabel: "Doctor of Nursing Practice", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "DVM", fullLabel: "Doctor of Veterinary Medicine (DVM)", displayLabel: "Doctor of Veterinary Medicine", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "OD", fullLabel: "Doctor of Optometry (OD)", displayLabel: "Doctor of Optometry", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: true),
        Entry(token: "DPM", fullLabel: "Doctor of Podiatric Medicine (DPM)", displayLabel: "Doctor of Podiatric Medicine", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: false),
        Entry(token: "DC", fullLabel: "Doctor of Chiropractic (DC)", displayLabel: "Doctor of Chiropractic", degreeLevel: DegreeConfiguration.medicalSchool, suffixPositionOnly: true),

        // Doctorate / Professional
        Entry(token: "PHD", fullLabel: "Doctor of Philosophy (PhD)", displayLabel: "Doctor of Philosophy", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "EDD", fullLabel: "Doctor of Education (EdD)", displayLabel: "Doctor of Education", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "PSYD", fullLabel: "Doctor of Psychology (PsyD)", displayLabel: "Doctor of Psychology", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DBA", fullLabel: "Doctor of Business Administration (DBA)", displayLabel: "Doctor of Business Administration", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DMA", fullLabel: "Doctor of Musical Arts (DMA)", displayLabel: "Doctor of Musical Arts", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DSC", fullLabel: "Doctor of Science (DSc)", displayLabel: "Doctor of Science", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DPA", fullLabel: "Doctor of Public Administration (DPA)", displayLabel: "Doctor of Public Administration", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DSW", fullLabel: "Doctor of Social Work (DSW)", displayLabel: "Doctor of Social Work", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DMIN", fullLabel: "Doctor of Ministry (DMin)", displayLabel: "Doctor of Ministry", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DENG", fullLabel: "Doctor of Engineering (DEng)", displayLabel: "Doctor of Engineering", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
        Entry(token: "DHSC", fullLabel: "Doctor of Health Science (DHSc)", displayLabel: "Doctor of Health Science", degreeLevel: DegreeConfiguration.doctorateProfessional, suffixPositionOnly: false),
    ]

    /// Spelled-out phrases (longest first for prefix matching) → token.
    private static let phraseTable: [(phrase: String, token: String)] = {
        let phrases: [(String, String)] = [
            ("Bachelor of Science in Nursing", "BSN"),
            ("Bachelor of Science in Education", "BSED"),
            ("Bachelor of Science in Engineering", "BSE"),
            ("Bachelor of Business Administration", "BBA"),
            ("Bachelor of Applied Science", "BAS"),
            ("Bachelor of Fine Arts", "BFA"),
            ("Bachelor of Architecture", "BARCH"),
            ("Bachelor of Engineering", "BE"),
            ("Bachelor of Science", "BS"),
            ("Bachelor of Arts", "BA"),
            ("Bachelor of Music", "BM"),
            ("Associate of Applied Science", "AAS"),
            ("Associate of Science", "AS"),
            ("Associate of Arts", "AA"),
            ("Master of Library and Information Science", "MLIS"),
            ("Master of Business Administration", "MBA"),
            ("Master of Science in Education", "MSED"),
            ("Master of Science in Nursing", "MSN"),
            ("Master of Health Administration", "MHA"),
            ("Master of Professional Studies", "MPS"),
            ("Master of Public Administration", "MPA"),
            ("Master of Public Health", "MPH"),
            ("Master of Social Work", "MSW"),
            ("Master of Fine Arts", "MFA"),
            ("Master of Public Policy", "MPP"),
            ("Master of Library Science", "MLS"),
            ("Master of Arts in Teaching", "MAT"),
            ("Master of Engineering", "MENG"),
            ("Master of Architecture", "MARCH"),
            ("Master of Education", "MED"),
            ("Master of Divinity", "MDIV"),
            ("Master of Science", "MS"),
            ("Master of Arts", "MA"),
            ("Master of Music", "MM"),
            ("Master of Laws", "LLM"),
            ("Master of Studies in Law", "MSL"),
            ("Doctor of Juridical Science", "SJD"),
            ("Doctor of Osteopathic Medicine", "DO"),
            ("Doctor of Business Administration", "DBA"),
            ("Doctor of Veterinary Medicine", "DVM"),
            ("Doctor of Nursing Practice", "DNP"),
            ("Doctor of Physical Therapy", "DPT"),
            ("Doctor of Podiatric Medicine", "DPM"),
            ("Doctor of Chiropractic", "DC"),
            ("Doctor of Dental Surgery", "DDS"),
            ("Doctor of Dental Medicine", "DMD"),
            ("Doctor of Public Administration", "DPA"),
            ("Doctor of Health Science", "DHSC"),
            ("Doctor of Musical Arts", "DMA"),
            ("Doctor of Social Work", "DSW"),
            ("Doctor of Optometry", "OD"),
            ("Doctor of Pharmacy", "PHARMD"),
            ("Doctor of Philosophy", "PHD"),
            ("Doctor of Education", "EDD"),
            ("Doctor of Psychology", "PSYD"),
            ("Doctor of Engineering", "DENG"),
            ("Doctor of Ministry", "DMIN"),
            ("Doctor of Science", "DSC"),
            ("Doctor of Medicine", "MD"),
            ("Juris Doctor", "JD"),
        ]
        return phrases
            .map { (normalizePhraseKey($0.0), $0.1) }
            .sorted { $0.phrase.count > $1.phrase.count }
    }()

    private static let byToken: [String: Entry] = {
        var map: [String: Entry] = [:]
        for entry in entries {
            map[entry.token] = entry
        }
        return map
    }()

    static func normalizeToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizePhraseKey(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func entry(forNormalizedToken token: String) -> Entry? {
        let norm = normalizeToken(token)
        guard !norm.isEmpty else { return nil }
        return byToken[norm]
    }

    static func entry(forNormalizedToken token: String, allowSuffixPositionOnly: Bool) -> Entry? {
        guard let entry = entry(forNormalizedToken: token) else { return nil }
        if entry.suffixPositionOnly, !allowSuffixPositionOnly { return nil }
        return entry
    }

    static var allNormalizedTokens: [String] {
        entries.map(\.token).sorted { $0.count > $1.count }
    }

    static func isKnownToken(_ token: String) -> Bool {
        entry(forNormalizedToken: token) != nil
    }

    static func isLikelyDegreeTypeSuffix(_ raw: String) -> Bool {
        let norm = normalizeToken(raw)
        guard !norm.isEmpty, norm.count <= 8 else { return false }
        if isKnownToken(norm) { return true }
        return norm.count <= 6 && norm.allSatisfy { $0.isLetter }
    }

    static func fullPickerLabels(forLevel level: String) -> [String] {
        let canonical = DegreeConfiguration.canonicalLevel(level)
        return entries
            .filter { DegreeConfiguration.canonicalLevel($0.degreeLevel) == canonical }
            .map(\.fullLabel)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func allFullPickerLabels() -> [String] {
        entries.map(\.fullLabel).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func degreeLevelsFromRegistry() -> [DegreeLevel] {
        var grouped: [String: [String]] = [:]
        for entry in entries {
            let level = entry.degreeLevel
            grouped[level, default: []].append(entry.fullLabel)
        }
        let order = [
            DegreeConfiguration.undergraduate,
            DegreeConfiguration.graduate,
            DegreeConfiguration.lawSchool,
            DegreeConfiguration.dentalSchool,
            DegreeConfiguration.medicalSchool,
            DegreeConfiguration.doctorateProfessional,
        ]
        return order.compactMap { level in
            guard let types = grouped[level], !types.isEmpty else { return nil }
            return DegreeLevel(level: level, types: types.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        }
    }

    static func level(forFullLabelOrToken raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry = entries.first(where: { $0.fullLabel.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return entry.degreeLevel
        }
        if let entry = entry(forNormalizedToken: trimmed) {
            return entry.degreeLevel
        }
        return nil
    }

    static func tokenFromPhrasePrefix(_ normalizedNoSpaces: String) -> String? {
        for row in phraseTable {
            if normalizedNoSpaces.hasPrefix(row.phrase) {
                return row.token
            }
        }
        return nil
    }

    static func displayLabel(forNormalizedToken token: String) -> String? {
        entry(forNormalizedToken: token)?.displayLabel
    }

    static func entry(matchingFullLabel raw: String) -> Entry? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return entries.first { $0.fullLabel.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    static var allEntries: [Entry] { entries }
}
