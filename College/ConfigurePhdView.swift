import SwiftUI

struct ConfigurePhdView: View {
    @Binding var isPresented: Bool
    var onBack: () -> Void
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    
    @State private var degreeType: String = "Doctor of Philosophy (Ph.D.)"
    @State private var specialization: String = ""
    @State private var dissertationTopic: String = ""
    
    let degreeTypes = [
        "Doctor of Philosophy (Ph.D.)",
        "Doctor of Education (Ed.D.)",
        "Doctor of Medicine (M.D.)",
        "Juris Doctor (J.D.)",
        "Other"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Gradient Top Border
            LinearGradient(colors: [DesignSystem.Colors.accent, Color(hex: "f472b6")], startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
            
            VStack(spacing: 32) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 30))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(8)
                                .background(DesignSystem.Colors.accent.opacity(0.1))
                                .cornerRadius(12)
                            
                            Text("Configure PhD Degree")
                                .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        
                        Text("Customize your doctoral research path and specialization.")
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
                        Text("Doctoral Degree Type")
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
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                            .padding(16)
                            .background(Color(hex: "f8fafc"))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Specialization
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Specialization / Area of Study")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .padding(.leading, 4)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 18))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            TextField("e.g. Quantum Computing, Molecular Biology", text: $specialization)
                                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .textFieldStyle(.plain)
                        }
                        .padding(16)
                        .background(Color(hex: "f8fafc"))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                    
                    // Dissertation Topic
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Dissertation Topic")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            
                            Text("OPTIONAL")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "f1f5f9"))
                                .cornerRadius(4)
                        }
                        .padding(.leading, 4)
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 18))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.top, 4)
                            
                            ZStack(alignment: .topLeading) {
                                if dissertationTopic.isEmpty {
                                    Text("Briefly describe your proposed research topic or thesis question...")
                                        .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .padding(.top, 8)
                                }
                                TextField("", text: $dissertationTopic, axis: .vertical)
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .textFieldStyle(.plain)
                                    .background(Color.clear)
                                    .frame(minHeight: 80, alignment: .top)
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
                        let trimmedSpec = specialization.trimmingCharacters(in: .whitespacesAndNewlines)
                        let planName = trimmedSpec.isEmpty
                            ? degreeType
                            : "\(degreeType) — \(trimmedSpec)"

                        _ = coreDataManager.addPlan(
                            name: planName,
                            type: degreeType,
                            major: trimmedSpec,
                            minor: "",
                            concentration: dissertationTopic.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        .background(LinearGradient(colors: [DesignSystem.Colors.accent, Color(hex: "f472b6")], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12)
                        .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 5, x: 0, y: 2)
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
        .frame(maxWidth: 700)
        .padding(16)
    }
}
