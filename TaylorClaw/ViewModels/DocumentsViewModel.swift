import Foundation
import Observation

/// Owns the list of ingested documents and drives the ingest workflow.
///
/// Files added through this view model are read, chunked, and (when
/// MemPalace is running) uploaded to the RAG backend. The Swift-side
/// `DocumentStore` always gets a metadata record so the UI can show the
/// document — even before MemPalace is installed.
@MainActor
@Observable
final class DocumentsViewModel {
    var documents: [Document] = []
    var errorMessage: String?
    var isAdding: Bool = false

    private let store: DocumentStore
    private let memPalace: MemPalaceServer

    init(
        store: DocumentStore = .shared,
        memPalace: MemPalaceServer = .shared
    ) {
        self.store = store
        self.memPalace = memPalace
    }

    func reload() async {
        do {
            documents = try await store.all()
        } catch {
            errorMessage = error.localizedDescription
            documents = []
        }
    }

    /// Ingest one or more URLs sequentially. Reloads after each so the UI
    /// reflects status as it advances.
    func add(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }

        let uploader = await memPalace.documentUploader()
        let ingestor = DocumentIngestor(uploader: uploader)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await ingestor.ingest(url: url)
            } catch {
                errorMessage = "\(url.lastPathComponent): \(error)"
            }
            await reload()
        }
    }

    func delete(id: UUID) async {
        do {
            try await store.delete(id: id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
