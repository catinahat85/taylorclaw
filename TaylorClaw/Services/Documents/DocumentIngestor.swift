import Foundation
import CryptoKit

/// Uploads documents to the RAG backend (MemPalace) and tracks metadata.
///
/// For each ingest:
///   1. Read file → plain text (via `DocumentReader`).
///   2. SHA-256 hash the text; skip if a matching document already exists.
///   3. Chunk (via `DocumentChunker`).
///   4. Call the configured MCP tool per chunk (default `add_document`).
///   5. Persist a `Document` record with status / chunk count.
///
/// Pass `client: nil` (or a no-op) to ingest locally without uploading —
/// tests exercise the chunking + store paths without an MCP server.
actor DocumentIngestor {
    private let chunker: DocumentChunker
    private let store: DocumentStore
    private let uploader: (any DocumentUploader)?
    private let reader: DocumentReading

    init(
        chunker: DocumentChunker = DocumentChunker(),
        store: DocumentStore = .shared,
        uploader: (any DocumentUploader)? = nil,
        reader: DocumentReading = FileReader()
    ) {
        self.chunker = chunker
        self.store = store
        self.uploader = uploader
        self.reader = reader
    }

    /// Ingest a file at `url`. Returns the resulting (possibly failed)
    /// `Document` record. Persists status updates to the store as it
    /// progresses.
    @discardableResult
    func ingest(url: URL) async throws -> Document {
        let kind = DocumentKind.from(url: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        var doc = Document(
            sourceURL: url,
            filename: url.lastPathComponent,
            fileSize: Int64(size),
            kind: kind,
            status: .pending
        )

        guard kind.isReadable else {
            doc.status = .failed
            doc.errorMessage = "Unsupported file type: .\(url.pathExtension)"
            try await store.upsert(doc)
            throw DocumentReaderError.unsupportedKind(url.pathExtension)
        }

        doc.status = .ingesting
        try await store.upsert(doc)

        do {
            let text = try await reader.readText(from: url)
            let hash = Self.sha256(text)
            doc.contentHash = hash

            if let existing = try await store.findByHash(hash), existing.id != doc.id {
                doc.status = .ingested
                doc.externalID = existing.externalID
                doc.chunkCount = existing.chunkCount
                try await store.upsert(doc)
                return doc
            }

            let chunks = chunker.chunk(text)
            doc.chunkCount = chunks.count

            if let uploader {
                let externalID = try await uploader.upload(
                    chunks: chunks,
                    title: url.lastPathComponent,
                    metadata: [
                        "filename": url.lastPathComponent,
                        "kind": kind.rawValue,
                        "contentHash": hash,
                    ]
                )
                doc.externalID = externalID
            }

            doc.status = .ingested
            try await store.upsert(doc)
            return doc
        } catch {
            doc.status = .failed
            doc.errorMessage = "\(error)"
            try await store.upsert(doc)
            throw error
        }
    }

    // MARK: - Helpers

    static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Protocols (injectable for tests)

/// Reads a file's text content.
protocol DocumentReading: Sendable {
    func readText(from url: URL) async throws -> String
}

/// Default reader — wraps `DocumentReader` for injection into the ingestor.
struct FileReader: DocumentReading {
    func readText(from url: URL) async throws -> String {
        try await DocumentReader.readText(from: url)
    }
}

/// Uploads chunks to a RAG backend. Returns the external document ID.
protocol DocumentUploader: Sendable {
    func upload(
        chunks: [String],
        title: String,
        metadata: [String: String]
    ) async throws -> String
}

/// MemPalace-flavored uploader. Calls `add_document` per chunk (MemPalace
/// groups them by the `document_id` metadata key), returning the
/// generated ID so the store can link back.
actor MCPDocumentUploader: DocumentUploader {
    private let client: MCPClient
    private let toolName: String

    init(client: MCPClient, toolName: String = "add_document") {
        self.client = client
        self.toolName = toolName
    }

    func upload(
        chunks: [String],
        title: String,
        metadata: [String: String]
    ) async throws -> String {
        let documentID = UUID().uuidString
        var meta = metadata
        meta["document_id"] = documentID
        meta["title"] = title

        for (idx, chunk) in chunks.enumerated() {
            var chunkMeta = meta
            chunkMeta["chunk_index"] = String(idx)
            let args: JSONValue = .object([
                "content": .string(chunk),
                "metadata": .object(chunkMeta.mapValues { JSONValue.string($0) }),
            ])
            let result = try await client.callTool(name: toolName, arguments: args)
            if result.isError == true {
                let msg = result.content.first?.text ?? "upload failed"
                throw DocumentIngestError.uploadFailed(chunk: idx, message: msg)
            }
        }
        return documentID
    }
}

enum DocumentIngestError: Error, Sendable, Equatable, CustomStringConvertible {
    case uploadFailed(chunk: Int, message: String)

    var description: String {
        switch self {
        case .uploadFailed(let i, let m): "chunk \(i) upload failed: \(m)"
        }
    }
}
