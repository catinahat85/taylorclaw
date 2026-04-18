import Foundation

/// A file the user has added to Taylor Claw's knowledge base.
///
/// Chunks and embeddings live on the MemPalace side in ChromaDB; this
/// record only tracks the Swift-side metadata we need to list, re-ingest,
/// or remove a document.
struct Document: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var externalID: String?
    var sourceURL: URL?
    var filename: String
    var fileSize: Int64
    var kind: DocumentKind
    var addedAt: Date
    var chunkCount: Int
    var status: IngestStatus
    var errorMessage: String?
    var contentHash: String?

    init(
        id: UUID = UUID(),
        externalID: String? = nil,
        sourceURL: URL? = nil,
        filename: String,
        fileSize: Int64 = 0,
        kind: DocumentKind,
        addedAt: Date = Date(),
        chunkCount: Int = 0,
        status: IngestStatus = .pending,
        errorMessage: String? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.sourceURL = sourceURL
        self.filename = filename
        self.fileSize = fileSize
        self.kind = kind
        self.addedAt = addedAt
        self.chunkCount = chunkCount
        self.status = status
        self.errorMessage = errorMessage
        self.contentHash = contentHash
    }
}

/// Supported source formats. Unknown formats are refused before ingest.
enum DocumentKind: String, Codable, Sendable, Hashable, CaseIterable {
    case text
    case markdown
    case pdf
    case code
    case html
    case rtf
    case json
    case unknown

    /// Detect kind from a URL's path extension. Case-insensitive.
    static func from(url: URL) -> DocumentKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "log":
            return .text
        case "md", "markdown":
            return .markdown
        case "pdf":
            return .pdf
        case "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "c", "cpp",
             "h", "hpp", "java", "rb", "sh", "bash", "zsh", "kt", "scala",
             "php", "cs", "m", "mm":
            return .code
        case "html", "htm", "xhtml":
            return .html
        case "rtf":
            return .rtf
        case "json", "yaml", "yml", "toml":
            return .json
        default:
            return .unknown
        }
    }

    var isReadable: Bool { self != .unknown }
}

/// Where a document is in its ingest lifecycle.
enum IngestStatus: String, Codable, Sendable, Hashable {
    case pending       // queued, not started
    case ingesting     // chunking + uploading
    case ingested      // embeddings stored in MemPalace
    case failed        // see Document.errorMessage
    case stale         // source file changed since last ingest
}
