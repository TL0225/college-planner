// ResumeDocumentStyle.swift
// Feature: Resume
// Purpose: Typography and page layout settings for the guided builder Home ribbon.

import Foundation

enum ResumePageSize: String, Codable, Sendable, CaseIterable, Hashable {
    case letter
    case a4

    var title: String {
        switch self {
        case .letter: return "Letter"
        case .a4: return "A4"
        }
    }
}

enum ResumeMarginPreset: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case compact
    case standard
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .spacious: return "Spacious"
        }
    }

    var marginInches: Double {
        switch self {
        case .compact: return 0.5
        case .standard: return 0.75
        case .spacious: return 1.0
        }
    }
}

enum ResumeFontPreset: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case libertinusSerif
    case newComputerModern
    case sourceSerif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .libertinusSerif: return "Libertinus"
        case .newComputerModern: return "Computer Modern"
        case .sourceSerif: return "Source Serif"
        }
    }

    var fontFamily: String {
        switch self {
        case .libertinusSerif: return "Libertinus Serif"
        case .newComputerModern: return "New Computer Modern"
        case .sourceSerif: return "Source Serif 4"
        }
    }
}

struct ResumeDocumentStyle: Codable, Sendable, Equatable, Hashable {
    var fontFamily: String
    var bodySize: Double
    var headingScale: Double
    var marginInches: Double
    var lineLeading: Double
    var pageSize: ResumePageSize
    var marginPreset: ResumeMarginPreset

    static let standard = ResumeDocumentStyle(
        fontFamily: ResumeFontPreset.libertinusSerif.fontFamily,
        bodySize: 10.5,
        headingScale: 1.0,
        marginInches: ResumeMarginPreset.standard.marginInches,
        lineLeading: 0.65,
        pageSize: .letter,
        marginPreset: .standard
    )

    var fontPreset: ResumeFontPreset {
        get {
            ResumeFontPreset.allCases.first { $0.fontFamily == fontFamily } ?? .libertinusSerif
        }
        set {
            fontFamily = newValue.fontFamily
        }
    }

    mutating func applyMarginPreset(_ preset: ResumeMarginPreset) {
        marginPreset = preset
        marginInches = preset.marginInches
    }
}
