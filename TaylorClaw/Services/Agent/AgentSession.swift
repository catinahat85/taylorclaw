import Foundation
import Observation

/// App-wide agent runtime: owns the MemPalace MCP client plus any
/// user-configured MCP servers, the approval prompter, and the safety
/// guard. Used by `AgentPanel`, the MCP Servers settings tab, and (in
/// Phase F2) the agent send loop.
///
/// The send path still goes through `ChatViewModel.send()` exactly as in
/// v0.1 — chat behavior is unchanged regardless of mode.
@MainActor
@Observable
final class AgentSession {
    static let shared = AgentSession()
    private static let memPalaceStartupTimeoutSeconds: Double = 420

    enum Status: Sendable, Equatable {
        case stopped
        case starting
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .stopped:           return "Stopped"
            case .starting:          return "Starting MemPalace…"
            case .ready:             return "Ready"
            case .failed(let msg):   return "Failed: \(msg)"
            }
        }
    }

    /// Per-server lifecycle state shown in the MCP Servers settings tab.
    enum ServerState: Sendable, Equatable {
        case stopped
        case starting
        case ready
        case failed(String)
    }

    struct UserServer: Sendable, Equatable, Identifiable {
        let config: MCPServerConfig
        var state: ServerState
        var tools: [MCPTool]
        var id: String { config.name }
    }

    private(set) var status: Status = .stopped
    private(set) var tools: [MCPTool] = []
    /// User-configured servers, surfaced to the settings UI. Keyed insertion
    /// order matches the store's file order.
    private(set) var userServers: [UserServer] = []

    let prompter: UIApprovalPrompter
    let guardActor: AgentGuard

    private var client: MCPClient?
    private var userClients: [String: MCPClient] = [:]
    private var startTask: Task<Void, Never>?

    private let store: MCPServerStore

    private init(store: MCPServerStore = .shared) {
        let prompter = UIApprovalPrompter()
        self.prompter = prompter
        self.guardActor = AgentGuard(prompter: prompter)
        self.store = store
    }

    // MARK: - Lifecycle

    /// Idempotent. Starts MemPalace if the runtime is installed and the
    /// client isn't already running, then fires off user-server starts in
    /// parallel. Re-entrant calls coalesce onto the in-flight start task.
    func ensureStarted() async {
        if case .ready = status {
            await reconcileUserServers()
            return
        }
        if case .starting = status, let task = startTask {
            await task.value
            return
        }
        guard RuntimeManager.shared.isInstalled else {
            status = .failed("Python runtime not installed")
            await reconcileUserServers()
            return
        }

        status = .starting
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startTask = task
        await task.value
        startTask = nil
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        // The MemPalace client is owned by `MemPalaceServer.shared` — don't
        // stop it here, other view models (chat, documents, diagnostics) still
        // depend on it. Just release our reference.
        client = nil
        tools = []
        status = .stopped
        await stopAllUserServers()
    }

    // MARK: - Retrievers

    /// Returns a live MCP-backed retriever when ready, otherwise a no-op.
    var memoryRetriever: any MemoryRetriever {
        if let c = client, case .ready = status {
            return MCPMemoryRetriever(client: c)
        }
        return NoMemoryRetriever()
    }

    var documentRetriever: any DocumentRetriever {
        if let c = client, case .ready = status {
            return MCPDocumentRetriever(client: c)
        }
        return NoDocumentRetriever()
    }

    /// Build a `MemoryService` wired to the live MCP client and the guard.
    /// Returns `nil` when MemPalace is not ready.
    func makeMemoryService() -> MemoryService? {
        guard let c = client, case .ready = status else { return nil }
        return MemoryService.mempalace(client: c, guardActor: guardActor)
    }

    // MARK: - User server management

    /// Load user servers from the store and start any with autoStart=true.
    /// Safe to call repeatedly — already-running servers are left alone.
    func reconcileUserServers() async {
        let configs = (try? await store.all()) ?? []
        let existing = Dictionary(uniqueKeysWithValues: userServers.map { ($0.id, $0) })
        var merged: [UserServer] = []
        var seen: Set<String> = []

        for cfg in configs {
            seen.insert(cfg.name)
            if var prev = existing[cfg.name] {
                // Config may have been edited; replace it.
                prev = UserServer(config: cfg, state: prev.state, tools: prev.tools)
                merged.append(prev)
            } else {
                merged.append(UserServer(config: cfg, state: .stopped, tools: []))
            }
        }

        // Stop servers the user removed from the store.
        for removed in existing.keys where !seen.contains(removed) {
            if let c = userClients.removeValue(forKey: removed) {
                await c.stop()
            }
        }

        userServers = merged

        for entry in merged where entry.config.autoStart && entry.state == .stopped {
            await startUserServer(named: entry.config.name)
        }
    }

    func addUserServer(_ config: MCPServerConfig) async {
        try? await store.upsert(config)
        await reconcileUserServers()
    }

    func updateUserServer(oldName: String, to config: MCPServerConfig) async {
        // If renamed, stop the old client and drop the old store entry.
        if oldName != config.name, let c = userClients.removeValue(forKey: oldName) {
            await c.stop()
            try? await store.delete(name: oldName)
        }
        try? await store.upsert(config)
        await reconcileUserServers()
    }

    func deleteUserServer(named name: String) async {
        if let c = userClients.removeValue(forKey: name) {
            await c.stop()
        }
        try? await store.delete(name: name)
        await reconcileUserServers()
    }

    /// Manually start a configured but stopped server.
    func startUserServer(named name: String) async {
        guard let idx = userServers.firstIndex(where: { $0.id == name }) else { return }
        guard userClients[name] == nil else { return }
        guard userServers[idx].state != .starting else { return }
        var cfg = userServers[idx].config
        // Brave's MCP server expects NDJSON stdin. Older saved configs may
        // still carry default `.contentLength` framing.
        if cfg.args.contains("@brave/brave-search-mcp-server"),
           cfg.writeFraming == .contentLength {
            cfg = MCPServerConfig(
                name: cfg.name,
                command: cfg.command,
                args: cfg.args,
                env: cfg.env,
                cwd: cfg.cwd,
                autoStart: cfg.autoStart,
                writeFraming: .ndjson
            )
            userServers[idx] = UserServer(config: cfg, state: .stopped, tools: [])
            try? await store.upsert(cfg)
        }
        userServers[idx].state = .starting
        userServers[idx].tools = []

        let c = MCPClient(config: cfg)
        do {
            try await c.start()
            let listed = await c.listTools()
            userClients[name] = c
            if let i = userServers.firstIndex(where: { $0.id == name }) {
                userServers[i].state = .ready
                userServers[i].tools = listed
            }
        } catch {
            await c.stop()
            if let i = userServers.firstIndex(where: { $0.id == name }) {
                let stderr = await c.stderrSnapshot().suffix(8).joined(separator: "\n")
                if stderr.isEmpty {
                    userServers[i].state = .failed(error.localizedDescription)
                } else {
                    userServers[i].state = .failed("\(error.localizedDescription)\n\(stderr)")
                }
                userServers[i].tools = []
            }
        }
    }

    /// Stop a running user server. Safe to call when already stopped.
    func stopUserServer(named name: String) async {
        if let c = userClients.removeValue(forKey: name) {
            await c.stop()
        }
        if let i = userServers.firstIndex(where: { $0.id == name }) {
            userServers[i].state = .stopped
            userServers[i].tools = []
        }
    }

    // MARK: - Private

    private func performStart() async {
        // Share the one MemPalace subprocess owned by `MemPalaceServer.shared`.
        // Launching a second `python -m mempalace.mcp_server` against the same
        // palace directory deadlocks on the ChromaDB lock held by the first
        // process, so the handshake never completes.
        do {
            try await MemPalaceServer.shared.start()
            guard let c = await MemPalaceServer.shared.mcpClient() else {
                throw MCPError.notInitialized
            }
            let listed = await c.listTools()
            self.client = c
            self.tools = listed
            self.status = .ready
        } catch {
            let stderr = await (MemPalaceServer.shared.mcpClient()?.stderrSnapshot() ?? [])
                .suffix(8).joined(separator: "\n")
            self.client = nil
            self.tools = []
            let base = describe(error)
            let msg = stderr.isEmpty ? base : "\(base)\n\(stderr)"
            self.status = .failed(msg)
        }

        // MemPalace result doesn't gate user-server startup — users may want
        // those even when MemPalace failed to launch (e.g. runtime missing).
        await reconcileUserServers()
    }

    private func describe(_ error: any Error) -> String {
        if let m = error as? MCPError {
            switch m {
            case .notInitialized:    return "MCP client not initialized"
            case .alreadyRunning:    return "MCP client already running"
            case .transportClosed:   return "MCP transport closed"
            case .timeout:
                return "Timed out waiting for MemPalace handshake"
            case .rpcError(let c, let msg):    return "RPC error \(c): \(msg)"
            case .decodingError(let d):         return "Decoding error: \(d)"
            case .processExited(let s):         return "Python subprocess exited with status \(s)"
            case .tooManyRestarts(let n):       return "Too many restarts (\(n))"
            case .launchFailed(let d):          return "Launch failed: \(d)"
            }
        }
        return String(describing: error)
    }

    private func stopAllUserServers() async {
        let clients = userClients
        userClients.removeAll()
        for (_, c) in clients {
            await c.stop()
        }
        userServers = userServers.map {
            UserServer(config: $0.config, state: .stopped, tools: [])
        }
    }
}
