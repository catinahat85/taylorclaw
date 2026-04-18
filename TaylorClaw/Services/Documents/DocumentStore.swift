import Foundation

/// Persists `Document` metadata as a single JSON blob in Application Support.
/// Chunks / embeddings live on the MemPalace side — this is just the list
/// Taylor Claw displays in the UI and uses for dedupe.
actor DocumentStore {
    static let shared = DocumentStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cache: [Document] = []
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("TaylorClaw", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("documents.json", isDirectory: false)
    }

    // MARK: - Public API

    func all() throws -> [Document] {
        try ensureLoaded()
        return cache.sorted { $0.addedAt > $1.addedAt }
    }

    func find(id: UUID) throws -> Document? {
        try ensureLoaded()
        return cache.first { $0.id == id }
    }

    func findByHash(_ hash: String) throws -> Document? {
        try ensureLoaded()
        return cache.first { $0.contentHash == hash }
    }

    func upsert(_ document: Document) throws {
        try ensureLoaded()
        if let idx = cache.firstIndex(where: { $0.id == document.id }) {
            cache[idx] = document
        } else {
            cache.append(document)
        }
        try persist()
    }

    func delete(id: UUID) throws {
        try ensureLoaded()
        cache.removeAll { $0.id == id }
        try persist()
    }

    func deleteAll() throws {
        cache.removeAll()
        loaded = true
        try persist()
    }

    // MARK: - Persistence

    private func ensureLoaded() throws {
        guard !loaded else { return }
        defer { loaded = true }
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            cache = []
            return
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            cache = []
            return
        }
        cache = try decoder.decode([Document].self, from: data)
    }

    private func persist() throws {
        let data = try encoder.encode(cache)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: fileURL)
        }
    }
}
