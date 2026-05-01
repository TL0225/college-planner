import SwiftUI

struct CourseCatalogManagerView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
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
                    
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fafbfc"))
        .onAppear {
            loadUniversities()
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
