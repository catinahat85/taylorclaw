import Foundation

/// Persists user-configured MCP server entries to a JSON file in
/// Application Support. MemPalace is *not* stored here — it's managed
/// internally by `AgentSession` and always present.
///
/// The file shape is a plain JSON array so users can hand-edit it if they
/// need to (e.g., fix an env var without booting the app).
actor MCPServerStore {
    static let shared = MCPServerStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cache: [MCPServerConfig] = []
    private var loaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("TaylorClaw", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mcp_servers.json", isDirectory: false)
    }

    func all() throws -> [MCPServerConfig] {
        try ensureLoaded()
        return cache
    }

    /// Insert or replace by `name` (which doubles as the identity).
    func upsert(_ config: MCPServerConfig) throws {
        try ensureLoaded()
        if let idx = cache.firstIndex(where: { $0.name == config.name }) {
            cache[idx] = config
        } else {
            cache.append(config)
        }
        try persist()
    }

    func delete(name: String) throws {
        try ensureLoaded()
        cache.removeAll { $0.name == name }
        try persist()
    }

    /// Rename an entry in place. Returns false when `oldName` is missing
    /// or `newName` collides with another entry.
    func rename(oldName: String, to newName: String) throws -> Bool {
        try ensureLoaded()
        guard oldName != newName else { return true }
        guard !cache.contains(where: { $0.name == newName }) else { return false }
        guard let idx = cache.firstIndex(where: { $0.name == oldName }) else { return false }
        let existing = cache[idx]
        cache[idx] = MCPServerConfig(
            name: newName,
            command: existing.command,
            args: existing.args,
            env: existing.env,
            cwd: existing.cwd,
            autoStart: existing.autoStart,
            writeFraming: existing.writeFraming
        )
        try persist()
        return true
    }

    // MARK: - Private

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
        let decoded = try decoder.decode([MCPServerConfig].self, from: data)
        cache = decoded.map { cfg in
            // Migration: @brave/brave-search-mcp-server uses the official MCP
            // TypeScript SDK which speaks Content-Length framing on stdio.
            // Earlier builds incorrectly stored `.ndjson` for this server;
            // force it back to `.contentLength` regardless of what was saved.
            if cfg.args.contains("@brave/brave-search-mcp-server"),
               cfg.writeFraming != .contentLength {
                return MCPServerConfig(
                    name: cfg.name,
                    command: cfg.command,
                    args: cfg.args,
                    env: cfg.env,
                    cwd: cfg.cwd,
                    autoStart: cfg.autoStart,
                    writeFraming: .contentLength
                )
            }
            return cfg
        }
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
