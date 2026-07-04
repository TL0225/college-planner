// ProfileResumeCard.swift
// Feature: Profile
// Purpose: Resume availability CTA on the profile dashboard.

import SwiftUI

struct ProfileResumeCard: View {
    let availability: ResumeAvailability
    var onBuildResume: () -> Void
    var onOpenCareerResumes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentTint)
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 17, weight: .bold))
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if showsActions {
                HStack(spacing: 10) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                    if showsSecondaryAction {
                        Button(ResumeRequiredCopy.uploadButton, action: onOpenCareerResumes)
                            .buttonStyle(.bordered)
                    }
                }
            } else if case .uploadedAwaitingParse = availability.state {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("View in Career", action: onOpenCareerResumes)
                        .buttonStyle(.link)
                }
            }
        }
        .profileCardSurface()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch availability.state {
        case .none:
            return String(localized: "profile.resume.none.title", defaultValue: "Build your resume")
        case .draftOnly:
            return String(localized: "profile.resume.draft.title", defaultValue: "Resume in progress")
        case .uploadedAwaitingParse:
            return String(localized: "profile.resume.parsing.title", defaultValue: "Parsing your resume")
        case .ready:
            return String(localized: "profile.resume.ready.title", defaultValue: "Resume ready")
        case .lowParserHealth:
            return String(localized: "profile.resume.review.title", defaultValue: "Resume needs review")
        }
    }

    private var subtitle: String {
        switch availability.state {
        case .none:
            return String(
                localized: "profile.resume.none.subtitle",
                defaultValue: "Turn your profile into an ATS-safe resume for job applications."
            )
        case .draftOnly:
            return String(
                localized: "profile.resume.draft.subtitle",
                defaultValue: "Continue where you left off in the Resume Builder."
            )
        case .uploadedAwaitingParse:
            return String(
                localized: "profile.resume.parsing.subtitle",
                defaultValue: "We are extracting skills and experience from your upload."
            )
        case .ready:
            return String(
                localized: "profile.resume.ready.subtitle",
                defaultValue: "Open Career to tailor, match jobs, and apply."
            )
        case .lowParserHealth(_, let percent):
            return String(
                localized: "profile.resume.review.subtitle",
                defaultValue: "Parser health is \(percent)% — review formatting before you apply."
            )
        }
    }

    private var iconName: String {
        switch availability.state {
        case .none, .draftOnly:
            return "doc.badge.plus"
        case .uploadedAwaitingParse:
            return "arrow.triangle.2.circlepath.doc"
        case .ready:
            return "doc.text.fill"
        case .lowParserHealth:
            return "exclamationmark.triangle.fill"
        }
    }

    private var accentColor: Color {
        switch availability.state {
        case .lowParserHealth:
            return .orange
        case .ready:
            return .green
        default:
            return .accentColor
        }
    }

    private var accentTint: Color {
        accentColor.opacity(0.14)
    }

    private var showsActions: Bool {
        switch availability.state {
        case .none, .draftOnly, .ready, .lowParserHealth:
            return true
        case .uploadedAwaitingParse:
            return false
        }
    }

    private var showsSecondaryAction: Bool {
        switch availability.state {
        case .none:
            return true
        default:
            return false
        }
    }

    private var primaryActionTitle: String {
        switch availability.state {
        case .none:
            return ResumeRequiredCopy.buildButton
        case .draftOnly:
            return String(localized: "profile.resume.continue", defaultValue: "Continue building")
        case .ready, .lowParserHealth:
            return String(localized: "profile.resume.open_career", defaultValue: "Open Career")
        case .uploadedAwaitingParse:
            return ""
        }
    }

    private func primaryAction() {
        switch availability.state {
        case .none, .draftOnly:
            onBuildResume()
        case .ready, .lowParserHealth:
            onOpenCareerResumes()
        case .uploadedAwaitingParse:
            break
        }
    }
}
