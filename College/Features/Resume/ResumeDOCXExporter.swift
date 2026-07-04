// ResumeDOCXExporter.swift
// Feature: Resume
// Purpose: ATS-safe DOCX export from canonical or structured resume profiles.

import Foundation

enum ResumeDOCXExportError: Error, Sendable {
    case emptyProfile
    case archiveFailed
}

enum ResumeDOCXExporter {
    static let forbiddenOOXMLElements = ["w:tbl", "w:textbox", "w:hdr", "w:ftr", "w:cols"]

    static func export(profile: ResumeCanonicalProfile, sectionOrder: [ResumeSectionKind]? = nil) throws -> Data {
        guard profile.hasContent else { throw ResumeDOCXExportError.emptyProfile }
        let xml = documentXML(from: profile, sectionOrder: sectionOrder)
        return try archiveDOCX(documentXML: xml)
    }

    static func export(structured: CareerResumeStructuredProfile) throws -> Data {
        try export(profile: ResumeCanonicalProfile.from(structured: structured))
    }

    static func containsForbiddenElements(in docxData: Data) -> Bool {
        guard let xml = documentXMLContents(from: docxData) else { return true }
        let patterns = ["<w:tbl", "<w:textbox", "<w:hdr", "<w:ftr", "<w:cols"]
        return patterns.contains { xml.contains($0) }
    }

    /// Exposed for unit tests to verify archive round-trip.
    static func documentXMLContentsForTesting(from docxData: Data) -> String? {
        documentXMLContents(from: docxData)
    }

    static func documentXML(from profile: ResumeCanonicalProfile, sectionOrder: [ResumeSectionKind]? = nil) -> String {
        var paragraphs: [String] = []
        appendBasics(&paragraphs, profile: profile)

        let order = sectionOrder ?? defaultSectionOrder(for: profile)
        for kind in order {
            switch kind {
            case .personal:
                continue
            case .summary:
                appendSummary(&paragraphs, profile: profile)
            case .education:
                appendEducation(&paragraphs, profile: profile)
            case .experience:
                appendExperience(&paragraphs, profile: profile)
            case .projects:
                appendProjects(&paragraphs, profile: profile)
            case .skills:
                appendSkills(&paragraphs, profile: profile)
            case .achievements:
                break
            case .certifications:
                appendCertifications(&paragraphs, profile: profile)
            case .extracurriculars:
                break
            }
        }

        let body = paragraphs.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:body>
            \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    // MARK: - Private

    private static func defaultSectionOrder(for profile: ResumeCanonicalProfile) -> [ResumeSectionKind] {
        var order: [ResumeSectionKind] = []
        if profile.basics?.summary?.isEmpty == false { order.append(.summary) }
        if !profile.education.isEmpty { order.append(.education) }
        if !profile.work.isEmpty { order.append(.experience) }
        if !profile.projects.isEmpty { order.append(.projects) }
        if !profile.skills.isEmpty || !profile.skillGroups.isEmpty { order.append(.skills) }
        if !profile.certifications.isEmpty { order.append(.certifications) }
        return order
    }

    private static func appendBasics(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard let basics = profile.basics else { return }

        if let name = trimmed(basics.name) {
            paragraphs.append(paragraph(style: "Title", runs: [(.plain, name)]))
        }

        var contactParts: [String] = []
        if let email = trimmed(basics.email) { contactParts.append(email) }
        if let phone = trimmed(basics.phone) { contactParts.append(phone) }
        if let location = trimmed(basics.location) { contactParts.append(location) }
        if !contactParts.isEmpty {
            paragraphs.append(paragraph(style: "Normal", runs: [(.plain, contactParts.joined(separator: " · "))]))
        }

        for link in basics.links {
            let visible = trimmed(CareerATSFieldNormalizer.normalizeURL(link)) ?? link
            paragraphs.append(paragraph(style: "Normal", runs: [(.plain, visible)]))
        }

        paragraphs.append(emptyParagraph())
    }

    private static func appendSummary(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard let summary = trimmed(profile.basics?.summary) else { return }
        paragraphs.append(sectionHeader("Professional Summary"))
        paragraphs.append(paragraph(style: "Normal", runs: [(.plain, summary)]))
        paragraphs.append(emptyParagraph())
    }

    private static func appendEducation(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard !profile.education.isEmpty else { return }
        paragraphs.append(sectionHeader("Education"))
        for entry in profile.education {
            var headline: [String] = []
            if let studyType = trimmed(entry.studyType) { headline.append(studyType) }
            if let area = trimmed(entry.area) { headline.append(area) }
            if !headline.isEmpty {
                paragraphs.append(paragraph(style: "Normal", runs: [(.bold, headline.joined(separator: ", "))]))
            }
            var subline: [String] = []
            if let institution = trimmed(entry.institution) { subline.append(institution) }
            if let endDate = trimmed(entry.endDate) { subline.append(endDate) }
            if !subline.isEmpty {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, subline.joined(separator: " · "))]))
            }
            if let gpa = entry.gpa {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, "GPA: \(String(format: "%.2f", gpa))")]))
            }
            paragraphs.append(emptyParagraph())
        }
    }

    private static func appendExperience(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard !profile.work.isEmpty else { return }
        paragraphs.append(sectionHeader("Work Experience"))
        for entry in profile.work {
            let title = trimmed(entry.position) ?? "Role"
            let company = trimmed(entry.company) ?? "Company"
            paragraphs.append(paragraph(
                style: "Normal",
                runs: [(.bold, title), (.plain, " at \(company)")]
            ))
            var meta: [String] = []
            if let dateRange = trimmed(entry.dateRange) { meta.append(dateRange) }
            if let location = trimmed(entry.location) { meta.append(location) }
            if !meta.isEmpty {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, meta.joined(separator: " · "))]))
            }
            for bullet in entry.highlights {
                paragraphs.append(bulletParagraph(bullet))
            }
            if let technologies = trimmed(entry.technologies) {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, "Technologies: \(technologies)")]))
            }
            paragraphs.append(emptyParagraph())
        }
    }

    private static func appendProjects(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard !profile.projects.isEmpty else { return }
        paragraphs.append(sectionHeader("Projects"))
        for entry in profile.projects {
            if let name = trimmed(entry.name) {
                paragraphs.append(paragraph(style: "Normal", runs: [(.bold, name)]))
            }
            var meta: [String] = []
            if let role = trimmed(entry.role) { meta.append(role) }
            if let dateRange = trimmed(entry.dateRange) { meta.append(dateRange) }
            if !meta.isEmpty {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, meta.joined(separator: " · "))]))
            }
            if let description = trimmed(entry.description) {
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, description)]))
            }
            for bullet in entry.highlights {
                paragraphs.append(bulletParagraph(bullet))
            }
            if let url = trimmed(entry.url) {
                let visible = trimmed(CareerATSFieldNormalizer.normalizeURL(url)) ?? url
                paragraphs.append(paragraph(style: "Normal", runs: [(.plain, visible)]))
            }
            paragraphs.append(emptyParagraph())
        }
    }

    private static func appendSkills(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        let flatSkills = profile.skills
        let grouped = profile.skillGroups.flatMap { group in
            group.skills.map { "\(group.category): \($0)" }
        }
        let skills = flatSkills + grouped
        guard !skills.isEmpty else { return }
        paragraphs.append(sectionHeader("Skills"))
        paragraphs.append(paragraph(style: "Normal", runs: [(.plain, skills.joined(separator: " · "))]))
        paragraphs.append(emptyParagraph())
    }

    private static func appendCertifications(_ paragraphs: inout [String], profile: ResumeCanonicalProfile) {
        guard !profile.certifications.isEmpty else { return }
        paragraphs.append(sectionHeader("Certifications"))
        for item in profile.certifications {
            paragraphs.append(bulletParagraph(item))
        }
        paragraphs.append(emptyParagraph())
    }

    private static func sectionHeader(_ title: String) -> String {
        paragraph(style: "Heading1", runs: [(.plain, title)])
    }

    private enum RunStyle {
        case plain
        case bold
    }

    private static func paragraph(style: String, runs: [(RunStyle, String)]) -> String {
        let runXML = runs.map { style, text in
            let escaped = escapeXML(text)
            switch style {
            case .plain:
                return "<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
            case .bold:
                return "<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
            }
        }.joined()
        return """
        <w:p>
          <w:pPr><w:pStyle w:val="\(escapeXML(style))"/></w:pPr>
          \(runXML)
        </w:p>
        """
    }

    private static func bulletParagraph(_ text: String) -> String {
        """
        <w:p>
          <w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr>
          <w:r><w:t xml:space="preserve">• \(escapeXML(text))</w:t></w:r>
        </w:p>
        """
    }

    private static func emptyParagraph() -> String {
        "<w:p><w:r><w:t xml:space=\"preserve\"></w:t></w:r></w:p>"
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func archiveDOCX(documentXML: String) throws -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let packageRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(packageRels.utf8)),
            ("word/document.xml", Data(documentXML.utf8)),
        ]

        guard let archive = ResumeDOCXZipWriter.archive(files: files) else {
            throw ResumeDOCXExportError.archiveFailed
        }
        return archive
    }

    private static func documentXMLContents(from docxData: Data) -> String? {
        guard let entry = ResumeDOCXZipWriter.readEntry(named: "word/document.xml", from: docxData) else {
            return nil
        }
        return String(data: entry, encoding: .utf8)
    }
}

// MARK: - Minimal ZIP writer (stored entries)

private enum ResumeDOCXZipWriter {
    static func archive(files: [(path: String, data: Data)]) -> Data? {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for file in files {
            let nameData = Data(file.path.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)

            var local = Data()
            local.appendUInt32(0x0403_4b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)
            local.append(nameData)
            local.append(file.data)

            archive.append(local)

            var central = Data()
            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        var end = Data()
        end.appendUInt32(0x0605_4b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(files.count))
        end.appendUInt16(UInt16(files.count))
        end.appendUInt32(UInt32(centralDirectory.count))
        end.appendUInt32(centralOffset)
        end.appendUInt16(0)
        archive.append(end)

        return archive
    }

    static func readEntry(named path: String, from archive: Data) -> Data? {
        var offset = 0
        let target = Data(path.utf8)

        while offset + 30 <= archive.count {
            let signature = archive.readUInt32(at: offset)
            guard signature == 0x0403_4b50 else { break }

            let compressedSize = archive.readUInt32(at: offset + 18)
            let uncompressedSize = archive.readUInt32(at: offset + 22)
            let nameLength = Int(archive.readUInt16(at: offset + 26))
            let extraLength = Int(archive.readUInt16(at: offset + 28))
            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd <= archive.count else { break }

            let name = archive.subdata(in: nameStart ..< nameEnd)
            let dataStart = nameEnd + extraLength
            let dataEnd = dataStart + Int(compressedSize)
            guard dataEnd <= archive.count else { break }

            if name == target {
                let payload = archive.subdata(in: dataStart ..< dataEnd)
                return compressedSize == uncompressedSize ? payload : nil
            }

            offset = dataEnd
        }
        return nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let slice = self[offset ..< offset + 2]
        return slice.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let slice = self[offset ..< offset + 4]
        return slice.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }
}
