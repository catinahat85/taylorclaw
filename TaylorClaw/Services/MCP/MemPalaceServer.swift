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
                "-m", "mempalace.mcp_server",
                "--data-dir", RuntimeConstants.mempalaceDir.path,
            ],
            env: ["MEM_PALACE_DATA_DIR": RuntimeConstants.mempalaceDir.path],
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
}
