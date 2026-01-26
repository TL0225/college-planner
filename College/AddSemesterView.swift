import SwiftUI

struct AddSemesterView: View {
    @Binding var isPresented: Bool
    @ObservedObject var plan: PlanEntity
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    
    @State private var selectedTerm: String = "Fall"
    @State private var selectedYear: String = ""
    
    let terms = [
        (name: "Fall", icon: "leaf.fill"),
        (name: "Winter", icon: "snowflake"),
        (name: "Spring", icon: "camera.macro"),
        (name: "Summer", icon: "sun.max.fill")
    ]
    
    var body: some View {
        ZStack {
            backdrop
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(100)
    }
    
    var backdrop: some View {
        DesignSystem.Colors.textMain.opacity(0.22)
            .ignoresSafeArea()
            .onTapGesture {
                isPresented = false
            }
    }
    
    var content: some View {
        VStack(spacing: 32) {
            header
            iconAndTitle
            termSelection
            yearSelection
            createButton
        }
        .padding(32)
        .background(Color.white)
        .cornerRadius(32)
        .shadow(color: Color.black.opacity(0.2), radius: 20)
        .frame(maxWidth: 500)
        .padding(24)
    }
    
    var header: some View {
        HStack {
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(8)
                    .background(Color.clear)
            }
        }
        .padding(.bottom, -20)
    }
    
    var iconAndTitle: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.primary)
                .padding(16)
                .background(DesignSystem.Colors.primary.opacity(0.1))
                .clipShape(Circle())
            
            VStack(spacing: 8) {
                Text("Add New Semester")
                    .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                Text("Plan your next academic term")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
        }
    }
    
    var termSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT TERM")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .tracking(1)
            
            HStack(spacing: 12) {
                ForEach(terms, id: \.name) { term in
                    Button(action: { selectedTerm = term.name }) {
                        VStack(spacing: 8) {
                            Image(systemName: term.icon)
                                .font(.system(size: 24))
                            Text(term.name)
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        }
                        .foregroundColor(selectedTerm == term.name ? DesignSystem.Colors.primary : DesignSystem.Colors.textMain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(selectedTerm == term.name ? DesignSystem.Colors.primary.opacity(0.05) : Color.white)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedTerm == term.name ? DesignSystem.Colors.primary : Color(hex: "e2e8f0"), lineWidth: selectedTerm == term.name ? 2 : 1)
                        )
                    }
                }
            }
        }
    }
    
    var yearSelection: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("YEAR")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .tracking(1)
            
            TextField("2025", text: $selectedYear)
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(16)
                .background(Color(hex: "f8fafc"))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
    
    var createButton: some View {
        Button(action: {
            // Action to create semester
            guard let year = Int(selectedYear) else {
                notifications.post(
                    kind: .warning,
                    title: "Invalid Year",
                    message: "Enter a valid year (e.g., 2026).",
                    isDismissible: true,
                    autoDismissAfter: 4
                )
                return
            }
            let semesterName = "\(selectedTerm) \(selectedYear)"
            _ = coreDataManager.addSemester(to: plan, name: semesterName, year: year, season: selectedTerm)

            notifications.post(
                kind: .success,
                title: "Semester Added",
                message: "Created \(semesterName).",
                isDismissible: true,
                autoDismissAfter: 3
            )
            isPresented = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                Text("Create Semester")
            }
            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(16)
            .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .padding(.top, 8)
    }
}
