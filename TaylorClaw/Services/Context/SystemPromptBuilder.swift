import Foundation

/// Assembles the final system prompt for a request.
///
/// Chat mode sends an empty (or user-supplied) prompt, matching v0.1.
/// Agent mode layers on: an agent preamble, optional user override, a
/// tool summary, and a memory block when snippets are available.
struct SystemPromptBuilder: Sendable {
    let mode: ChatMode
    let userTemplate: String?
    let tools: [MCPTool]
    let memorySnippets: [MemorySnippet]
    let documentSnippets: [DocumentSnippet]

    init(
        mode: ChatMode,
        userTemplate: String? = nil,
        tools: [MCPTool] = [],
        memorySnippets: [MemorySnippet] = [],
        documentSnippets: [DocumentSnippet] = []
    ) {
        self.mode = mode
        self.userTemplate = userTemplate
        self.tools = tools
        self.memorySnippets = memorySnippets
        self.documentSnippets = documentSnippets
    }

    func build() -> String {
        switch mode {
        case .chat:
            return userTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .agent:
            return [
                Self.agentPreamble,
                userTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
                toolsSection,
                memorySection,
                documentSection,
            ]
            .compactMap { (s: String?) -> String? in
                guard let s, !s.isEmpty else { return nil }
                return s
            }
            .joined(separator: "\n\n")
        }
    }

    // MARK: - Sections

    private static let agentPreamble = """
        You are Taylor Claw, a helpful assistant running locally on macOS.

        You have access to tools via MCP servers and a persistent memory store. \
        Use tools when they are the right choice; do not call them unnecessarily. \
        When you use a tool, briefly explain what you are doing and why. \
        Never fabricate tool results.
        """

    private var toolsSection: String? {
        guard !tools.isEmpty else { return nil }
        var lines = ["## Available tools"]
        for tool in tools {
            if let desc = tool.description, !desc.isEmpty {
                lines.append("- `\(tool.name)` — \(desc)")
            } else {
                lines.append("- `\(tool.name)`")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var memorySection: String? {
        guard !memorySnippets.isEmpty else { return nil }
        var lines = ["## Relevant memory"]
        for snippet in memorySnippets {
            let source = snippet.source.map { " [\($0)]" } ?? ""
            lines.append("- \(snippet.text)\(source)")
        }
        return lines.joined(separator: "\n")
    }

    private var documentSection: String? {
        guard !documentSnippets.isEmpty else { return nil }
        var lines = ["## Relevant documents"]
        for (i, snippet) in documentSnippets.enumerated() {
            let title = snippet.documentTitle ?? "document \(i + 1)"
            lines.append("### \(title)")
            lines.append(snippet.text)
        }
        return lines.joined(separator: "\n")
    }
}
