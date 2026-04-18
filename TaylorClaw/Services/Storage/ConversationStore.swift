import Foundation

actor ConversationStore {
    static let shared = ConversationStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cache: [Conversation] = []
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("TaylorClaw", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json", isDirectory: false)
    }

    func all() throws -> [Conversation] {
        try ensureLoaded()
        return cache.sorted { $0.updatedAt > $1.updatedAt }
    }

    func upsert(_ conversation: Conversation) throws {
        try ensureLoaded()
        var updated = conversation
        updated.updatedAt = Date()
        if let idx = cache.firstIndex(where: { $0.id == conversation.id }) {
            cache[idx] = updated
        } else {
            cache.append(updated)
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
        cache = try decoder.decode([Conversation].self, from: data)
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
