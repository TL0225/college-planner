import SwiftUI

struct DegreeSettingsView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    
    // Get degree information from profile
    var degreeLevel: String {
        return coreDataManager.profile?.degreeLevel ?? "Undergraduate"
    }
    
    var degreeType: String {
        return coreDataManager.profile?.degreeType ?? "Bachelor of Science (BS)"
    }
    
    var degreeTypeShort: String {
        return DegreeConfiguration.shortForm(from: degreeType)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Degree Settings", systemImage: "graduationcap.fill")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Degree Track")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Set in Academic Identity")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    Spacer()
                    Text("ACTIVE")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Display degree level and type
                VStack(alignment: .leading, spacing: 8) {
                    Text(degreeLevel)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    
                    HStack {
                        Text(degreeTypeShort)
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 2)
                )
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .font(.system(size: 12))
                    Text("Change your degree level and type in the Profile → Academic Identity section.")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            .padding()
            .background(Color(hex: "f8f9fa"))
            .cornerRadius(16)
            
            // Honors
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Honors")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Recognized achievements")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    Spacer()
                    Button("Manage") {
                        // Action
                    }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.primary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                HStack(spacing: 16) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .frame(width: 48, height: 48)
                        .background(DesignSystem.Colors.warning.opacity(0.1))
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dean's List Fall 2024")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("College of Engineering")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
            }
            .padding()
            .background(Color(hex: "f8f9fa"))
            .cornerRadius(16)
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}
