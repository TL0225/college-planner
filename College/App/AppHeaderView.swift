// AppHeaderView.swift
// Feature: App
// Purpose: App module — AppHeaderView.
// Data: CollegePersistence / repositories when applicable.

//
//  AppHeaderView.swift
//  College
//

import SwiftUI

struct AppHeaderView: View {
    let title: String
    let activePage: AppPage

    var body: some View {
        HStack(spacing: 0) {
            if activePage == .brightspace {
                BrightspaceHeaderControls()
            }
            
            Spacer()

            // Right Utilities
            HStack(spacing: 20) {

                // Integrated Search & AI Button inside a shared pill
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "64748B"))
                        Text("Search...")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "64748B"))
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 12)
                    
                    Button(action: {}) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Ask AI")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "1E3A8A"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(hex: "DBEAFE"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
                .frame(width: 320, height: 36)
                .background(Color(hex: "E2E8F0").opacity(0.8))
                .clipShape(Capsule())

                // Divider
                Divider()
                    .background(Color(hex: "CBD5E1"))
                    .frame(height: 20)
                
                // Notifications & Settings
                HStack(spacing: 18) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "64748B"))
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle().fill(Color(hex: "D97706")).frame(width: 6, height: 6)
                            )
                            .offset(x: 2, y: -2)
                    }
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "64748B"))
                }
                
                // Profile Bubble
                Circle()
                    .fill(Color(hex: "2563EB"))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("JD")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .overlay(
            Group {
                if activePage != .brightspace {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "111827"))
                }
            },
            alignment: .center
        )
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(
            Color.white.opacity(0.6)
                .background(.ultraThinMaterial)
        )
        // Ensure there is a subtle bottom border if needed. 
        .overlay(
            Rectangle()
                .fill(Color(hex: "CBD5E1").opacity(0.5))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

private struct BrightspaceHeaderControls: View {
    @Environment(AppContainer.self) private var container
    private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 20) {
                Button(action: { brightspaceCoordinator.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brightspaceCoordinator.canGoBack ? Color(hex: "475569") : Color(hex: "CBD5E1"))
                }
                .disabled(!brightspaceCoordinator.canGoBack)
                .buttonStyle(.plain)

                Button(action: { brightspaceCoordinator.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brightspaceCoordinator.canGoForward ? Color(hex: "475569") : Color(hex: "CBD5E1"))
                }
                .disabled(!brightspaceCoordinator.canGoForward)
                .buttonStyle(.plain)

                Button(action: { brightspaceCoordinator.reload() }) {
                    Image(systemName: brightspaceCoordinator.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "475569"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(brightspaceCoordinator.pageTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1e293b"))
                if let url = brightspaceCoordinator.currentURL {
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(hex: "64748b"))
                }
            }
        }
    }
}
