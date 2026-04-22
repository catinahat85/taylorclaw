import AppKit
import Foundation
import Observation

/// Gathers state from every long-lived actor (stores, keychain, MemPalace,
/// audit log) and renders it as a copy-pasteable report. Used by the
/// Diagnostics settings tab so bug reports carry ground truth.
@MainActor
@Observable
final class DiagnosticsViewModel {
    struct KeyStatus: Identifiable, Hashable {
        let provider: ProviderID
        let hasKey: Bool
        var id: ProviderID { provider }
    }

    struct Snapshot {
        var appVersion: String = "?"
        var buildNumber: String = "?"
        var bundleID: String = "?"
        var appSupportPath: String = ""
        var conversationsPath: String = ""
        var documentsPath: String = ""
        var auditLogPath: String = ""
        var mempalaceLogPath: String = ""
        var runtimeInstalled: Bool = false
        var venvPythonPath: String = ""
        var mempalaceRunning: Bool = false
        var toolCount: Int = 0
        var toolNames: [String] = []
        var keyStatus: [KeyStatus] = []
        var conversationCount: Int = 0
        var documentCount: Int = 0
        var recentAudit: [AuditEntry] = []
        var mempalaceStderr: [String] = []
        var defaultModel: String = ""
        var defaultChatMode: String = ""
        var lastError: String?
    }

    var snapshot = Snapshot()
    var isRefreshing = false
    var didCopy = false

    private let keychain: KeychainStore
    private let memPalace: MemPalaceServer
    private let conversationStore: ConversationStore
    private let documentStore: DocumentStore
    private let auditLog: AuditLog
    private let preferences: Preferences

    init(
        keychain: KeychainStore = .shared,
        memPalace: MemPalaceServer = .shared,
        conversationStore: ConversationStore = .shared,
        documentStore: DocumentStore = .shared,
        auditLog: AuditLog = .shared,
        preferences: Preferences = .shared
    ) {
        self.keychain = keychain
        self.memPalace = memPalace
        self.conversationStore = conversationStore
        self.documentStore = documentStore
        self.auditLog = auditLog
        self.preferences = preferences
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var snap = Snapshot()

        let info = Bundle.main.infoDictionary ?? [:]
        snap.appVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        snap.buildNumber = info["CFBundleVersion"] as? String ?? "?"
        snap.bundleID = Bundle.main.bundleIdentifier ?? "?"

        snap.appSupportPath = RuntimeConstants.appSupport.path
        snap.conversationsPath = RuntimeConstants.appSupport
            .appendingPathComponent("conversations.json").path
        snap.documentsPath = RuntimeConstants.appSupport
            .appendingPathComponent("documents.json").path
        snap.auditLogPath = AuditLog.defaultURL().path
        snap.mempalaceLogPath = RuntimeConstants.appSupport
            .appendingPathComponent("mcp-mempalace.log").path
        snap.venvPythonPath = RuntimeConstants.venvPython.path
        snap.runtimeInstalled = FileManager.default.fileExists(atPath: snap.venvPythonPath)

        snap.mempalaceRunning = await memPalace.isRunning
        let tools = await memPalace.listTools()
        snap.toolCount = tools.count
        snap.toolNames = tools.map(\.name).sorted()
        if let client = await memPalace.mcpClient() {
            let stderr = await client.stderrSnapshot()
            snap.mempalaceStderr = Array(stderr.suffix(25))
        } else {
            snap.mempalaceStderr = []
        }

        var keys: [KeyStatus] = []
        for provider in ProviderID.allCases {
            let has = await keychain.hasKey(for: provider)
            keys.append(KeyStatus(provider: provider, hasKey: has))
        }
        snap.keyStatus = keys

        do {
            snap.conversationCount = try await conversationStore.all().count
        } catch {
            snap.lastError = "Conversations: \(error.localizedDescription)"
        }

        do {
            snap.documentCount = try await documentStore.all().count
        } catch {
            snap.lastError = (snap.lastError.map { $0 + " | " } ?? "")
                + "Documents: \(error.localizedDescription)"
        }

        snap.recentAudit = await auditLog.recent(limit: 50).reversed()

        let model = preferences.defaultModel
        snap.defaultModel = "\(model.provider.displayName) · \(model.displayName) (\(model.id))"
        snap.defaultChatMode = preferences.defaultChatMode.displayName

        self.snapshot = snap
    }

    func copyReport() {
        let text = plainTextReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }

    func plainTextReport() -> String {
        let s = snapshot
        var lines: [String] = []
        lines.append("=== TaylorClaw Diagnostics ===")
        lines.append("Generated: \(Self.iso8601(Date()))")
        lines.append("")
        lines.append("## App")
        lines.append("version: \(s.appVersion) (build \(s.buildNumber))")
        lines.append("bundleID: \(s.bundleID)")
        lines.append("defaultModel: \(s.defaultModel)")
        lines.append("defaultChatMode: \(s.defaultChatMode)")
        lines.append("")
        lines.append("## Paths")
        lines.append("appSupport: \(s.appSupportPath)")
        lines.append("conversations: \(s.conversationsPath)")
        lines.append("documents: \(s.documentsPath)")
        lines.append("audit: \(s.auditLogPath)")
        lines.append("mempalaceLog: \(s.mempalaceLogPath)")
        lines.append("venvPython: \(s.venvPythonPath)")
        lines.append("")
        lines.append("## Runtime")
        lines.append("runtimeInstalled: \(s.runtimeInstalled)")
        lines.append("mempalaceRunning: \(s.mempalaceRunning)")
        lines.append("toolCount: \(s.toolCount)")
        if !s.toolNames.isEmpty {
            lines.append("tools: \(s.toolNames.joined(separator: ", "))")
        }
        if !s.mempalaceStderr.isEmpty {
            lines.append("recentStderr:")
            for line in s.mempalaceStderr {
                lines.append("  \(line)")
            }
        }
        lines.append("")
        lines.append("## API Keys")
        for status in s.keyStatus {
            lines.append("\(status.provider.rawValue): \(status.hasKey ? "present" : "missing")")
        }
        lines.append("")
        lines.append("## Stores")
        lines.append("conversations: \(s.conversationCount)")
        lines.append("documents: \(s.documentCount)")
        lines.append("")
        lines.append("## Recent Audit (up to 50, newest first)")
        if s.recentAudit.isEmpty {
            lines.append("(empty)")
        } else {
            for entry in s.recentAudit {
                let ts = Self.iso8601(entry.timestamp)
                var line = "\(ts)  \(entry.serverName)/\(entry.toolName)"
                    + "  risk=\(entry.risk.rawValue)  outcome=\(entry.outcome.rawValue)"
                if let err = entry.error { line += "  error=\(err)" }
                lines.append(line)
            }
        }
        if let err = s.lastError {
            lines.append("")
            lines.append("## Snapshot Errors")
            lines.append(err)
        }
        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
