import Foundation

/// User-facing configuration describing how to launch an MCP server.
///
/// This mirrors the `mcpServers` entry format used by Claude Desktop and
/// other MCP hosts so users can paste configs they already have.
struct MCPServerConfig: Codable, Sendable, Hashable, Identifiable {
    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
    let cwd: String?
    /// Whether Taylor Claw should auto-start this server at app launch.
    let autoStart: Bool

    init(
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        cwd: String? = nil,
        autoStart: Bool = true
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.autoStart = autoStart
    }

    var id: String { name }
}
