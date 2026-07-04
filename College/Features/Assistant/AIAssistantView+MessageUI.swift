// AIAssistantView+MessageUI.swift
// Feature: Assistant
// Purpose: Message bubbles and pending-action cards (Phase 6 decomposition).

import SwiftUI
import AppKit

extension AIAssistantView {
    func shouldShowTranscriptDayHeader(for message: AssistantMessage, previousMessage: AssistantMessage?) -> Bool {
        guard let previousMessage else { return true }
        return !Calendar.current.isDate(message.timestamp, inSameDayAs: previousMessage.timestamp)
    }

    func transcriptDayHeader(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textLight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func isAssistantStructuredMessage(_ message: AssistantMessage) -> Bool {
        guard !message.isUser else { return false }
        if !message.sources.isEmpty || !message.toolTrace.isEmpty { return true }
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("What I Found") { return true }
        if trimmed.hasPrefix("Saved answer") { return true }
        return false
    }

    @ViewBuilder
    func transcriptBodyText(_ message: AssistantMessage, structured: Bool) -> some View {
        Group {
            if message.isUser {
                Text(message.text)
            } else {
                let paragraphs = AssistantMessageFormatting.paragraphs(message.text)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
        .foregroundStyle(DesignSystem.Colors.textMain)
        .textSelection(.enabled)
        .multilineTextAlignment(message.isUser ? .trailing : .leading)
        .frame(
            maxWidth: structured || message.isUser ? nil : AssistantChatChrome.proseLineMaxWidth,
            alignment: message.isUser ? .trailing : .leading
        )
        .accessibilityIdentifier(
            message.isUser ? "assistant.bubble.user" : "assistant.bubble.assistant"
        )
    }

    @ViewBuilder
    func userMessageRow(_ message: AssistantMessage) -> some View {
        if editingUserMessageID == message.id {
            userMessageEditCard(messageID: message.id)
        } else {
            HStack(alignment: .center, spacing: 8) {
                transcriptBodyText(message, structured: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: AssistantChatChrome.bubbleCornerRadius, style: .continuous)
                            .fill(AssistantChatChrome.userBubbleFill())
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: AssistantChatChrome.bubbleCornerRadius, style: .continuous)
                            .stroke(AssistantChatChrome.userBubbleStroke(), lineWidth: 0.8)
                    }

                Button {
                    beginUserMessageEdit(message)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit prompt")
                .disabled(!canEditMessage(message))
                .accessibilityIdentifier("assistant.message.edit")
            }
        }
    }

    func userMessageEditCard(messageID: UUID) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Edit prompt", text: $editingUserMessageDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DesignSystem.Colors.primary.opacity(0.85), lineWidth: 1.5)
                }
                .accessibilityIdentifier("assistant.message.edit.field")

            HStack(spacing: 14) {
                Button("Cancel") {
                    cancelUserMessageEdit()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .accessibilityIdentifier("assistant.message.edit.cancel")

                Button("Update") {
                    commitUserMessageEdit(messageID: messageID)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    editingUserMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isResponding
                )
                .accessibilityIdentifier("assistant.message.edit.update")
            }
        }
        .frame(maxWidth: AssistantChatChrome.proseLineMaxWidth, alignment: .trailing)
    }

    @ViewBuilder
    func messageBubble(_ message: AssistantMessage, previousMessage: AssistantMessage? = nil) -> some View {
        let showRoleHeader = !message.isUser && previousMessage?.isUser != false
        let structured = isAssistantStructuredMessage(message)
        let showTimestamp = hoveredTranscriptMessageID == message.id
        HStack {
            if message.isUser { Spacer(minLength: 30) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                if showRoleHeader {
                    Label(message.role.rawValue, systemImage: message.role.symbol)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }

                if message.isUser {
                    userMessageRow(message)
                } else {
                    transcriptBodyText(message, structured: structured)
                }

                if streamingMessageID == message.id && !message.isUser {
                    Text("Receiving…")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }

                if !message.isUser, !message.sources.isEmpty {
                    sourceTrustChips(for: message.sources)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                        ForEach(message.sources, id: \.self) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                if let urlStr = source.url,
                                   let url = URL(string: urlStr),
                                   url.scheme == "http" || url.scheme == "https" {
                                    Link(destination: url) {
                                        Text(source.title)
                                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                            .foregroundStyle(DesignSystem.Colors.info)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(source.title)
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                                if let snippet = source.snippet, !snippet.isEmpty {
                                    Text(snippet)
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                        .lineLimit(2)
                                }
                                if source.toolName != nil || source.hopIndex != nil || source.latencyMS != nil {
                                    Text(sourceMetadataLabel(source))
                                        .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if !message.isUser, !message.toolTrace.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(message.toolTrace.enumerated()), id: \.offset) { _, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: step.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(step.ok ? DesignSystem.Colors.primary : DesignSystem.Colors.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Step \(step.hopIndex + 1) · \(step.toolName) · \(step.latencyMS)ms")
                                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                                            .foregroundStyle(DesignSystem.Colors.textMain)
                                        if !step.summary.isEmpty {
                                            Text(step.summary)
                                                .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                                .foregroundStyle(DesignSystem.Colors.textLight)
                                                .lineLimit(3)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Tool trace (\(message.toolTrace.count))")
                        }
                    }
                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                    .padding(.top, 2)
                }

                if !message.isUser, !message.supersededReplyTexts.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(message.supersededReplyTexts.enumerated()), id: \.offset) { _, draft in
                            Text(draft)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Previous drafts (\(message.supersededReplyTexts.count))")
                        }
                    }
                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                    .padding(.top, 2)
                }

                if !message.isUser {
                    HStack(spacing: 6) {
                        Button {
                            copyMessageText(message.text)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Copy response")

                        Button {
                            setMessageFeedback(messageID: message.id, feedback: message.feedback == .helpful ? nil : .helpful)
                        } label: {
                            Image(systemName: message.feedback == .helpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.feedback == .helpful ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Helpful")
                        .accessibilityIdentifier("assistant.feedback.helpful")

                        Button {
                            setMessageFeedback(messageID: message.id, feedback: message.feedback == .notHelpful ? nil : .notHelpful)
                        } label: {
                            Image(systemName: message.feedback == .notHelpful ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(message.feedback == .notHelpful ? DesignSystem.Colors.warning : DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                        .help("Not helpful")
                        .accessibilityIdentifier("assistant.feedback.notHelpful")
                    }
                    .padding(.top, 2)
                }

                if message.isUser, !message.attachmentDisplayNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(message.attachmentDisplayNames.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.surface.opacity(0.65), in: Capsule())
                            }
                        }
                    }
                }

                if showTimestamp {
                    Text(timeLabel(message.timestamp))
                        .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .opacity(0.85)
                }
            }
            .padding(.horizontal, message.isUser ? 0 : (structured ? 12 : 0))
            .padding(.vertical, message.isUser ? 0 : (structured ? 10 : 4))
            .background {
                if !message.isUser, structured {
                    RoundedRectangle(cornerRadius: AssistantChatChrome.bubbleCornerRadius, style: .continuous)
                        .fill(AssistantChatChrome.structuredCardFill())
                }
            }
            .overlay {
                if !message.isUser, structured {
                    RoundedRectangle(cornerRadius: AssistantChatChrome.bubbleCornerRadius, style: .continuous)
                        .stroke(AssistantChatChrome.structuredCardStroke(), lineWidth: 0.8)
                }
            }
            .frame(maxWidth: AssistantChatChrome.proseLineMaxWidth, alignment: message.isUser ? .trailing : .leading)
            .onHover { hovering in
                hoveredTranscriptMessageID = hovering ? message.id : nil
            }
            if !message.isUser { Spacer(minLength: 30) }
        }
    }

    func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    @ViewBuilder
    func sourceTrustChips(for sources: [AssistantReplySource]) -> some View {
        let tiers = Set(sources.compactMap(\.trustTier))
        if !tiers.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(Array(tiers).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { tier in
                        Text(AssistantAcademicWebPolicy.userFacingLabel(for: tier))
                            .font(DesignSystem.Fonts.main(size: 9, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignSystem.Colors.surface.opacity(0.55), in: Capsule())
                            .accessibilityIdentifier("assistant.sourceTrust.\(tier.rawValue)")
                    }
                }
                if tiers.contains(.webGeneral) {
                    Text("General web sources may be stale — confirm important facts officially.")
                        .font(DesignSystem.Fonts.main(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
            }
            .padding(.top, 2)
        }
    }

    func sourceMetadataLabel(_ source: AssistantReplySource) -> String {
        var parts: [String] = []
        if let tool = source.toolName, !tool.isEmpty {
            parts.append(tool)
        }
        if let hop = source.hopIndex {
            parts.append("hop \(hop + 1)")
        }
        if let latencyMS = source.latencyMS {
            parts.append("\(latencyMS)ms")
        }
        return parts.joined(separator: " · ")
    }
    @ViewBuilder
    func pendingActionCard(_ action: AssistantPendingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pending Assistant Action")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)

            Text(actionTitle(action))
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Text(actionDetail(action))
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textLight)

            Text(actionDiffPreview(action))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                Button("Confirm") {
                    confirmPendingAction(action)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("assistant.pendingAction.confirm")

                Button("Cancel") {
                    cancelPendingAction()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("assistant.pendingAction.cancel")
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.glassCardBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending assistant action: \(actionTitle(action))")
        .accessibilityIdentifier("assistant.pendingAction.card")
    }

    func actionTitle(_ action: AssistantPendingAction) -> String {
        switch action.kind {
        case .createTask:
            return "Create Task: \(action.title)"
        case .createEvent:
            return "Create Event: \(action.title)"
        case .editTask:
            return "Edit Task: \(action.originalTitle ?? action.title)"
        case .editEvent:
            return "Edit Event: \(action.originalTitle ?? action.title)"
        case .deleteTask:
            return "Delete Task: \(action.title)"
        case .deleteEvent:
            return "Delete Event: \(action.title)"
        case .saveWebLearning:
            return "Save Web Learning: \(action.title)"
        case .syncSyllabusDeadlines:
            return action.title
        }
    }

    func actionDetail(_ action: AssistantPendingAction) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        switch action.kind {
        case .syncSyllabusDeadlines:
            return action.webLearningSummary ?? "Creates tasks from syllabus due dates."
        case .createTask:
            if let dueDate = action.dueDate {
                return "Due: \(formatter.string(from: dueDate))"
            }
            return "Due: Not set"
        case .createEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                return "Time: Not set"
            }
            if action.allDay {
                return "Time: All day on \(formatter.string(from: startDate))"
            }
            return "Time: \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
        case .editTask:
            let dueText: String
            if let dueDate = action.dueDate {
                dueText = formatter.string(from: dueDate)
            } else {
                dueText = "No due time"
            }
            return "Updated title: \(action.title) | Updated due: \(dueText)"
        case .editEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                return "Updated event time is incomplete"
            }
            if action.allDay {
                return "Updated time: All day on \(formatter.string(from: startDate))"
            }
            return "Updated time: \(formatter.string(from: startDate)) to \(formatter.string(from: endDate))"
        case .deleteTask:
            return "Delete the existing task that best matches this title."
        case .deleteEvent:
            return "Delete the existing event that best matches this title."
        case .saveWebLearning:
            let urlCount = action.webLearningSourceURLs?.count ?? 0
            return "Stores a short summary on this Mac (\(urlCount) source URL(s)). Tags: \(action.webLearningTags ?? "none")"
        }
    }

    func actionDiffPreview(_ action: AssistantPendingAction) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        switch action.kind {
        case .createTask:
            return "Before: Task \"\(action.title)\" not present\nAfter:  Task \"\(action.title)\" created"
        case .createEvent:
            return "Before: Event \"\(action.title)\" not present\nAfter:  Event \"\(action.title)\" created"
        case .editTask:
            let oldDue = action.previousDueDate.map { formatter.string(from: $0) } ?? "No due time"
            let newDue = action.dueDate.map { formatter.string(from: $0) } ?? "No due time"
            return "Before: Task \"\(action.originalTitle ?? action.title)\" | Due: \(oldDue)\nAfter:  Task \"\(action.title)\" | Due: \(newDue)"
        case .editEvent:
            let oldStart = action.previousStartDate.map { formatter.string(from: $0) } ?? "—"
            let oldEnd = action.previousEndDate.map { formatter.string(from: $0) } ?? "—"
            let newStart = action.startDate.map { formatter.string(from: $0) } ?? "—"
            let newEnd = action.endDate.map { formatter.string(from: $0) } ?? "—"
            return "Before: Event \"\(action.originalTitle ?? action.title)\" | \(oldStart) to \(oldEnd)\nAfter:  Event \"\(action.title)\" | \(newStart) to \(newEnd)"
        case .deleteTask:
            return "Before: Task \"\(action.title)\" present\nAfter:  Task \"\(action.title)\" removed"
        case .deleteEvent:
            return "Before: Event \"\(action.title)\" present\nAfter:  Event \"\(action.title)\" removed"
        case .saveWebLearning:
            let preview = String((action.webLearningSummary ?? "").prefix(400))
            return "Before: Not saved\nAfter:  Saved note \"\(action.title)\"\n\n\(preview)"
        case .syncSyllabusDeadlines:
            let count = action.webLearningTags.flatMap { raw -> Int? in
                guard let data = raw.data(using: .utf8),
                      let drafts = try? JSONDecoder().decode([SyllabusDeadlineDraftPayload].self, from: data) else {
                    return nil
                }
                return drafts.count
            } ?? 0
            return "Before: No syllabus deadline tasks\nAfter:  \(count) planner task(s) from syllabus due dates"
        }
    }
}
