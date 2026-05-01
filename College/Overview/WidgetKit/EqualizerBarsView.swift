//
//  EqualizerBarsView.swift
//  College
//
//  Animated 5-bar EQ visualizer used by the music widget and any
//  other view that needs a "now playing" indicator.
//

import SwiftUI
import Combine

struct EqualizerBarsView: View {
    let isPlaying: Bool

    @State private var heights: [CGFloat] = [0.55, 0.85, 0.40, 1.00, 0.65]

    private let ticker = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: isPlaying ? heights[i] * 20 + 2 : 2)
                    .animation(.easeInOut(duration: 0.18), value: heights[i])
            }
        }
        .frame(width: 25, height: 22)
        .onReceive(ticker) { _ in
            guard isPlaying else { return }
            heights = (0..<5).map { _ in CGFloat.random(in: 0.25...1.0) }
        }
    }
}
