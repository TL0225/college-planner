import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private var hostingController: NSHostingController<ShareRootView>?

    override func loadView() {
        let root = ShareRootView(
            onCancel: { [weak self] in self?.finish() },
            onSave: { [weak self] request in self?.handleSave(request) }
        )
        let host = NSHostingController(rootView: root)
        self.hostingController = host
        self.view = host.view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor in
            let payload = await extractPayload()
            hostingController?.rootView.prefill(payload)
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Save to College"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        finish()
    }

    private func handleSave(_ request: CareerSaveRequest) {
        Task { @MainActor in
            do {
                try await CareerIngestCoordinator.shared.writeSaveRequest(request)
                finish()
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func extractPayload() async -> CareerSaveRequest {
        let fallback = CareerSaveRequest(
            requestId: UUID(),
            company: "",
            title: "",
            baseSalary: "",
            location: "",
            keywords: [],
            jobDescription: "",
            postingURL: "",
            applicationDeadline: Date()
        )
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else { return fallback }

        if let pdfRequestId = await extractSharedResumePDF(from: item) {
            if let openURL = URL(string: "college://resume/import?requestId=\(pdfRequestId.uuidString)") {
                NSWorkspace.shared.open(openURL)
            }
            finish()
            return fallback
        }

        var urlText = ""
        var bodyText = ""

        if let attachments = item.attachments {
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    urlText = url.absoluteString
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                    bodyText = text
                }
            }
        }

        let payload = CareerIngestPayload(
            requestId: UUID(),
            sourceURL: urlText,
            rawText: bodyText,
            createdAt: Date()
        )
        do {
            let written = try CareerIngestCoordinator.shared.writeIngestPayload(
                url: URL(string: payload.sourceURL) ?? URL(string: "about:blank")!,
                text: payload.rawText,
                requestId: payload.requestId
            )
            if let openURL = URL(string: "college://ingest?requestId=\(written.requestId.uuidString)") {
                NSWorkspace.shared.open(openURL)
            }
        } catch {
            presentError(error.localizedDescription)
            return fallback
        }
        if let parsed = await CareerIngestCoordinator.shared.readParseResult() {
            return CareerSaveRequest(
                requestId: parsed.requestId,
                company: parsed.company,
                title: parsed.title,
                baseSalary: parsed.baseSalary,
                location: parsed.location,
                keywords: parsed.keywords,
                jobDescription: parsed.jobDescription,
                postingURL: payload.sourceURL,
                applicationDeadline: Date()
            )
        }
        return fallback
    }

    @MainActor
    private func extractSharedResumePDF(from item: NSExtensionItem) async -> UUID? {
        guard let attachments = item.attachments else { return nil }
        for provider in attachments {
            guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) else { continue }
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                return try? CareerIngestCoordinator.shared.writeSharedResumeImport(
                    data: data,
                    fileName: url.lastPathComponent
                )
            }
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? Data {
                return try? CareerIngestCoordinator.shared.writeSharedResumeImport(
                    data: data,
                    fileName: "Shared-Resume.pdf"
                )
            }
        }
        return nil
    }
}

private struct ShareRootView: View {
    @State private var request: CareerSaveRequest
    @State private var isExtracting = true

    let onCancel: () -> Void
    let onSave: (CareerSaveRequest) -> Void

    init(onCancel: @escaping () -> Void, onSave: @escaping (CareerSaveRequest) -> Void) {
        self.onCancel = onCancel
        self.onSave = onSave
        _request = State(initialValue: CareerSaveRequest(
            requestId: UUID(),
            company: "",
            title: "",
            baseSalary: "",
            location: "",
            keywords: [],
            jobDescription: "",
            postingURL: "",
            applicationDeadline: Date()
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isExtracting {
                ProgressView("Extracting Job Details…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Job Title", text: binding(\.title))
                TextField("Company", text: binding(\.company))
                TextField("Location", text: binding(\.location))
                TextField("Base Salary", text: binding(\.baseSalary))
                DatePicker("Application Deadline", selection: binding(\.applicationDeadline), displayedComponents: .date)
                TextEditor(text: binding(\.jobDescription))
                    .frame(minHeight: 100)
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Save to Tracker") {
                        onSave(request)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }

    func prefill(_ value: CareerSaveRequest) {
        request = value
        isExtracting = false
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CareerSaveRequest, T>) -> Binding<T> {
        Binding(
            get: { request[keyPath: keyPath] },
            set: { request[keyPath: keyPath] = $0 }
        )
    }
}
