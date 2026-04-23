import Foundation

/// User-facing configuration describing how to launch an MCP server.
///
/// This mirrors the `mcpServers` entry format used by Claude Desktop and
/// other MCP hosts so users can paste configs they already have.
struct MCPServerConfig: Codable, Sendable, Hashable, Identifiable {
    enum WriteFraming: String, Codable, Sendable, Hashable {
        case ndjson
        case contentLength
    }

    let name: String
    let command: String
    let args: [String]
    let env: [String: String]
    let cwd: String?
    /// Whether Taylor Claw should auto-start this server at app launch.
    let autoStart: Bool
    /// Stdio framing used for outbound JSON-RPC requests.
    let writeFraming: WriteFraming

    init(
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        cwd: String? = nil,
        autoStart: Bool = true,
        writeFraming: WriteFraming = .contentLength
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.autoStart = autoStart
        self.writeFraming = writeFraming
    }

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, command, args, env, cwd, autoStart, writeFraming
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.command = try c.decode(String.self, forKey: .command)
        self.args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        self.env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        self.autoStart = try c.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        self.writeFraming = try c.decodeIfPresent(WriteFraming.self, forKey: .writeFraming) ?? .contentLength
    }
}
