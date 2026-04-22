import Foundation

/// Thin wrapper that launches the MemPalace MCP server under the installed
/// Python runtime and exposes it via a generic `MCPClient`.
actor MemPalaceServer {
    static let shared = MemPalaceServer()

    private var client: MCPClient?
    private var startTask: Task<MCPClient, any Error>?

    var isRunning: Bool { client != nil }

    private var config: MCPServerConfig {
        MCPServerConfig(
            name: "mempalace",
            command: RuntimeConstants.venvPython.path,
            args: [
                "-u",
                "-m", "mempalace.mcp_server",
                "--palace", RuntimeConstants.mempalaceDir.path,
            ],
            env: [
                "PYTHONUNBUFFERED": "1",
            ],
            autoStart: true
        )
    }

    // MARK: - Lifecycle

    /// Idempotent. Concurrent callers coalesce onto a single in-flight launch
    /// task — without this, each caller's `await c.start()` suspends before
    /// `self.client` is assigned, so every guard passes and we spawn a fresh
    /// Python subprocess per caller. Two subprocesses against the same palace
    /// directory deadlock on ChromaDB's file lock and the handshake never
    /// completes.
    func start() async throws {
        if client != nil { return }
        if let existing = startTask {
            let c = try await existing.value
            if self.client == nil { self.client = c }
            return
        }
        guard FileManager.default.fileExists(atPath: RuntimeConstants.venvPython.path) else {
            throw RuntimeError.notInstalled
        }
        let cfg = config
        let task = Task<MCPClient, any Error> {
            let c = MCPClient(config: cfg)
            try await c.start()
            return c
        }
        startTask = task
        do {
            let c = try await task.value
            self.client = c
            self.startTask = nil
        } catch {
            self.startTask = nil
            throw error
        }
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        guard let c = client else { return }
        await c.stop()
        self.client = nil
    }

    /// Expose the underlying MCP client so `AgentSession` can reuse this
    /// single Python subprocess for its agent tool-call loop. Returns nil
    /// before `start()` has completed.
    func mcpClient() -> MCPClient? { client }

    // MARK: - Tool access

    func listTools() async -> [MCPTool] {
        await client?.listTools() ?? []
    }

    func callTool(name: String, arguments: JSONValue = .object([:])) async throws -> MCPToolCallResult {
        guard let c = client else { throw MCPError.notInitialized }
        return try await c.callTool(name: name, arguments: arguments)
    }

    // MARK: - Retrievers

    /// Returns an `MCPMemoryRetriever` bound to this server if it is running,
    /// otherwise `NoMemoryRetriever`. Safe to call before / after `start()`.
    func memoryRetriever() -> any MemoryRetriever {
        guard let c = client else { return NoMemoryRetriever() }
        return MCPMemoryRetriever(client: c)
    }

    /// Returns an `MCPDocumentRetriever` bound to this server if it is running,
    /// otherwise `NoDocumentRetriever`.
    func documentRetriever() -> any DocumentRetriever {
        guard let c = client else { return NoDocumentRetriever() }
        return MCPDocumentRetriever(client: c)
    }

    /// Returns an `MCPDocumentUploader` bound to this server if it is running,
    /// otherwise nil — callers fall back to local-only ingest (metadata in
    /// `DocumentStore` but no embeddings on the MemPalace side).
    func documentUploader() -> (any DocumentUploader)? {
        guard let c = client else { return nil }
        return MCPDocumentUploader(client: c)
    }
}
