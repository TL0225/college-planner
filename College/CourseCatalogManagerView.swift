import SwiftUI

struct CourseCatalogManagerView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @State private var universityName: String = ""
    @State private var isImporting: Bool = false
    @State private var apiKey: String = ""
    @State private var universities: [UniversityEntity] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Course Catalog Manager", systemImage: "books.vertical.fill")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(hex: "f1f5f9")),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // API Configuration Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("AI API Configuration")
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Claude API Key")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            SecureField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .padding(12)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                            
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.Colors.info)
                                Text("Get your API key from console.anthropic.com")
                                    .font(DesignSystem.Fonts.main(size: 11))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "f8f9fa"))
                    .cornerRadius(16)
                    
                    // Import New University Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("Import University Catalog")
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter any university name and the system will automatically discover and import their course catalog.")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            HStack(spacing: 12) {
                                TextField("e.g., Stanford University", text: $universityName)
                                    .textFieldStyle(.plain)
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .padding(12)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                    )
                                    .disabled(isImporting)
                                
                                Button(action: importCatalog) {
                                    HStack(spacing: 8) {
                                        if isImporting {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .frame(width: 16, height: 16)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                        }
                                        Text(isImporting ? "Importing..." : "Import")
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        isImporting || universityName.isEmpty || apiKey.isEmpty
                                        ? DesignSystem.Colors.primary.opacity(0.5)
                                        : DesignSystem.Colors.primary
                                    )
                                    .cornerRadius(8)
                                }
                                .disabled(isImporting || universityName.isEmpty || apiKey.isEmpty)
                            }
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
                    
                    // Imported Universities List
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle.fill")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text("Imported Universities")
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Spacer()
                            Text("\(universities.count)")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        
                        if universities.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 48))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text("No universities imported yet")
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text("Import your university to enable course search and degree validation")
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(universities, id: \.id) { university in
                                    UniversityCard(university: university)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(hex: "f8f9fa"))
                    .cornerRadius(16)
                    
                    // How It Works Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(DesignSystem.Colors.warning)
                            Text("How It Works")
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            FeatureRow(
                                icon: "1.circle.fill",
                                title: "AI Discovery",
                                description: "System uses AI to find your university's course catalog automatically"
                            )
                            FeatureRow(
                                icon: "2.circle.fill",
                                title: "Smart Parsing",
                                description: "AI extracts courses, prerequisites, and degree requirements from any format"
                            )
                            FeatureRow(
                                icon: "3.circle.fill",
                                title: "Local Storage",
                                description: "All data stored locally - works offline, completely private"
                            )
                            FeatureRow(
                                icon: "4.circle.fill",
                                title: "Auto-Complete",
                                description: "When adding courses, search from your university's full catalog"
                            )
                        }
                    }
                    .padding()
                    .background(Color(hex: "fff7ed"))
                    .cornerRadius(16)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fafbfc"))
        .onAppear(perform: loadUniversities)
    }
    
    private func importCatalog() {
        guard !universityName.isEmpty, !apiKey.isEmpty else { return }
        
        isImporting = true
        
        Task {
            do {
                let service = CourseCatalogService(coreDataManager: coreDataManager, apiKey: apiKey)
                
                try await service.importCourseCatalog(universityName: universityName)
                
                await MainActor.run {
                    isImporting = false
                    universityName = ""
                    loadUniversities()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                }
            }
        }
    }
    
    private func loadUniversities() {
        let context = coreDataManager.viewContext
        let fetchRequest: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        universities = (try? context.fetch(fetchRequest)) ?? []
    }
}

struct UniversityCard: View {
    @ObservedObject var university: UniversityEntity
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "building.columns.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.primary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(university.name ?? "Unknown")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                if let lastSync = university.lastCatalogSync {
                    Text("Last synced: \(lastSync, style: .relative) ago")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                
                if let coursesCount = university.courses?.count {
                    Text("\(coursesCount) courses imported")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.success)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.Colors.success)
                .font(.system(size: 24))
        }
        .padding()
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
        )
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text(description)
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
