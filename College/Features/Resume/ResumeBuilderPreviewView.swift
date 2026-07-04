// ResumeBuilderPreviewView.swift
// Feature: Resume
// Purpose: PDF preview with reload guard and overlay chips.

import CryptoKit
import PDFKit
import SwiftUI

struct ResumeBuilderPreviewView: View {
    let pdfData: Data?
    let isCompiling: Bool
    let usingFallback: Bool
    let emptySectionWarnings: [ResumeSectionKind]
    let compileError: String?

    @State private var displayedDocument: PDFDocument?
    @State private var lastPDFDataHash: String?

    var body: some View {
        Group {
            if let displayedDocument {
                GeometryReader { proxy in
                    let horizontalInset: CGFloat = 24
                    let pageWidth = max(0, proxy.size.width - horizontalInset * 2)
                    ScrollView(.vertical) {
                        ResumePreviewPDFHost(document: displayedDocument, pageWidth: pageWidth)
                            .frame(maxWidth: .infinity)
                            .padding(horizontalInset)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                ContentUnavailableView(
                    "No preview yet",
                    systemImage: "doc.richtext",
                    description: Text("Add sections to generate a live preview.")
                )
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if usingFallback {
                        previewChip("Preview · compatibility mode", systemImage: "exclamationmark.triangle")
                    }
                    if isCompiling {
                        previewChip("Recompiling…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if let compileError {
                    Text(compileError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(emptySectionWarnings, id: \.self) { kind in
                    Text(kind.emptySectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: pdfData) { _, newData in
            updateDocumentIfNeeded(newData)
        }
        .onAppear {
            updateDocumentIfNeeded(pdfData)
        }
    }

    @ViewBuilder
    private func previewChip(_ title: String, systemImage: String) -> some View {
        GlassEffectContainer(spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private func updateDocumentIfNeeded(_ data: Data?) {
        guard let data else { return }
        let hash = Self.sha256(data)
        guard hash != lastPDFDataHash else { return }
        lastPDFDataHash = hash
        displayedDocument = PDFDocument(data: data)
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct ResumePreviewPDFHost: View {
    let document: PDFDocument
    let pageWidth: CGFloat

    /// US Letter aspect ratio (8.5" × 11").
    private let pageAspectRatio: CGFloat = 8.5 / 11.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)

            ResumePreviewPDFRepresentable(document: document)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: pageWidth, height: pageWidth / pageAspectRatio)
    }
}

private struct ResumePreviewPDFRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.backgroundColor = .white
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        view.autoScales = true
        view.scaleFactor = view.scaleFactorForSizeToFit
    }
}
