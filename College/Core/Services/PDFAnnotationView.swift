// PDFAnnotationView.swift
// Feature: Core
// Purpose: Core module — PDFAnnotationView.
// Data: CollegePersistence / repositories when applicable.

// PDFAnnotationView.swift
// Full macOS PDF annotation editor using PDFKit.
// Presents as a sheet from DocumentVaultCard.
// Supports highlights, notes, freehand ink, text boxes, and arrows.
// On save the annotated PDF data is handed back via `onSave`.

import SwiftUI
@preconcurrency import PDFKit
@preconcurrency import AppKit

// MARK: - Annotation tool model

enum PDFAnnotationTool: String, CaseIterable, Identifiable {
    case pointer   = "arrow"
    case highlight = "highlighter"
    case underline = "underline"
    case note      = "note"
    case text      = "text.cursor"
    case ink       = "pencil"
    case arrow     = "arrow.up.right"
    case rectangle = "rectangle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pointer:   return "Select"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .note:      return "Note"
        case .text:      return "Text"
        case .ink:       return "Ink"
        case .arrow:     return "Arrow"
        case .rectangle: return "Box"
        }
    }

    var icon: String { rawValue }
}

// MARK: - Color picker model

private let annotationColors: [(name: String, color: NSColor)] = [
    ("Yellow",  .systemYellow),
    ("Green",   .systemGreen),
    ("Blue",    .systemBlue),
    ("Pink",    .systemPink),
    ("Orange",  .systemOrange),
    ("Red",     .systemRed),
    ("Gray",    .systemGray),
    ("Black",   .black),
]

// MARK: - PDFAnnotationView

struct PDFAnnotationView: View {
    let fileURL: URL
    let documentName: String
    let onSave: (Data) -> Void
    let onDismiss: () -> Void

    @State private var activeTool: PDFAnnotationTool = .pointer
    @State private var activeColor: NSColor = .systemYellow
    @State private var strokeWidth: CGFloat = 2.0
    @State private var fontSize: CGFloat = 12.0
    @State private var pdfDocument: PDFDocument?
    @State private var pdfViewRef: PDFView? = nil
    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var isPasswordLocked: Bool = false
    @State private var passwordInput: String = ""
    @State private var passwordError: String? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var isSaving: Bool = false
    @State private var showPageJump: Bool = false
    @State private var pageJumpText: String = ""

    private let accentPink = Color(hex: "FF1A7F")

    var body: some View {
        VStack(spacing: 0) {
            // ── Top Toolbar ──────────────────────────────────────────────
            annotationToolbar

            Divider()

            if isPasswordLocked {
                passwordPromptView
            } else {
                HStack(spacing: 0) {
                    thumbnailSidebar

                    Divider()

                    PDFViewRepresentable(
                        document: pdfDocument,
                        activeTool: activeTool,
                        activeColor: activeColor,
                        strokeWidth: strokeWidth,
                        fontSize: fontSize,
                        onPageChanged: { page, total in
                            currentPage = page
                            totalPages = total
                        },
                        onSetup: { view in
                            pdfViewRef = view
                        }
                    )
                    .background(Color(hex: "525659"))
                }

                statusBar
            }
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 540, idealHeight: 620)
        .onAppear { loadDocument() }
    }

    // MARK: - Annotation Toolbar
    @ViewBuilder private var annotationToolbar: some View {
        HStack(spacing: 0) {
            // Close
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .frame(width: 32, height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .help("Close without saving")

            Spacer().frame(width: 12)

            // Document name
            Text(documentName)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 240)

            Spacer()

            // Tool picker
            HStack(spacing: 2) {
                ForEach(PDFAnnotationTool.allCases) { tool in
                    Button {
                        activeTool = tool
                    } label: {
                        Image(systemName: tool.icon)
                            .font(DesignSystem.Fonts.main(size: 13))
                            .foregroundStyle(activeTool == tool ? .white : DesignSystem.Colors.textLight)
                            .frame(width: 30, height: 30)
                            .background(activeTool == tool ? accentPink : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(tool.label)
                }
            }
            .padding(DesignSystem.Spacing.xs)
            .background(Color(hex: "f1f5f9"))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)

            // Color picker
            HStack(spacing: 4) {
                ForEach(annotationColors, id: \.name) { item in
                    Button {
                        activeColor = item.color
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(item.color))
                                .frame(width: 20, height: 20)
                            if activeColor == item.color {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
            .padding(.trailing, 12)

            // Stroke width
            HStack(spacing: 4) {
                Image(systemName: "line.diagonal")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                Slider(value: $strokeWidth, in: 1...8, step: 0.5)
                    .frame(width: 70)
                    .help("Stroke width")
            }
            .padding(.trailing, 12)

            // Undo / Redo
            HStack(spacing: 2) {
                Button {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Undo")

                Button {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(DesignSystem.Fonts.main(size: 13))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Redo")
            }
            .padding(DesignSystem.Spacing.xs)
            .background(Color(hex: "f1f5f9"))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.trailing, 12)

            // Save
            Button {
                saveAnnotations()
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "checkmark")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    }
                    Text(isSaving ? "Saving…" : "Save")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accentPink)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.trailing, 14)
        }
        .frame(height: 52)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Thumbnail Sidebar
    @ViewBuilder private var thumbnailSidebar: some View {
        if let doc = pdfDocument {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<doc.pageCount, id: \.self) { index in
                        Button {
                            if let page = doc.page(at: index) {
                                pdfViewRef?.go(to: page)
                                currentPage = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                PDFPageThumbnailView(page: doc.page(at: index))
                                    .frame(width: 76, height: 98)
                                    .background(DesignSystem.Colors.surface)
                                    .clipShape(.rect(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(currentPage == index ? Color(hex: "FF1A7F") : Color(hex: "d1d5db"), lineWidth: currentPage == index ? 2 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.06), radius: 2)
                                Text("\(index + 1)")
                                    .font(DesignSystem.Fonts.main(size: 10))
                                    .foregroundStyle(currentPage == index ? Color(hex: "FF1A7F") : DesignSystem.Colors.textLight)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .frame(width: 100)
            .background(Color(hex: "f8fafc"))
        }
    }

    // MARK: - Status Bar
    @ViewBuilder private var statusBar: some View {
        HStack(spacing: 12) {
            // Zoom
            Button {
                pdfViewRef?.scaleFactor -= 0.25
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)

            Button {
                pdfViewRef?.scaleFactor = 1.0
            } label: {
                Text(String(format: "%.0f%%", (pdfViewRef?.scaleFactor ?? 1.0) * 100))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .frame(width: 44)
            }
            .buttonStyle(.plain)

            Button {
                pdfViewRef?.scaleFactor += 0.25
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)

            Button { pdfViewRef?.autoScales = true } label: {
                Image(systemName: "rectangle.arrowtriangle.2.inward")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)
            .help("Fit to window")

            Spacer()

            // Page navigation
            Button {
                guard let doc = pdfDocument, currentPage > 0,
                      let page = doc.page(at: currentPage - 1) else { return }
                pdfViewRef?.go(to: page)
            } label: {
                Image(systemName: "chevron.left")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)
            .disabled(currentPage <= 0)

            Button { showPageJump.toggle() } label: {
                Text("Page \(currentPage + 1) of \(totalPages)")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPageJump) {
                HStack(spacing: 8) {
                    Text("Go to page:")
                        .font(DesignSystem.Fonts.main(size: 12))
                    TextField("", text: $pageJumpText)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if let n = Int(pageJumpText),
                               let doc = pdfDocument,
                               n >= 1, n <= doc.pageCount,
                               let page = doc.page(at: n - 1) {
                                pdfViewRef?.go(to: page)
                                currentPage = n - 1
                            }
                            showPageJump = false
                            pageJumpText = ""
                        }
                }
                .padding(DesignSystem.Spacing.md)
            }

            Button {
                guard let doc = pdfDocument, currentPage < doc.pageCount - 1,
                      let page = doc.page(at: currentPage + 1) else { return }
                pdfViewRef?.go(to: page)
            } label: {
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .buttonStyle(.plain)
            .disabled(totalPages == 0 || currentPage >= totalPages - 1)

            Spacer()

            // Active tool indicator
            HStack(spacing: 4) {
                Image(systemName: activeTool.icon)
                    .font(DesignSystem.Fonts.main(size: 11))
                Text(activeTool.label)
                    .font(DesignSystem.Fonts.main(size: 11))
            }
            .foregroundStyle(DesignSystem.Colors.textLight)
            .padding(.trailing, 14)
        }
        .frame(height: 34)
        .padding(.horizontal, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(hex: "e2e8f0")), alignment: .top)
    }

    // MARK: - Password Prompt
    @ViewBuilder private var passwordPromptView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.doc.fill")
                .font(DesignSystem.Fonts.main(size: 48))
                .foregroundStyle(Color(hex: "FF1A7F"))
            Text("This PDF is password protected")
                .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
            SecureField("Enter PDF password", text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { unlockPDF() }
            if let error = passwordError {
                Text(error)
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
            HStack(spacing: 12) {
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                Button("Unlock") { unlockPDF() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "FF1A7F"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func loadDocument() {
        switch openPDF(at: fileURL) {
        case .open(let doc):
            pdfDocument = doc
            totalPages  = doc.pageCount
        case .locked(let doc):
            pdfDocument    = doc
            isPasswordLocked = true
        case .failed:
            onDismiss()
        }
    }

    private func unlockPDF() {
        guard let doc = pdfDocument else { return }
        if doc.unlock(withPassword: passwordInput) {
            isPasswordLocked = false
            totalPages        = doc.pageCount
            passwordError     = nil
        } else {
            passwordError = "Incorrect password. Please try again."
        }
    }

    private func saveAnnotations() {
        guard let doc = pdfDocument else { return }
        isSaving = true
        let data = doc.dataRepresentation()
        isSaving = false
        if let data {
            onSave(data)
        } else {
            onDismiss()
        }
    }
}

// MARK: - NSViewRepresentable: PDFView

struct PDFViewRepresentable: NSViewRepresentable {
    var document: PDFDocument?
    var activeTool: PDFAnnotationTool
    var activeColor: NSColor
    var strokeWidth: CGFloat
    var fontSize: CGFloat
    var onPageChanged: (Int, Int) -> Void
    var onSetup: (PDFView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChanged: onPageChanged) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(hex: "525659") ?? .darkGray
        view.document = document

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        context.coordinator.pdfView = view
        onSetup(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        // Keep the coordinator up-to-date with the current tool settings
        context.coordinator.activeTool  = activeTool
        context.coordinator.activeColor = activeColor
        context.coordinator.strokeWidth = strokeWidth
        context.coordinator.fontSize    = fontSize

        // Attach the custom gesture recogniser for annotation drawing
        context.coordinator.configureGestures(on: view)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: nsView
        )
    }

    @MainActor
    class Coordinator: NSObject {
        var pdfView: PDFView?
        var activeTool: PDFAnnotationTool = .pointer
        var activeColor: NSColor = .systemYellow
        var strokeWidth: CGFloat = 2.0
        var fontSize: CGFloat = 12.0
        var onPageChanged: (Int, Int) -> Void

        init(onPageChanged: @escaping (Int, Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let doc  = view.document else { return }
            let index = doc.index(for: page)
            onPageChanged(index, doc.pageCount)
        }

        private var gestureConfigured = false
        func configureGestures(on view: PDFView) {
            guard !gestureConfigured else { return }
            gestureConfigured = true
            let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            click.numberOfClicksRequired = 1
            view.addGestureRecognizer(click)
        }

        @objc func handleClick(_ gesture: NSGestureRecognizer) {
            guard let view = pdfView,
                  let page = view.currentPage else { return }

            let locationInView = gesture.location(in: view)
            let locationInPage = view.convert(locationInView, to: page)

            switch activeTool {
            case .pointer, .ink, .arrow, .rectangle:
                break // handled by PDFKit's default interaction

            case .highlight:
                addHighlight(at: locationInPage, on: page, type: .highlight)

            case .underline:
                addHighlight(at: locationInPage, on: page, type: .underline)

            case .note:
                addNote(at: locationInPage, on: page)

            case .text:
                addTextAnnotation(at: locationInPage, on: page)
            }
        }

        private func addHighlight(at point: CGPoint, on page: PDFPage, type: PDFAnnotationSubtype) {
            let size: CGFloat = 100
            let bounds = CGRect(x: point.x - size / 2, y: point.y - 8, width: size, height: 16)
            let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            annotation.color = activeColor.withAlphaComponent(0.5)
            page.addAnnotation(annotation)
        }

        private func addNote(at point: CGPoint, on page: PDFPage) {
            let bounds = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
            annotation.color = activeColor
            annotation.contents = "Note"
            page.addAnnotation(annotation)
        }

        private func addTextAnnotation(at point: CGPoint, on page: PDFPage) {
            let bounds = CGRect(x: point.x - 50, y: point.y - 10, width: 140, height: 24)
            let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            annotation.font  = NSFont.systemFont(ofSize: fontSize)
            annotation.color = .white
            annotation.fontColor = activeColor
            annotation.contents  = "Text"
            page.addAnnotation(annotation)
        }
    }
}

// MARK: - PDFPageThumbnailView

private struct PDFPageThumbnailView: NSViewRepresentable {
    let page: PDFPage?

    @MainActor
    final class Coordinator {
        let pdfView: PDFView

        init() {
            self.pdfView = PDFView()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = context.coordinator.pdfView
        return view
    }
    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        // PDFThumbnailView gets its content from its associated PDFView.
        // We manually render the page as an NSImage for preview instead.
    }
}

// MARK: - NSColor hex convenience

private extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        guard hex.count == 6 else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >>  8) & 0xFF) / 255
        let b = CGFloat(        int & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
