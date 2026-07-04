// InterviewPrepView.swift
// Feature: Career
// Purpose: Career module — InterviewPrepView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct InterviewPrepView: View {
    enum QuestionType: String, CaseIterable, Identifiable {
        case all = "All"
        case behavioral = "Behavioral"
        case technical = "Technical"
        case systemDesign = "System Design"
        case hr = "HR"
        case culture = "Culture"
        case starred = "✩ Starred"

        var id: String { rawValue }
    }

    enum Confidence: String, CaseIterable, Identifiable {
        case notStarted = "Not Started"
        case practicing = "Practicing"
        case confident = "Confident"

        var id: String { rawValue }
    }

    enum Difficulty: String {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"
    }

    struct PrepQuestion: Identifiable {
        let id: UUID
        var category: QuestionType
        var company: String
        var question: String
        var difficulty: Difficulty
        var confidence: Confidence
        var isStarred: Bool
        var notes: String
    }

    @State private var selectedType: QuestionType = .all
    @State private var selectedCompany = "All"
    @State private var questions: [PrepQuestion] = [
        PrepQuestion(
            id: UUID(),
            category: .behavioral,
            company: "Google",
            question: "Tell me about a time you had to deal with a difficult team member.",
            difficulty: .medium,
            confidence: .confident,
            isStarred: true,
            notes: ""
        ),
        PrepQuestion(
            id: UUID(),
            category: .systemDesign,
            company: "Airbnb",
            question: "Design a URL shortener service like bit.ly at scale.",
            difficulty: .hard,
            confidence: .practicing,
            isStarred: true,
            notes: ""
        ),
        PrepQuestion(
            id: UUID(),
            category: .technical,
            company: "Stripe",
            question: "Given a binary tree, write a function to find its maximum depth.",
            difficulty: .medium,
            confidence: .notStarted,
            isStarred: false,
            notes: ""
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topToolbar
                .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredIndexes, id: \.self) { index in
                        PrepQuestionCard(question: $questions[index]) {
                            questions.removeAll { $0.id == questions[index].id }
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.bgMain)
    }

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        statPill(dot: .blue, label: "Total Questions", value: "\(questions.count)")
                        statPill(dot: .green, label: "Confident", value: "\(questions.filter { $0.confidence == .confident }.count)")
                        statPill(dot: .orange, label: "Practicing", value: "\(questions.filter { $0.confidence == .practicing }.count)")
                        statPill(dot: .yellow, label: "Starred", value: "\(questions.filter { $0.isStarred }.count)")
                    }

                    questionCategoryFilter
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button("All") { selectedCompany = "All" }
                ForEach(companyOptions, id: \.self) { company in
                    Button(company) { selectedCompany = company }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Company: \(selectedCompany)")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            Button("+ Add Question") {
                questions.insert(
                    PrepQuestion(
                        id: UUID(),
                        category: .behavioral,
                        company: "All",
                        question: "New interview question...",
                        difficulty: .medium,
                        confidence: .notStarted,
                        isStarred: false,
                        notes: ""
                    ),
                    at: 0
                )
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.primary, in: Capsule(style: .continuous))
        }
    }

    private var questionCategoryFilter: some View {
        HStack(spacing: 4) {
            ForEach(QuestionType.allCases) { type in
                let selected = selectedType == type
                Button {
                    selectedType = type
                } label: {
                    Text(type.rawValue)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(DesignSystem.Colors.surface)
                                    .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.xs)
        .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
    }

    private func statPill(dot: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: Capsule(style: .continuous))
    }

    private var companyOptions: [String] {
        Array(Set(questions.map(\.company))).sorted()
    }

    private var filteredIndexes: [Int] {
        questions.indices.filter { idx in
            let q = questions[idx]
            if selectedType == .starred, !q.isStarred { return false }
            if selectedType != .all, selectedType != .starred, q.category != selectedType { return false }
            if selectedCompany != "All", q.company != selectedCompany { return false }
            return true
        }
    }
}

private struct PrepQuestionCard: View {
    @Binding var question: InterviewPrepView.PrepQuestion
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(question.category.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(categoryColor.opacity(0.14), in: Capsule(style: .continuous))
                    Text(question.difficulty.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(difficultyColor)
                }
                .frame(width: 92, alignment: .leading)

                Text(question.question)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(isExpanded ? nil : 2)

                HStack(spacing: 10) {
                    Button {
                        question.isStarred.toggle()
                    } label: {
                        Image(systemName: question.isStarred ? "star.fill" : "star")
                            .foregroundStyle(question.isStarred ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                confidencePill(.notStarted, tint: .secondary)
                confidencePill(.practicing, tint: .orange)
                confidencePill(.confident, tint: .green)
            }

            if isExpanded {
                TextEditor(text: $question.notes)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(DesignSystem.Spacing.sm)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func confidencePill(_ level: InterviewPrepView.Confidence, tint: Color) -> some View {
        let selected = question.confidence == level
        return Button {
            question.confidence = level
        } label: {
            Text(level.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? tint : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? tint.opacity(0.14) : Color.clear, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder((selected ? tint : Color.secondary.opacity(0.25)), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch question.category {
        case .behavioral: return .purple
        case .technical: return .orange
        case .systemDesign: return .blue
        case .hr: return .teal
        case .culture: return .pink
        case .all, .starred: return .secondary
        }
    }

    private var difficultyColor: Color {
        switch question.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}
