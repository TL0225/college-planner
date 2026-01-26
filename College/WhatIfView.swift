import SwiftUI

struct WhatIfView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager

    var body: some View {
        HStack(spacing: 0) {
            WhatIfSidebar()
                .frame(width: 320)
                .background(DesignSystem.Colors.surface)
                .overlay(
                    Rectangle()
                        .frame(width: 1)
                        .foregroundColor(Color(hex: "f1f5f9")),
                    alignment: .trailing
                )
            
            WhatIfMainContent()
        }
    }
}

struct WhatIfSidebar: View {
    @EnvironmentObject var coreDataManager: CoreDataManager

    private var currentMajorTitle: String {
        let major = (coreDataManager.profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return major.isEmpty ? "Select Major" : major
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Scenario Selector
                HStack {
                    Button(action: {}) {
                        HStack {
                            Image(systemName: "flask")
                                .foregroundColor(DesignSystem.Colors.secondary)
                            Text("Scenario A")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .padding()
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(DesignSystem.Colors.secondary)
                            .cornerRadius(12)
                    }
                }
                
                // Current Plan
                PlanStatusCard(title: "Current Plan", status: "Active", statusColor: DesignSystem.Colors.primary, major: currentMajorTitle, progress: 0.45, creditsLeft: 55, color: DesignSystem.Colors.primary)
                
                // Hypothetical Plan
                PlanStatusCard(title: "Hypothetical Plan", status: "Draft", statusColor: DesignSystem.Colors.info, major: currentMajorTitle, progress: 0.25, creditsLeft: 82, color: DesignSystem.Colors.info, isDashed: true)
                
                Divider()
                
                // Simulation Controls
                VStack(alignment: .leading, spacing: 16) {
                    Text("Simulation Controls")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    
                    ControlRow(title: "Add Summer Semesters", subtitle: "Accelerate graduation", control: Toggle("", isOn: .constant(false)).labelsHidden())
                    
                    ControlRow(title: "Max Credits / Sem", subtitle: "Current: 18 Credits", control: HStack {
                        Button("-") {}
                            .frame(width: 24, height: 24)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(Circle())
                            .shadow(radius: 1)
                        Text("18").font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        Button("+") {}
                            .frame(width: 24, height: 24)
                            .background(DesignSystem.Colors.surface)
                            .clipShape(Circle())
                            .shadow(radius: 1)
                    })
                }
            }
            .padding()
        }
    }
}

struct PlanStatusCard: View {
    let title: String
    let status: String
    let statusColor: Color
    let major: String
    let progress: Double
    let creditsLeft: Int
    let color: Color
    var isDashed: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                Text("Status: \(status)")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading) {
                Text(isDashed ? "MAJOR SWITCH" : "MAJOR")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(color)
                    .tracking(1)
                
                Text(major)
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .padding(.bottom, 4)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geometry.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)
                .padding(.bottom, 4)
                
                HStack {
                    Text("\(Int(progress * 100))% \(isDashed ? "Transferable" : "Complete")")
                    Spacer()
                    Text("\(creditsLeft) Credits Left")
                }
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
            }
            .padding()
            .background(color.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: isDashed ? [5] : []))
            )
        }
    }
}

struct ControlRow<Content: View>: View {
    let title: String
    let subtitle: String
    let control: Content
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text(subtitle)
                    .font(DesignSystem.Fonts.main(size: 10))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            Spacer()
            control
        }
        .padding()
        .background(DesignSystem.Colors.bgMain)
        .cornerRadius(12)
    }
}

struct WhatIfMainContent: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text("What If Scenarios")
                        .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text("Explore how changing your major or adding a minor impacts your timeline.")
                        .font(DesignSystem.Fonts.main(size: 14))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Label("Save Scenario", systemImage: "square.and.arrow.down")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DesignSystem.Colors.surface)
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    }
                    
                    Button(action: {}) {
                        Label("Run Simulation", systemImage: "play.fill")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(LinearGradient(colors: [DesignSystem.Colors.secondary, DesignSystem.Colors.accent], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(color: DesignSystem.Colors.secondary.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                }
            }
            .padding(32)
            
            Spacer()
            Text("Scenario Content Placeholder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.bgMain.opacity(0.3))
        }
    }
}
