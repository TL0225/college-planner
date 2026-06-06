// CareerToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct CareerToolbarContent: ToolbarContent {
    let activePage: AppPage
    @FocusedValue(\.activePage) private var focusedActivePage
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(AppContainer.self) private var appContainer

    private var careerScene: CareerSceneState { appContainer.careerScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    private var careerPageIsActive: Bool {
        (focusedActivePage ?? activePage) == .career
    }

    private var subviewBinding: Binding<CareerSubView> {
        Binding(
            get: { careerScene.selectedView },
            set: { careerScene.select($0) }
        )
    }

    var body: some ToolbarContent {
        ToolbarItem(id: "career.subviews", placement: .principal) {
            GlassToolbarGroup {
                Picker("Career Views", selection: subviewBinding) {
                    Text("Board").tag(CareerSubView.board)
                    Text("Openings").tag(CareerSubView.openings)
                    Text("Stats").tag(CareerSubView.stats)
                    Text("Resumes").tag(CareerSubView.resumes)
                    Text("Stories").tag(CareerSubView.stories)
                    Text("Networking").tag(CareerSubView.networking)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                .fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if careerScene.selectedView == .board {
                CareerBoardLayoutMenu(
                    layout: careerScene.boardLayout,
                    onSelect: { careerScene.setBoardLayout($0) }
                )
                StaticToolbarGlassButton(
                    symbol: "doc.on.doc",
                    tip: "Copy board as Markdown table",
                    accessibilityIdentifier: "toolbar.career.copyMarkdown"
                ) {
                    toolbarDispatcher.dispatch(.career(.copyBoardMarkdown))
                }
            }
            StaticToolbarGlassButton(
                symbol: "plus",
                tip: "Add application",
                accessibilityIdentifier: "toolbar.career.add",
                action: {
                    toolbarDispatcher.dispatch(.career(.addApplication))
                },
                isEnabled: careerPageIsActive
            )
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}
