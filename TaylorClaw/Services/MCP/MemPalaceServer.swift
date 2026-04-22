import Foundation

/// Thin wrapper that launches the MemPalace MCP server under the installed
/// Python runtime and exposes it via a generic `MCPClient`.
actor MemPalaceServer {
    static let shared = MemPalaceServer()

    private var client: MCPClient?

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

    func start() async throws {
        guard client == nil else { return }
        guard FileManager.default.fileExists(atPath: RuntimeConstants.venvPython.path) else {
            throw RuntimeError.notInstalled
        }
        let c = MCPClient(config: config)
        try await c.start()
        self.client = c
    }

    func stop() async {
        guard let c = client else { return }
        await c.stop()
        self.client = nil
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
