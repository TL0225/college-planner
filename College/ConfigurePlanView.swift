import SwiftUI

struct ConfigurePlanView: View {
    @Binding var isPresented: Bool
    @State private var selectedDegree: DegreeLevel = .bachelors
    @State private var showMastersConfig = false
    @State private var showBachelorsConfig = false
    @State private var showPhdConfig = false
    
    enum DegreeLevel {
        case bachelors, masters, phd
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color(hex: "0f172a").opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            if showMastersConfig {
                ConfigureMastersView(isPresented: $isPresented, onBack: {
                    withAnimation {
                        showMastersConfig = false
                    }
                })
                .transition(.move(edge: .trailing))
            } else if showBachelorsConfig {
                ConfigureBachelorsView(isPresented: $isPresented, onBack: {
                    withAnimation {
                        showBachelorsConfig = false
                    }
                })
                .transition(.move(edge: .trailing))
            } else if showPhdConfig {
                ConfigurePhdView(isPresented: $isPresented, onBack: {
                    withAnimation {
                        showPhdConfig = false
                    }
                })
                .transition(.move(edge: .trailing))
            } else {
                // Modal Content
                VStack(spacing: 0) {
                    // Gradient Top Border
                    LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary, DesignSystem.Colors.accent], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 8)
                    
                    VStack(spacing: 40) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Image(systemName: "graduationcap.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(DesignSystem.Colors.primary)
                                        .padding(8)
                                        .background(DesignSystem.Colors.primary.opacity(0.1))
                                        .cornerRadius(12)
                                    
                                    Text("Configure Academic Plan")
                                        .font(DesignSystem.Fonts.main(size: 30, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                }
                                
                                Text("Select your degree level to begin customizing your path.")
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
                        
                        // Options Grid
                        HStack(spacing: 24) {
                            DegreeOptionCard(
                                title: "Bachelors",
                                description: "Undergraduate degrees including BA, BS, and BFA programs.",
                                icon: "book.fill",
                                color: DesignSystem.Colors.primary,
                                isSelected: selectedDegree == .bachelors
                            ) {
                                selectedDegree = .bachelors
                            }
                            
                            DegreeOptionCard(
                                title: "Masters",
                                description: "Graduate studies including MA, MS, and MBA programs.",
                                icon: "star.fill", // workspace_premium equivalent
                                color: DesignSystem.Colors.secondary,
                                isSelected: selectedDegree == .masters
                            ) {
                                selectedDegree = .masters
                            }
                            
                            DegreeOptionCard(
                                title: "PHD",
                                description: "Doctoral research and advanced dissertation tracks.",
                                icon: "brain.head.profile", // psychology equivalent
                                color: DesignSystem.Colors.accent,
                                isSelected: selectedDegree == .phd
                            ) {
                                selectedDegree = .phd
                            }
                        }
                        
                        // Footer
                        HStack(spacing: 16) {
                            Spacer()
                            
                            Button("Cancel") {
                                isPresented = false
                            }
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.clear)
                            .cornerRadius(12)
                            
                            Button(action: {
                                if selectedDegree == .masters {
                                    withAnimation {
                                        showMastersConfig = true
                                    }
                                } else if selectedDegree == .bachelors {
                                    withAnimation {
                                        showBachelorsConfig = true
                                    }
                                } else if selectedDegree == .phd {
                                    withAnimation {
                                        showPhdConfig = true
                                    }
                                } else {
                                    // Continue action for other degrees
                                    isPresented = false
                                }
                            }) {
                                HStack {
                                    Text("Continue")
                                    Image(systemName: "arrow.right")
                                }
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 12)
                                .background(DesignSystem.Colors.primary)
                                .cornerRadius(12)
                                .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 5, x: 0, y: 2)
                            }
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
                .frame(maxWidth: 900)
                .padding(16)
                .transition(.opacity)
            }
        }
        .transition(.opacity)
        .zIndex(100)
    }
}

struct DegreeOptionCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? color : Color.white)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                        
                        Image(systemName: icon)
                            .font(.system(size: 32))
                            .foregroundColor(isSelected ? .white : color)
                    }
                    .scaleEffect(isSelected ? 1.0 : 1.0) // Could add hover scale if needed
                    
                    VStack(spacing: 8) {
                        Text(title)
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(isSelected ? color : DesignSystem.Colors.textMain)
                        
                        Text(description)
                            .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .background(isSelected ? color.opacity(0.05) : DesignSystem.Colors.bgMain.opacity(0.5))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(isSelected ? color : Color(hex: "e2e8f0"), lineWidth: isSelected ? 2 : 2)
                )
                .shadow(color: isSelected ? color.opacity(0.1) : Color.clear, radius: 10)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(color)
                        .padding(20)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
