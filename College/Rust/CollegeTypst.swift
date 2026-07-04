// CollegeTypst.swift
// Feature: Rust FFI
// Purpose: Swift wrapper for embedded Typst PDF compilation.

import Foundation

#if COLLEGE_TYPST_LINKED
@_silgen_name("college_typst_compile_pdf")
private func college_typst_compile_pdf(
    _ source: UnsafePointer<CChar>?,
    _ outLen: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?

@_silgen_name("college_typst_free")
private func college_typst_free(_ ptr: UnsafeMutablePointer<UInt8>?, _ len: Int)

@_silgen_name("college_typst_last_error")
private func college_typst_last_error() -> UnsafePointer<CChar>?
#endif

enum CollegeTypst {
    /// True when the Rust lib is not linked and the Swift fallback is in use.
    static var isUsingFallbackRenderer: Bool {
        #if COLLEGE_TYPST_LINKED
        false
        #else
        true
        #endif
    }

    static func compilePDF(typstSource: String) throws -> Data {
        #if COLLEGE_TYPST_LINKED
        var len = 0
        guard let ptr = typstSource.withCString({ college_typst_compile_pdf($0, &len) }) else {
            throw ResumeCompileError.from(cString: college_typst_last_error())
        }
        defer { college_typst_free(ptr, len) }
        return Data(bytes: ptr, count: len)
        #else
        let plain = PlainTextResume.from(typstSource)
        return CareerResumePDFExporter.renderSingleColumnPDF(text: plain)
        #endif
    }

    /// Release builds must link Typst; the fallback is dev/CI-only.
    static func assertProductionTypstLinked() {
        #if !DEBUG && !COLLEGE_TYPST_LINKED
        assertionFailure("Release builds require COLLEGE_TYPST_LINKED for resume PDF generation.")
        #endif
    }
}

struct ResumeCompileError: LocalizedError, Sendable {
    enum Kind: Sendable {
        case generic
        case unsupportedCharacters(section: String?)
        case sectionRenderFailure(section: String)
    }

    let kind: Kind
    let userMessage: String
    let debugDetail: String?

    var errorDescription: String? { userMessage }

    static func from(cString: UnsafePointer<CChar>?) -> ResumeCompileError {
        let raw: String
        if let cString {
            raw = String(cString: cString)
        } else {
            raw = "Unknown compilation error"
        }
        return map(rawDiagnostic: raw)
    }

    static func map(rawDiagnostic: String) -> ResumeCompileError {
        let lower = rawDiagnostic.lowercased()
        let debug = rawDiagnostic

        if lower.contains("skill") {
            return ResumeCompileError(
                kind: .sectionRenderFailure(section: "Skills"),
                userMessage: "The Skills section could not be rendered — check for special characters.",
                debugDetail: debug
            )
        }
        if lower.contains("project") {
            return ResumeCompileError(
                kind: .sectionRenderFailure(section: "Projects"),
                userMessage: "A project description contains unsupported characters.",
                debugDetail: debug
            )
        }
        if lower.contains("experience") || lower.contains("company") {
            return ResumeCompileError(
                kind: .sectionRenderFailure(section: "Experience"),
                userMessage: "Work experience could not be rendered — check for special characters.",
                debugDetail: debug
            )
        }
        if lower.contains("education") {
            return ResumeCompileError(
                kind: .sectionRenderFailure(section: "Education"),
                userMessage: "Education could not be rendered — check for special characters.",
                debugDetail: debug
            )
        }
        if lower.contains("unexpected") || lower.contains("token") || lower.contains("character") {
            return ResumeCompileError(
                kind: .unsupportedCharacters(section: nil),
                userMessage: "Some resume text contains characters the template could not render.",
                debugDetail: debug
            )
        }

        return ResumeCompileError(
            kind: .generic,
            userMessage: "The resume preview could not be generated. Try removing special characters from your profile.",
            debugDetail: debug
        )
    }
}
