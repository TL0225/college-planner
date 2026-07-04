// UnlockView.swift
// Feature: Core
// Purpose: Core module — UnlockView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
// import LocalAuthentication

struct UnlockView: View {
    @Environment(AppContainer.self) private var container
    private var securityManager: SecurityManager { container.securityManager }
    @State private var isWorking = false
    @State private var isAuthenticating = false
    @State private var authenticationAttemptToken: UUID? = nil
    @State private var authenticationWatchdogTask: Task<Void, Never>? = nil

    private func beginAuthenticationAttempt() {
        guard !isWorking && !isAuthenticating else { return }

        isAuthenticating = true
        let token = UUID()
        authenticationAttemptToken = token

        #if DEBUG
        UnlockDebugLog.log("UnlockView: authentication attempt started (token=\(token.uuidString))")
        #endif

        authenticationWatchdogTask?.cancel()
        authenticationWatchdogTask = Task {
            // These sleeps are intentionally coarse; we just want a breadcrumb trail.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, authenticationAttemptToken == token else { return }
            #if DEBUG
            UnlockDebugLog.log("UnlockView: WATCHDOG token=\(token.uuidString) still waiting after 2s")
            #endif

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, authenticationAttemptToken == token else { return }
            #if DEBUG
            UnlockDebugLog.log("UnlockView: WATCHDOG token=\(token.uuidString) still waiting after 5s")
            #endif

            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, authenticationAttemptToken == token else { return }
            #if DEBUG
            UnlockDebugLog.log("UnlockView: WATCHDOG token=\(token.uuidString) still waiting after 10s")
            #endif
        }
    }

    private func endAuthenticationAttempt() {
        isAuthenticating = false
        authenticationAttemptToken = nil
        authenticationWatchdogTask?.cancel()
        authenticationWatchdogTask = nil
    }

    private func handleAuthenticationResult(_ result: Result<Void, any Error>) {
        endAuthenticationAttempt()

        switch result {
        case .success:
            #if DEBUG
            UnlockDebugLog.log("UnlockView: auth success (LocalAuthenticationView)")
            #endif

            guard !isWorking else { return }
            isWorking = true

            Task {
                await MainActor.run {
                    securityManager.setLastUnlockErrorForDisplay(nil)
                }
                _ = await securityManager.completeUnlockAfterAuthentication()
                await MainActor.run { isWorking = false }
            }

        case .failure(let error):
            #if DEBUG
            UnlockDebugLog.log("UnlockView: auth failure (LocalAuthenticationView): \(error.localizedDescription)")
            #endif

            Task { @MainActor in
                securityManager.setLastUnlockErrorForDisplay(error.localizedDescription)
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(DesignSystem.Fonts.main(size: 44, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primary)

            VStack(spacing: 6) {
                Text("Locked")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)

                Text("Biometric authentication is temporarily disabled. Use Unlock to continue.")
                    .font(DesignSystem.Fonts.main(size: 13))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .multilineTextAlignment(.center)

            if let err = securityManager.lastUnlockError, !err.isEmpty {
                Text(err)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .multilineTextAlignment(.center)
            }

            Button {
                guard !isWorking else { return }
                isWorking = true
                Task {
                    await MainActor.run {
                        securityManager.setLastUnlockErrorForDisplay(nil)
                    }
                    _ = await securityManager.completeUnlockAfterAuthentication()
                    await MainActor.run { isWorking = false }
                }
            } label: {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.9)
                    }
                    Text(isWorking ? "Unlocking…" : "Unlock")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minWidth: 140)
                .background(DesignSystem.Colors.primary)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .controlSize(.large)
            .disabled(isWorking)

            // Biometric auth path is intentionally disabled for now.
            // Re-enable by restoring the LocalAuthenticationView block below.
            /*
            LocalAuthenticationView(
                reason: Text("Access your encrypted student data"),
                context: nil,
                result: handleAuthenticationResult
            ) {
                HStack(spacing: 10) {
                    if isAuthenticating || isWorking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.9)
                    }
                    Text(isWorking ? "Unlocking…" : (isAuthenticating ? "Authenticating…" : "Unlock"))
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minWidth: 140)
                .background(DesignSystem.Colors.primary)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 14))
                .simultaneousGesture(TapGesture().onEnded {
                    beginAuthenticationAttempt()
                })
            }
            .controlSize(.large)
            .disabled(isWorking || isAuthenticating)
            */
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .onAppear {
            #if DEBUG
            UnlockDebugLog.log("UnlockView: onAppear")
            #endif
        }
    }
}

#Preview {
    UnlockView()
        }

