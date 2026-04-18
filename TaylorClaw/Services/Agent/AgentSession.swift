import Foundation
import Observation

/// App-wide agent runtime: owns the MemPalace MCP client, the
/// approval prompter, and the safety guard. Used by `AgentPanel` and (in
/// Phase F2) the agent send loop.
///
/// Phase F1 only exercises lifecycle + retrieval previews + the approval
/// sheet. The send path still goes through `ChatViewModel.send()` exactly
/// as in v0.1, so chat behavior is unchanged regardless of mode.
@MainActor
@Observable
final class AgentSession {
    static let shared = AgentSession()

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

    private(set) var status: Status = .stopped
    private(set) var tools: [MCPTool] = []

    let prompter: UIApprovalPrompter
    let guardActor: AgentGuard

    private var client: MCPClient?
    private var startTask: Task<Void, Never>?

    private init() {
        let prompter = UIApprovalPrompter()
        self.prompter = prompter
        self.guardActor = AgentGuard(prompter: prompter)
    }

    // MARK: - Lifecycle

    /// Idempotent. Starts MemPalace if the runtime is installed and the
    /// client isn't already running. Re-entrant calls coalesce onto the
    /// in-flight start task.
    func ensureStarted() async {
        if case .ready = status { return }
        if case .starting = status, let task = startTask {
            await task.value
            return
        }
        guard RuntimeManager.shared.isInstalled else {
            status = .failed("Python runtime not installed")
            return
        }

        status = .starting
        let task = Task { [weak self] in
            await self?.performStart()
        }
        startTask = task
        await task.value
        startTask = nil
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        if let c = client {
            await c.stop()
        }
        client = nil
        tools = []
        status = .stopped
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

    // MARK: - Private

    private func performStart() async {
        let config = MCPServerConfig(
            name: "mempalace",
            command: RuntimeConstants.venvPython.path,
            args: [
                "-m", "mempalace.mcp_server",
                "--data-dir", RuntimeConstants.mempalaceDir.path,
            ],
            env: ["MEM_PALACE_DATA_DIR": RuntimeConstants.mempalaceDir.path],
            autoStart: true
        )
        let c = MCPClient(config: config)
        do {
            try await c.start()
            let listed = await c.listTools()
            self.client = c
            self.tools = listed
            self.status = .ready
        } catch {
            await c.stop()
            self.client = nil
            self.tools = []
            self.status = .failed(error.localizedDescription)
        }
    }
}
