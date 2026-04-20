import Foundation

/// Append-only record of every tool call the agent attempts.
///
/// Lines are JSON-encoded `AuditEntry` values, one per line (JSONL format),
/// stored in `~/Library/Application Support/TaylorClaw/audit.jsonl`.
/// Pass `fileURL: nil` for an in-memory log (used in tests).
actor AuditLog {
    static let shared = AuditLog(fileURL: AuditLog.defaultURL())

    let fileURL: URL?
    private var entries: [AuditEntry] = []
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL?) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        var cache: [AuditEntry] = []
        defer { self.entries = cache }
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            if let lineData = line.data(using: .utf8),
               let entry = try? dec.decode(AuditEntry.self, from: lineData) {
                cache.append(entry)
            }
        }
    }

    static func defaultURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaylorClaw", isDirectory: true)
        return dir.appendingPathComponent("audit.jsonl")
    }

    // MARK: - Public API

    func append(_ entry: AuditEntry) {
        entries.append(entry)
        writeAppend(entry)
    }

    func recent(limit: Int = 100) -> [AuditEntry] {
        Array(entries.suffix(limit))
    }

    func all() -> [AuditEntry] { entries }

    func clear() {
        entries.removeAll()
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Disk

    private func writeAppend(_ entry: AuditEntry) {
        guard let url = fileURL,
              let data = try? encoder.encode(entry) else { return }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var line = data
        line.append(0x0A)   // newline
        if fm.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            }
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }
}

/// A single entry in the audit log.
struct AuditEntry: Codable, Sendable, Hashable {
    enum Outcome: String, Codable, Sendable, Hashable {
        case autoApproved       // policy said safe
        case sessionApproved    // user previously said "allow for session"
        case userApproved       // user just approved this call
        case userDenied         // user rejected this call
        case blocked            // policy says never allow
        case loopLimit          // tripped per-tool call limit
        case toolSuccess        // tool ran, returned ok
        case toolError          // tool ran, returned error
    }

    let timestamp: Date
    let toolName: String
    let serverName: String
    let risk: ToolRisk
    let outcome: Outcome
    let arguments: JSONValue?
    let error: String?

    init(
        timestamp: Date = Date(),
        toolName: String,
        serverName: String,
        risk: ToolRisk,
        outcome: Outcome,
        arguments: JSONValue? = nil,
        error: String? = nil
    ) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.serverName = serverName
        self.risk = risk
        self.outcome = outcome
        self.arguments = arguments
        self.error = error
    }
}
