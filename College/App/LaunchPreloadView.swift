// LaunchPreloadView.swift
// Feature: App
// Purpose: App module — LaunchPreloadView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct LaunchPreloadView: View {
    @Environment(AppContainer.self) private var appContainer
    private var preload: LaunchPreloadCoordinator { appContainer.launchPreloadCoordinator }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @State private var didAppear = false

    private var motionReduced: Bool { systemReduceMotion || appReduceMotion }
    private var percentValue: Int {
        min(100, max(0, Int((preload.overallProgress * 100).rounded())))
    }

    var body: some View {
        ZStack {
            LaunchBackground()

            VStack(spacing: 18) {
                LaunchHeroCard(
                    title: preload.currentStepTitle,
                    status: preload.statusText,
                    percentValue: percentValue,
                    overallProgress: preload.overallProgress,
                    motionReduced: motionReduced
                )

                LaunchProgressTimeline(
                    currentStepNumber: preload.currentStepNumber,
                    totalStepCount: preload.totalStepCount,
                    currentStepProgress: preload.currentStepProgress,
                    motionReduced: motionReduced
                )

                LaunchStatusDetails(
                    detailText: preload.currentStepDetailText,
                    etaText: preload.etaText,
                    retryAttempt: preload.retryAttempt,
                    currentStepTitle: preload.currentStepTitle,
                    errorText: preload.lastErrorText,
                    motionReduced: motionReduced
                )
            }
            .frame(width: 560)
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 28, x: 0, y: 18)
            .opacity(didAppear || motionReduced ? 1 : 0)
            .scaleEffect(didAppear || motionReduced ? 1 : 0.985)
            .animation(motionReduced ? nil : .easeOut(duration: 0.28), value: didAppear)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("College launch progress")
            .accessibilityValue("\(percentValue)% complete. \(preload.currentStepTitle). \(preload.statusText)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onAppear { didAppear = true }
    }
}

private struct LaunchBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.10),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -260, y: -180)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 280, y: 210)
        }
        .ignoresSafeArea()
    }
}

private struct LaunchHeroCard: View {
    let title: String
    let status: String
    let percentValue: Int
    let overallProgress: Double
    let motionReduced: Bool

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(width: 58, height: 58)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("College")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Preparing your workspace")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ProgressView()
                    .controlSize(.regular)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(status)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("launch.statusText")
                    }

                    Spacer(minLength: 12)

                    Text("\(percentValue)%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(motionReduced ? .opacity : .numericText(value: Double(percentValue)))
                }

                ProgressView(value: overallProgress)
                    .progressViewStyle(.linear)
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .accessibilityLabel("Overall startup progress")
                    .accessibilityValue("\(percentValue)%")
            }
        }
    }
}

private struct LaunchProgressTimeline: View {
    let currentStepNumber: Int
    let totalStepCount: Int
    let currentStepProgress: Double
    let motionReduced: Bool

    private var steps: [LaunchStepPresentation] {
        LaunchPreloadCoordinator.StepID.allCases.map(LaunchStepPresentation.init(step:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Startup checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Step \(max(0, currentStepNumber))/\(max(1, totalStepCount))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    LaunchStepIndicator(
                        step: step,
                        state: state(for: index),
                        progress: currentStepProgress,
                        motionReduced: motionReduced
                    )
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Startup checklist")
        .accessibilityValue("Step \(max(0, currentStepNumber)) of \(max(1, totalStepCount))")
    }

    private func state(for index: Int) -> LaunchStepIndicator.State {
        let stepNumber = index + 1
        if currentStepNumber == 0 { return .pending }
        if stepNumber < currentStepNumber { return .complete }
        if stepNumber == currentStepNumber { return .active }
        return .pending
    }
}

private struct LaunchStepIndicator: View {
    enum State {
        case complete
        case active
        case pending
    }

    let step: LaunchStepPresentation
    let state: State
    let progress: Double
    let motionReduced: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(backgroundStyle)
                    .frame(width: 34, height: 34)
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(foregroundStyle)
            }
            .scaleEffect(state == .active && !motionReduced ? 1.05 : 1)
            .animation(motionReduced ? nil : .spring(response: 0.25, dampingFraction: 0.78), value: stateDescription)

            Text(step.title)
                .font(.caption2.weight(state == .active ? .semibold : .medium))
                .foregroundStyle(state == .pending ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(stateDescription)")
        .accessibilityValue(state == .active ? "\(Int((progress * 100).rounded()))% in this step" : "")
    }

    private var symbolName: String {
        switch state {
        case .complete:
            return "checkmark"
        case .active:
            return step.symbol
        case .pending:
            return step.symbol
        }
    }

    private var backgroundStyle: Color {
        switch state {
        case .complete:
            return Color.green.opacity(0.18)
        case .active:
            return Color.accentColor.opacity(0.18)
        case .pending:
            return Color.secondary.opacity(0.12)
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .complete:
            return .green
        case .active:
            return Color.accentColor
        case .pending:
            return .secondary
        }
    }

    private var stateDescription: String {
        switch state {
        case .complete:
            return "complete"
        case .active:
            return "in progress"
        case .pending:
            return "pending"
        }
    }
}

private struct LaunchStatusDetails: View {
    let detailText: String
    let etaText: String?
    let retryAttempt: Int
    let currentStepTitle: String
    let errorText: String?
    let motionReduced: Bool

    private var hasDetails: Bool {
        !detailText.isEmpty ||
            (etaText?.isEmpty == false) ||
            retryAttempt > 0 ||
            (errorText?.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorText, !errorText.isEmpty {
                LaunchErrorBanner(message: errorText)
                    .transition(motionReduced ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            if hasDetails {
                VStack(alignment: .leading, spacing: 8) {
                    if !detailText.isEmpty {
                        Label(detailText, systemImage: "text.line.first.and.arrowtriangle.forward")
                            .lineLimit(2)
                    }

                    if let etaText, !etaText.isEmpty {
                        Label(etaText, systemImage: "clock")
                    }

                    if retryAttempt > 0 {
                        Label("Retrying \(currentStepTitle.lowercased())... Attempt \(retryAttempt)", systemImage: "arrow.clockwise")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(motionReduced ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: detailText)
        .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: errorText)
        .accessibilityElement(children: .contain)
    }
}

private struct LaunchErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Startup needs attention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DesignSystem.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignSystem.Colors.warning.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Startup needs attention")
        .accessibilityValue(message)
    }
}

private struct LaunchStepPresentation: Identifiable {
    let id: LaunchPreloadCoordinator.StepID
    let title: String
    let symbol: String

    init(step: LaunchPreloadCoordinator.StepID) {
        id = step
        switch step {
        case .storeReady:
            title = "Database"
            symbol = "externaldrive.fill"
        case .coreSnapshots:
            title = "Local Data"
            symbol = "tray.full.fill"
        case .calendarWarmup:
            title = "Calendar"
            symbol = "calendar"
        case .brightspaceWarmup:
            title = "Brightspace"
            symbol = "network"
        case .integrationsWarmup:
            title = "Integrations"
            symbol = "link"
        case .featureWarmup:
            title = "Features"
            symbol = "sparkles"
        }
    }
}

