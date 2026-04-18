import SwiftUI
import UniformTypeIdentifiers

struct DocumentsSettingsView: View {
    @Bindable var viewModel: DocumentsViewModel
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            list
            footer
        }
        .padding(16)
        .task { await viewModel.reload() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.add(urls: urls) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Documents")
                    .font(.title3.weight(.semibold))
                Text("Files you add here are chunked and embedded in MemPalace. In Agent mode, relevant chunks are pulled into the system prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                showImporter = true
            } label: {
                Label("Add files…", systemImage: "plus")
            }
            .disabled(viewModel.isAdding)
        }
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.documents.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No documents yet")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(viewModel.documents) { doc in
                    DocumentRow(document: doc) {
                        Task { await viewModel.delete(id: doc.id) }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let msg = viewModel.errorMessage {
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
        if viewModel.isAdding {
            ProgressView().controlSize(.small)
        }
    }

    private static let allowedTypes: [UTType] = [
        .plainText, .text, .pdf, .rtf, .html,
        .json, .yaml, .sourceCode, .swiftSource,
    ]
}

private struct DocumentRow: View {
    let document: Document
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(document.filename)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(statusText)
                    if document.chunkCount > 0 {
                        Text("· \(document.chunkCount) chunks")
                    }
                    if document.fileSize > 0 {
                        Text("· \(formattedSize)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let err = document.errorMessage, document.status == .failed {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch document.kind {
        case .pdf: "doc.richtext"
        case .markdown, .text: "doc.plaintext"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .html: "globe"
        case .rtf: "doc.text"
        case .json: "curlybraces"
        case .unknown: "doc"
        }
    }

    private var statusText: String {
        switch document.status {
        case .pending: "Queued"
        case .ingesting: "Ingesting…"
        case .ingested: "Ready"
        case .failed: "Failed"
        case .stale: "Stale"
        }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file)
    }
}
