// AutoGrowingTextEditor.swift
// Feature: Core
// Purpose: Core module — AutoGrowingTextEditor.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct AutoGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    var font: NSFont
    var textColor: NSColor
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.delegate = context.coordinator
        textView.string = text

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView

        DispatchQueue.main.async {
            self.remeasure(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != textColor {
            textView.textColor = textColor
        }

        DispatchQueue.main.async {
            self.remeasure(textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func remeasure(_ textView: NSTextView) {
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = ceil(used.height + textView.textContainerInset.height * 2)

        if measuredHeight != height {
            measuredHeight = max(18, height)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: AutoGrowingTextEditor

        init(_ parent: AutoGrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.remeasure(textView)
        }
    }
}
