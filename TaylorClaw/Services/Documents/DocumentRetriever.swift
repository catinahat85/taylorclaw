import Foundation

/// A single chunk returned from a RAG search.
struct DocumentSnippet: Sendable, Hashable, Codable {
    let text: String
    let score: Double?
    let documentID: String?
    let documentTitle: String?
    let chunkIndex: Int?

    init(
        text: String,
        score: Double? = nil,
        documentID: String? = nil,
        documentTitle: String? = nil,
        chunkIndex: Int? = nil
    ) {
        self.text = text
        self.score = score
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.chunkIndex = chunkIndex
    }
}

/// Abstracts document search. Agent mode calls this alongside the
/// `MemoryRetriever` to pull relevant chunks into the system prompt.
protocol DocumentRetriever: Sendable {
    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet]
}

/// Returns nothing. Safe default when no RAG backend is available.
struct NoDocumentRetriever: DocumentRetriever {
    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet] { [] }
}

/// Retrieves chunks by calling an MCP tool — by default MemPalace's
/// `search_documents`.
actor MCPDocumentRetriever: DocumentRetriever {
    private let client: MCPClient
    private let toolName: String
    private let queryArgKey: String
    private let limitArgKey: String

    init(
        client: MCPClient,
        toolName: String = "search_documents",
        queryArgKey: String = "query",
        limitArgKey: String = "limit"
    ) {
        self.client = client
        self.toolName = toolName
        self.queryArgKey = queryArgKey
        self.limitArgKey = limitArgKey
    }

    func retrieve(query: String, limit: Int) async throws -> [DocumentSnippet] {
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

    private static func parse(content: MCPToolCallResult.Content) -> DocumentSnippet? {
        guard content.type == "text", let text = content.text, !text.isEmpty else {
            return nil
        }
        if let data = text.data(using: .utf8),
           let snippet = try? JSONDecoder().decode(DocumentSnippet.self, from: data) {
            return snippet
        }
        return DocumentSnippet(text: text)
    }
}
