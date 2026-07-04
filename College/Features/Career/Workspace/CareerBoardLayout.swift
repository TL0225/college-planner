import SwiftUI
import CollegeCareer

struct CareerBoardLayoutMenu: View {
    let layout: CareerBoardLayout
    let onSelect: (CareerBoardLayout) -> Void

    var body: some View {
        Menu {
            ForEach(CareerBoardLayout.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    if layout == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.primary)
        }
        .help("Board layout")
        .accessibilityLabel("Board layout")
    }
}
