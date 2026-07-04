// EmailService.swift
// Feature: Core
// Purpose: Centralized email composition — resolves the user's configured email
//          as the sender ("from") and opens the system mail client with a draft.
// Data: Reads `account.email` (UserDefaults) and `Profile.universityEmail`.

import AppKit
import Foundation

/// A prefilled email draft. Recipients and headers are percent-encoded into a
/// `mailto:` URL when handed to the system mail client.
struct EmailDraft: Equatable, Sendable {
    var to: [String]
    var cc: [String]
    var bcc: [String]
    /// Sender address. When `nil`, `EmailService` fills it with the user's
    /// configured email so the draft opens "from" that account.
    var from: String?
    var subject: String?
    var body: String?

    init(
        to: [String] = [],
        cc: [String] = [],
        bcc: [String] = [],
        from: String? = nil,
        subject: String? = nil,
        body: String? = nil
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.from = from
        self.subject = subject
        self.body = body
    }

    /// Builds an RFC 6068-style `mailto:` URL with robust percent-encoding.
    var mailtoURL: URL? {
        let recipients = to
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanCC = cc.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanBCC = bcc.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanFrom = from?.trimmingCharacters(in: .whitespacesAndNewlines)

        // A draft is only meaningful with at least a recipient or a sender.
        guard !recipients.isEmpty || !(cleanFrom?.isEmpty ?? true) else { return nil }

        var string = "mailto:" + recipients.map(Self.encode).joined(separator: ",")

        var query: [String] = []
        if !cleanCC.isEmpty { query.append("cc=" + cleanCC.map(Self.encode).joined(separator: ",")) }
        if !cleanBCC.isEmpty { query.append("bcc=" + cleanBCC.map(Self.encode).joined(separator: ",")) }
        if let cleanFrom, !cleanFrom.isEmpty { query.append("from=" + Self.encode(cleanFrom)) }
        if let subject = subject?.nilIfBlank { query.append("subject=" + Self.encode(subject)) }
        if let body = body?.nilIfBlank { query.append("body=" + Self.encode(body)) }

        if !query.isEmpty { string += "?" + query.joined(separator: "&") }
        return URL(string: string)
    }

    /// Percent-encodes a header value, escaping characters that would otherwise
    /// be interpreted as `mailto:` structure (including `+`, which some clients
    /// decode back into a space).
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+/#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Opens the system mail client with drafts whose sender defaults to the user's
/// configured email. Inject via `AppContainer.emailService` and call from any
/// feature that needs to send mail (professor contact, advisors, recruiters, …).
@MainActor
final class EmailService {
    /// UserDefaults key shared with the Settings sign-in email field.
    static let accountEmailDefaultsKey = "account.email"

    private let persistence: CollegePersistence
    private let defaults: UserDefaults

    init(persistence: CollegePersistence = .shared, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
    }

    /// The email used as the sender for composed drafts. Prefers the Settings
    /// sign-in email, then the saved profile's university email, then the
    /// primary academic profile's university email.
    var senderEmail: String? {
        if let account = defaults.string(forKey: Self.accountEmailDefaultsKey)?.nilIfBlank {
            return account
        }
        if let profileEmail = persistence.profile?.universityEmail?.nilIfBlank {
            return profileEmail
        }
        let academic = persistence.academicProfiles.first(where: \.isPrimary)
            ?? persistence.academicProfiles.first
        return academic?.universityEmail?.nilIfBlank
    }

    /// Whether the user has configured an email to send from.
    var hasSenderEmail: Bool { senderEmail != nil }

    /// Opens the mail client for `draft`, filling `from` with the user's
    /// configured email when the draft does not specify one.
    @discardableResult
    func compose(_ draft: EmailDraft) -> Bool {
        var draft = draft
        if draft.from?.nilIfBlank == nil {
            draft.from = senderEmail
        }
        guard let url = draft.mailtoURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Convenience for a single recipient.
    @discardableResult
    func compose(
        to recipient: String,
        cc: [String] = [],
        subject: String? = nil,
        body: String? = nil
    ) -> Bool {
        compose(EmailDraft(to: [recipient], cc: cc, subject: subject, body: body))
    }

    /// Composes an email to a professor with a sensible course-aware subject and
    /// greeting. Returns `false` if there is no recipient address.
    @discardableResult
    func composeToProfessor(
        email: String,
        professorName: String? = nil,
        courseCode: String? = nil,
        courseName: String? = nil
    ) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return false }

        let subject: String?
        if let code = courseCode?.nilIfBlank {
            if let name = courseName?.nilIfBlank {
                subject = "\(code) – \(name)"
            } else {
                subject = code
            }
        } else {
            subject = courseName?.nilIfBlank
        }

        let body: String?
        if let salutation = Self.professorSalutation(from: professorName) {
            body = "\(salutation),\n\n"
        } else {
            body = nil
        }

        return compose(EmailDraft(to: [trimmedEmail], subject: subject, body: body))
    }

    /// Produces a greeting such as "Dear Professor Smith" from a full name.
    private static func professorSalutation(from name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let cleaned = stripTitlePrefixes(from: trimmed)
        let lastName = cleaned.split(separator: " ").last.map(String.init) ?? cleaned
        return "Dear Professor \(lastName)"
    }

    private static func stripTitlePrefixes(from name: String) -> String {
        let prefixes = ["dr.", "dr", "prof.", "prof", "professor", "mr.", "mrs.", "ms.", "mx."]
        var components = name.split(separator: " ").map(String.init)
        while let first = components.first, prefixes.contains(first.lowercased()) {
            components.removeFirst()
        }
        return components.isEmpty ? name : components.joined(separator: " ")
    }
}

private extension String {
    /// Returns the trimmed string, or `nil` when it is empty after trimming.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
