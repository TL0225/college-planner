// LaunchPreloadView.swift
// Feature: App
// Purpose: App module — LaunchPreloadView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

private let launchBlue = Color(red: 0.18, green: 0.51, blue: 1.0)

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
        LaunchMinimalCard(
            overallProgress: preload.overallProgress,
            statusText: preload.statusText,
            errorText: preload.lastErrorText,
            motionReduced: motionReduced
        )
        .padding(LaunchSplashWindowMetrics.shadowPadding)
        .fixedSize()
        .opacity(didAppear || motionReduced ? 1 : 0)
        .scaleEffect(didAppear || motionReduced ? 1 : 0.96)
        .animation(motionReduced ? nil : .spring(response: 0.4, dampingFraction: 0.82), value: didAppear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("College launch progress")
        .accessibilityValue("\(percentValue)% complete. \(preload.statusText)")
        .background(MainWindowSplashPlacementView())
        .onAppear { didAppear = true }
    }
}

private struct LaunchMinimalCard: View {
    let overallProgress: Double
    let statusText: String
    let errorText: String?
    let motionReduced: Bool

    var body: some View {
        VStack(spacing: 0) {
            LaunchLogoSection()

            Spacer().frame(height: 36)

            LaunchProgressSection(
                overallProgress: overallProgress,
                statusText: statusText,
                errorText: errorText,
                motionReduced: motionReduced
            )
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 44)
        .frame(width: LaunchSplashWindowMetrics.cardWidth, height: LaunchSplashWindowMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: launchBlue.opacity(0.10), radius: 48, x: 0, y: 24)
    }
}

private struct LaunchLogoSection: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(launchBlue.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .blur(radius: 18)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [launchBlue, launchBlue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            Text("College")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct LaunchProgressSection: View {
    let overallProgress: Double
    let statusText: String
    let errorText: String?
    let motionReduced: Bool

    var body: some View {
        VStack(spacing: 12) {
            LaunchProgressBar(progress: overallProgress, motionReduced: motionReduced)

            Group {
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                } else {
                    Text(statusText)
                        .foregroundStyle(Color.white.opacity(0.38))
                        .accessibilityIdentifier("launch.statusText")
                }
            }
            .font(.system(size: 12, weight: .regular))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: statusText)
            .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: errorText)
        }
    }
}

private struct LaunchProgressBar: View {
    let progress: Double
    let motionReduced: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [launchBlue, launchBlue.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * progress), height: 4)
                    .animation(motionReduced ? nil : .spring(response: 0.5, dampingFraction: 0.88), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading progress")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

