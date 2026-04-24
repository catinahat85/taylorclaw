import Foundation

/// A lightweight template for a common MCP server.
///
/// Presets are *not* bundled runtimes — they require tools the user already
/// has on PATH (Node/`npx`, Astral's `uv`/`uvx`, etc.). The preset flow
/// pre-fills the add-server form; the user still confirms before the entry
/// is saved.
struct MCPServerPreset: Sendable, Hashable, Identifiable {
    /// Stable preset identifier (not the server name — users can rename).
    let id: String
    /// Human-readable title shown in the preset picker.
    let title: String
    /// One-line description of what the server does.
    let summary: String
    /// Runtime dependency the user must have installed (e.g. "Node (`npx`)").
    let requires: String
    /// Suggested server name for the new entry.
    let defaultName: String
    /// Command to launch the server.
    let command: String
    /// Default args template.
    let args: [String]
    /// Placeholder env vars the user is expected to fill in (API keys etc.).
    /// The value is a prompt shown next to the field in the add sheet.
    let requiredEnv: [(key: String, hint: String)]
    /// Preferred outbound stdio framing for this server.
    let writeFraming: MCPServerConfig.WriteFraming

    func makeConfig(
        name: String? = nil,
        env: [String: String] = [:],
        autoStart: Bool = true
    ) -> MCPServerConfig {
        MCPServerConfig(
            name: name ?? defaultName,
            command: command,
            args: args,
            env: env,
            cwd: nil,
            autoStart: autoStart,
            writeFraming: writeFraming
        )
    }

    // Hashable via id alone — the tuple array isn't Hashable.
    static func == (lhs: MCPServerPreset, rhs: MCPServerPreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension MCPServerPreset {
    /// Built-in preset catalog. These reference external packages users
    /// fetch themselves — we don't bundle or pin them.
    static let catalog: [MCPServerPreset] = [
        braveSearch,
        fetch,
        filesystem,
    ]

    /// Anthropic's Brave Search MCP server. Needs a Brave Search API key.
    static let braveSearch = MCPServerPreset(
        id: "brave-search",
        title: "Brave Search",
        summary: "Web + local search via the Brave Search API.",
        requires: "Node (`npx`)",
        defaultName: "brave-search",
        command: "npx",
        args: ["-y", "@brave/brave-search-mcp-server", "--transport", "stdio"],
        requiredEnv: [
            ("BRAVE_API_KEY", "Brave Search API key (brave.com/search/api)"),
        ],
        writeFraming: .contentLength
    )

    /// Reference `fetch` server — lets the agent retrieve arbitrary URLs.
    static let fetch = MCPServerPreset(
        id: "fetch",
        title: "Fetch",
        summary: "Retrieve URLs and convert HTML to markdown.",
        requires: "Astral `uv` / `uvx`",
        defaultName: "fetch",
        command: "uvx",
        args: ["mcp-server-fetch"],
        requiredEnv: [],
        writeFraming: .contentLength
    )

    /// Reference filesystem server, scoped to a user-chosen directory.
    /// The user edits `args` after creation to point at the directory.
    static let filesystem = MCPServerPreset(
        id: "filesystem",
        title: "Filesystem",
        summary: "Read-write access to files under a scoped root.",
        requires: "Node (`npx`)",
        defaultName: "filesystem",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "~/Documents"],
        requiredEnv: [],
        writeFraming: .contentLength
    )
}
