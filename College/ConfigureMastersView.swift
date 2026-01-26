import SwiftUI

struct ConfigureMastersView: View {
    @Binding var isPresented: Bool
    var onBack: () -> Void
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    
    @State private var degreeType: String = "Master of Science (M.S.)"
    @State private var major: String = ""
    @State private var concentration: String = ""
    
    let degreeTypes = [
        "Master of Science (M.S.)",
        "Master of Arts (M.A.)",
        "Master of Business Administration (M.B.A.)",
        "Master of Engineering (M.Eng.)",
        "Master of Education (M.Ed.)",
        "Master of Fine Arts (M.F.A.)",
        "Other"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Gradient Top Border
            LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary, DesignSystem.Colors.accent], startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
            
            VStack(spacing: 32) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill") // workspace_premium equivalent
                                .font(.system(size: 30))
                                .foregroundColor(DesignSystem.Colors.secondary)
                                .padding(8)
                                .background(DesignSystem.Colors.secondary.opacity(0.1))
                                .cornerRadius(12)
                            
                            Text("Configure Master's Degree")
                                .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        
                        Text("Define your program details to personalize your dashboard.")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(.leading, 4)
                    }
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(8)
                            .background(Color.clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Form Fields
                VStack(spacing: 24) {
                    // Degree Type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Master's Degree Type")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .padding(.leading, 4)
                        
                        Menu {
                            ForEach(degreeTypes, id: \.self) { type in
                                Button(type) {
                                    degreeType = type
                                }
                            }
                        } label: {
                            HStack {
                                Text(degreeType)
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.secondary)
                            }
                            .padding(16)
                            .background(Color(hex: "f8fafc")) // Slate 50
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Major / Field of Study
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Major / Field of Study")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .padding(.leading, 4)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap") // school
                                .font(.system(size: 18))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            TextField("e.g. Information Science", text: $major)
                                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        .padding(16)
                        .background(Color(hex: "f8fafc"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                    
                    // Concentration
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Concentration")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            
                            Text("Optional")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(hex: "f1f5f9"))
                                .cornerRadius(8)
                        }
                        .padding(.leading, 4)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2") // category
                                .font(.system(size: 18))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            ZStack(alignment: .leading) {
                                if concentration.isEmpty {
                                    Text("e.g. Applied Economics")
                                        .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                                TextField("", text: $concentration)
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .textFieldStyle(.plain)
                                    .background(Color.clear)
                                    .frame(height: 24)
                            }
                        }
                        .padding(16)
                        .background(Color(hex: "f8fafc"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                }
                
                // Footer
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left")
                            Text("Back")
                        }
                        .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    Button(action: {
                        let planName = major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? degreeType
                            : "\(degreeType) — \(major.trimmingCharacters(in: .whitespacesAndNewlines))"

                        _ = coreDataManager.addPlan(
                            name: planName,
                            type: degreeType,
                            major: major.trimmingCharacters(in: .whitespacesAndNewlines),
                            minor: "",
                            concentration: concentration.trimmingCharacters(in: .whitespacesAndNewlines)
                        )

                        notifications.post(
                            kind: .success,
                            title: "Plan Created",
                            message: "Saved \(planName).",
                            isDismissible: true,
                            autoDismissAfter: 3
                        )

                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Text("Save Configuration")
                            Image(systemName: "checkmark")
                        }
                        .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(LinearGradient(colors: [DesignSystem.Colors.secondary, DesignSystem.Colors.primary], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12)
                        .shadow(color: DesignSystem.Colors.secondary.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 24)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(hex: "f1f5f9")),
                    alignment: .top
                )
            }
            .padding(40)
        }
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.2), radius: 20)
        .frame(maxWidth: 700) // Slightly narrower than the selection screen
        .padding(16)
    }
}
