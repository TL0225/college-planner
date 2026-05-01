import Foundation
import SwiftUI

struct OverviewDeepCatalogPrompt: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.secondary)
            Text("Catalog intelligence is available in Settings > Resources.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
