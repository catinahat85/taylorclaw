import Foundation

/// Thin wrapper that launches the MemPalace MCP server under the installed
/// Python runtime and exposes it via a generic `MCPClient`.
actor MemPalaceServer {
    static let shared = MemPalaceServer()

    private var client: MCPClient?
    private var pendingClient: MCPClient?
    private var startTask: Task<MCPClient, any Error>?

    var isRunning: Bool { client != nil }

    private func config(writeFraming: MCPTransport.WriteFraming) -> MCPServerConfig {
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
            autoStart: true,
            writeFraming: writeFraming
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
        // Best-effort cleanup of orphaned MemPalace processes from previous
        // app runs. Stale servers against the same palace path can hold the
        // Chroma lock and cause new startups to hang indefinitely.
        terminateStaleProcesses()
        guard FileManager.default.fileExists(atPath: RuntimeConstants.venvPython.path) else {
            throw RuntimeError.notInstalled
        }
        let task = Task<MCPClient, any Error> { [weak self] in
            guard let self else { throw MCPError.notInitialized }
            do {
                let primaryConfig = await self.config(writeFraming: .ndjson)
                let primary = MCPClient(config: primaryConfig)
                await self.setPendingClient(primary)
                try await primary.start()
                return primary
            } catch let error as MCPError {
                if case .launchFailed(let details) = error,
                   details.contains("initialize failed: timeout") {
                    let fallbackConfig = await self.config(writeFraming: .contentLength)
                    let fallback = MCPClient(config: fallbackConfig)
                    await self.setPendingClient(fallback)
                    try await fallback.start()
                    return fallback
                }
                throw error
            }
        }
        startTask = task
        do {
            let ready = try await task.value
            self.client = ready
            self.pendingClient = nil
            self.startTask = nil
        } catch {
            if let pending = self.pendingClient {
                await pending.stop()
            }
            self.pendingClient = nil
            self.startTask = nil
            throw error
        }
    }

    private func setPendingClient(_ client: MCPClient) {
        pendingClient = client
    }

    func stop() async {
        startTask?.cancel()
        startTask = nil
        if let c = pendingClient {
            await c.stop()
            pendingClient = nil
        }
        guard let c = client else { return }
        await c.stop()
        self.client = nil
    }

    /// Expose the underlying MCP client so `AgentSession` can reuse this
    /// single Python subprocess for its agent tool-call loop. Returns the
    /// ready client when start has completed, or the in-flight client during
    /// startup (useful for reading stderr while the handshake is pending).
    func mcpClient() -> MCPClient? { client ?? pendingClient }

    // MARK: - Private

    /// Kill orphaned mempalace servers scoped to this palace path.
    /// `pkill` exits non-zero when no process matches; that's expected.
    private func terminateStaleProcesses() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = [
            "-f",
            "mempalace.mcp_server --palace \(RuntimeConstants.mempalaceDir.path)",
        ]
        do { try pkill.run() } catch { return }
        pkill.waitUntilExit()
    }

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
