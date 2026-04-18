import Foundation

/// A single piece of retrieved memory.
struct MemorySnippet: Sendable, Hashable, Codable {
    let text: String
    let score: Double?
    let source: String?

    init(text: String, score: Double? = nil, source: String? = nil) {
        self.text = text
        self.score = score
        self.source = source
    }
}

/// Abstraction over "query my past memory for things relevant to this input."
///
/// Chat mode wires up `NoMemoryRetriever`. Agent mode wires up
/// `MCPMemoryRetriever` pointed at MemPalace.
protocol MemoryRetriever: Sendable {
    func retrieve(query: String, limit: Int) async throws -> [MemorySnippet]
}

/// Returns nothing. Safe default when MemPalace isn't installed / running.
struct NoMemoryRetriever: MemoryRetriever {
    func retrieve(query: String, limit: Int) async throws -> [MemorySnippet] { [] }
}

/// Retrieves memory by calling an MCP tool on the MemPalace server.
///
/// The tool name defaults to `retrieve_memory`, which matches MemPalace's
/// default. Override `toolName` if you point at a different server.
actor MCPMemoryRetriever: MemoryRetriever {
    private let client: MCPClient
    private let toolName: String
    private let queryArgKey: String
    private let limitArgKey: String

    init(
        client: MCPClient,
        toolName: String = "retrieve_memory",
        queryArgKey: String = "query",
        limitArgKey: String = "limit"
    ) {
        self.client = client
        self.toolName = toolName
        self.queryArgKey = queryArgKey
        self.limitArgKey = limitArgKey
    }

    func retrieve(query: String, limit: Int) async throws -> [MemorySnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let args: JSONValue = .object([
            queryArgKey: .string(trimmed),
            limitArgKey: .int(Int64(limit)),
        ])
        let result = try await client.callTool(name: toolName, arguments: args)
        if result.isError == true { return [] }
        return result.content.compactMap { Self.parse(content: $0) }
    }

    private static func parse(content: MCPToolCallResult.Content) -> MemorySnippet? {
        guard content.type == "text", let text = content.text, !text.isEmpty else {
            return nil
        }
        // MemPalace may emit either plain text or a JSON object per content
        // item. Try JSON first, fall back to plain text.
        if let data = text.data(using: .utf8),
           let snippet = try? JSONDecoder().decode(MemorySnippet.self, from: data) {
            return snippet
        }
        return MemorySnippet(text: text)
    }
}
