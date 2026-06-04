// CourseCatalogManagerView.swift
// Feature: Courses
// Purpose: Courses module — CourseCatalogManagerView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import SwiftData

struct CourseCatalogManagerView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var universities: [University] = []

    var body: some View {
        VStack(spacing: 0) {
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
        .onAppear { loadUniversities() }
    }

    private func loadUniversities() {
        guard let repo = collegePersistence.catalogRepository else {
            universities = []
            return
        }
        universities = (try? repo.fetchUniversities()) ?? []
    }
}

struct UniversityCard: View {
    let university: University

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "building.columns.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(university.name)
                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                if let short = university.shortName, !short.isEmpty {
                    Text(short)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
